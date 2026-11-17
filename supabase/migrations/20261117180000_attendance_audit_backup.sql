-- ============================================================
-- Предупреждения по явке, журнал действий, приветствие новичка,
-- ежедневная копия данных. Применено через Supabase MCP.
-- ============================================================

-- 1. Журнал действий лидера
create table if not exists public.clan_audit_log (
  id bigserial primary key,
  clan_id uuid not null references public.clans(id) on delete cascade,
  actor_id uuid,
  actor_name text,
  action text not null,
  target_user_id uuid,
  target_name text,
  details jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now()
);
create index if not exists clan_audit_log_clan_created_idx
  on public.clan_audit_log (clan_id, created_at desc);
alter table public.clan_audit_log enable row level security;
revoke all on public.clan_audit_log from anon, authenticated;
grant select on public.clan_audit_log to authenticated;
drop policy if exists audit_select on public.clan_audit_log;
create policy audit_select on public.clan_audit_log
  for select to authenticated using (public.can_edit_clan(clan_id));

create or replace function public.log_clan_member_change()
returns trigger language plpgsql security definer set search_path = 'public'
as $$
declare
  v_actor uuid := auth.uid();
  v_actor_name text;
  v_clan uuid := coalesce(NEW.clan_id, OLD.clan_id);
  v_target uuid := coalesce(NEW.user_id, OLD.user_id);
  v_target_name text;
begin
  v_actor_name := coalesce(
    (select name from public.user_cards where user_id = v_actor),
    (select display_name from public.clan_members where clan_id = v_clan and user_id = v_actor),
    'система'
  );
  v_target_name := coalesce(
    NEW.display_name, OLD.display_name,
    (select nickname from public.profiles where user_id = v_target),
    'игрок'
  );

  if TG_OP = 'INSERT' then
    insert into public.clan_audit_log (clan_id, actor_id, actor_name, action, target_user_id, target_name, details)
    values (NEW.clan_id, v_actor, v_actor_name, 'member_joined', NEW.user_id, v_target_name,
            jsonb_build_object('rank', NEW.rank, 'role', NEW.role));
  elsif TG_OP = 'DELETE' then
    insert into public.clan_audit_log (clan_id, actor_id, actor_name, action, target_user_id, target_name, details)
    values (OLD.clan_id, v_actor, v_actor_name, 'member_removed', OLD.user_id, v_target_name,
            jsonb_build_object('rank', OLD.rank, 'role', OLD.role));
  else
    if NEW.rank is distinct from OLD.rank then
      insert into public.clan_audit_log (clan_id, actor_id, actor_name, action, target_user_id, target_name, details)
      values (NEW.clan_id, v_actor, v_actor_name, 'rank_changed', NEW.user_id, v_target_name,
              jsonb_build_object('old', OLD.rank, 'new', NEW.rank));
    end if;
    if NEW.role is distinct from OLD.role then
      insert into public.clan_audit_log (clan_id, actor_id, actor_name, action, target_user_id, target_name, details)
      values (NEW.clan_id, v_actor, v_actor_name, 'role_changed', NEW.user_id, v_target_name,
              jsonb_build_object('old', OLD.role, 'new', NEW.role));
    end if;
  end if;

  if TG_OP = 'DELETE' then return OLD; end if;
  return NEW;
end $$;

drop trigger if exists audit_clan_members on public.clan_members;
create trigger audit_clan_members after insert or update or delete on public.clan_members
  for each row execute function public.log_clan_member_change();

create or replace function public.log_application_decision()
returns trigger language plpgsql security definer set search_path = 'public'
as $$
declare
  v_actor uuid := auth.uid();
  v_actor_name text;
  v_target_name text;
begin
  if OLD.status = 'pending' and NEW.status in ('accepted', 'rejected') then
    v_actor_name := coalesce(
      (select name from public.user_cards where user_id = v_actor),
      (select display_name from public.clan_members where clan_id = NEW.clan_id and user_id = v_actor),
      'лидер'
    );
    v_target_name := coalesce((select nickname from public.profiles where user_id = NEW.user_id), 'игрок');
    insert into public.clan_audit_log (clan_id, actor_id, actor_name, action, target_user_id, target_name, details)
    values (NEW.clan_id, v_actor, v_actor_name,
            case when NEW.status = 'accepted' then 'application_accepted' else 'application_rejected' end,
            NEW.user_id, v_target_name,
            jsonb_build_object('application_id', NEW.id, 'message', NEW.message));
  end if;
  return NEW;
end $$;

drop trigger if exists audit_clan_applications on public.clan_applications;
create trigger audit_clan_applications after update of status on public.clan_applications
  for each row execute function public.log_application_decision();

-- 2. Звание по умолчанию + приветствие новичка
alter table public.clan_members alter column rank set default 'PRIVATE';
update public.clan_members set rank = 'LEADER' where role = 'owner' and (rank is null or rank <> 'LEADER');

create or replace function public.ensure_clan_rank()
returns trigger language plpgsql set search_path = 'public'
as $$
begin
  if NEW.role = 'owner' then
    NEW.rank := 'LEADER';
  elsif NEW.rank is null then
    NEW.rank := 'PRIVATE';
  end if;
  return NEW;
end $$;

drop trigger if exists ensure_clan_rank on public.clan_members;
create trigger ensure_clan_rank before insert or update of role, rank on public.clan_members
  for each row execute function public.ensure_clan_rank();

create or replace function public.welcome_new_member()
returns trigger language plpgsql security definer set search_path = 'public'
as $$
declare
  v_curator uuid;
  v_curator_name text;
  v_name text;
  v_rank text;
begin
  if NEW.role = 'owner' then return NEW; end if;

  v_curator := case
    when auth.uid() is not null and auth.uid() <> NEW.user_id then auth.uid()
    else (select owner_id from public.clans where id = NEW.clan_id)
  end;
  v_curator_name := coalesce(
    (select name from public.user_cards where user_id = v_curator),
    (select display_name from public.clan_members where clan_id = NEW.clan_id and user_id = v_curator),
    'лидер клана'
  );
  v_name := coalesce(NEW.display_name, (select nickname from public.profiles where user_id = NEW.user_id), 'новичок');
  v_rank := case NEW.rank
    when 'RESERVE' then 'Запасной' when 'PRIVATE' then 'Рядовой' when 'FIGHTER' then 'Боец'
    when 'SERGEANT' then 'Сержант' when 'OFFICER' then 'Офицер' when 'COLONEL' then 'Полковник'
    when 'CALLER' then 'Колер' when 'LEADER' then 'Лидер' else 'Рядовой'
  end;

  insert into public.clan_messages (clan_id, user_id, body)
  values (NEW.clan_id, v_curator,
          format('Добро пожаловать, %s! Звание: %s. Куратор: %s.', v_name, v_rank, v_curator_name));
  return NEW;
end $$;

drop trigger if exists welcome_new_member on public.clan_members;
create trigger welcome_new_member after insert on public.clan_members
  for each row execute function public.welcome_new_member();

-- 3. Ежедневная копия данных (снимок ключевых таблиц)
create extension if not exists pg_cron with schema extensions;

create table if not exists public.data_backups (
  id bigserial primary key,
  created_at timestamptz not null default now(),
  label text not null default 'daily',
  data jsonb not null
);
alter table public.data_backups enable row level security;
revoke all on public.data_backups from anon, authenticated;

create or replace function public.create_data_backup(p_token text default null)
returns bigint language plpgsql security definer set search_path = 'public'
as $$
declare
  v_expected text;
  v_data jsonb;
  v_id bigint;
begin
  if p_token is not null then
    select decrypted_secret into v_expected from vault.decrypted_secrets where name = 'clanpulse_backup_token';
    if v_expected is null or v_expected <> p_token then
      raise exception 'Неверный токен резервной копии';
    end if;
  end if;

  select jsonb_build_object(
    'profiles', (select coalesce(jsonb_agg(to_jsonb(t)), '[]'::jsonb) from public.profiles t),
    'user_cards', (select coalesce(jsonb_agg(to_jsonb(t)), '[]'::jsonb) from public.user_cards t),
    'clans', (select coalesce(jsonb_agg(to_jsonb(t)), '[]'::jsonb) from public.clans t),
    'clan_members', (select coalesce(jsonb_agg(to_jsonb(t)), '[]'::jsonb) from public.clan_members t),
    'clan_invites', (select coalesce(jsonb_agg(to_jsonb(t)), '[]'::jsonb) from public.clan_invites t),
    'clan_applications', (select coalesce(jsonb_agg(to_jsonb(t)), '[]'::jsonb) from public.clan_applications t),
    'players', (select coalesce(jsonb_agg(to_jsonb(t)), '[]'::jsonb) from public.players t),
    'squads', (select coalesce(jsonb_agg(to_jsonb(t)), '[]'::jsonb) from public.squads t),
    'matches', (select coalesce(jsonb_agg(to_jsonb(t)), '[]'::jsonb) from public.matches t),
    'match_stats', (select coalesce(jsonb_agg(to_jsonb(t)), '[]'::jsonb) from public.match_stats t),
    'clan_events', (select coalesce(jsonb_agg(to_jsonb(t)), '[]'::jsonb) from public.clan_events t),
    'event_rsvps', (select coalesce(jsonb_agg(to_jsonb(t)), '[]'::jsonb) from public.event_rsvps t),
    'clan_messages', (select coalesce(jsonb_agg(to_jsonb(t)), '[]'::jsonb) from public.clan_messages t),
    'direct_messages', (select coalesce(jsonb_agg(to_jsonb(t)), '[]'::jsonb) from public.direct_messages t),
    'notifications', (select coalesce(jsonb_agg(to_jsonb(t)), '[]'::jsonb) from public.notifications t),
    'clan_verifications', (select coalesce(jsonb_agg(to_jsonb(t)), '[]'::jsonb) from public.clan_verifications t),
    'platform_admins', (select coalesce(jsonb_agg(to_jsonb(t)), '[]'::jsonb) from public.platform_admins t),
    'parse_battle_usage', (select coalesce(jsonb_agg(to_jsonb(t)), '[]'::jsonb) from public.parse_battle_usage t),
    'player_totals', (select coalesce(jsonb_agg(to_jsonb(t)), '[]'::jsonb) from public.player_totals t),
    'clan_audit_log', (select coalesce(jsonb_agg(to_jsonb(t)), '[]'::jsonb) from public.clan_audit_log t)
  ) into v_data;

  insert into public.data_backups (label, data)
  values (case when p_token is null then 'daily' else 'manual' end, v_data)
  returning id into v_id;

  delete from public.data_backups
   where label = 'daily' and created_at < now() - interval '30 days';
  return v_id;
end $$;

revoke all on function public.create_data_backup(text) from public, anon, authenticated;

do $$
begin
  if not exists (select 1 from vault.secrets where name = 'clanpulse_backup_token') then
    perform vault.create_secret(
      replace(gen_random_uuid()::text, '-', '') || replace(gen_random_uuid()::text, '-', ''),
      'clanpulse_backup_token',
      'Токен ежедневного снимка ClanPulse'
    );
  end if;
end $$;

do $$
begin
  perform cron.unschedule('clanpulse-daily-backup');
exception when others then null;
end $$;
select cron.schedule('clanpulse-daily-backup', '17 3 * * *', 'select public.create_data_backup();');

select public.create_data_backup();
