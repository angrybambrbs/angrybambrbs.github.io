-- Календарь: связь событий с боями, напоминания и еженедельная сводка

alter table public.clan_events
  add column if not exists match_id uuid references public.matches(id) on delete set null,
  add column if not exists reminded_at timestamptz;
create index if not exists clan_events_clan_starts_idx on public.clan_events (clan_id, starts_at);

create table if not exists public.clan_digests (
  clan_id uuid primary key references public.clans(id) on delete cascade,
  sent_at timestamptz not null default now(),
  body text not null
);
alter table public.clan_digests enable row level security;
revoke all on public.clan_digests from anon, authenticated;

create or replace function public.send_event_reminders()
returns integer language plpgsql security definer set search_path = 'public'
as $$
declare e record; v_cnt integer := 0;
begin
  for e in select id, clan_id, title, note, starts_at, created_by from public.clan_events
    where reminded_at is null and starts_at > now() and starts_at <= now() + interval '30 hours'
  loop
    insert into public.notifications (user_id, type, title, body, href, actor_id)
    select cm.user_id, 'rsvp', 'Скоро событие',
           coalesce(e.title, 'Событие клана') ||
             case when e.note is not null and e.note <> '' then ': ' || left(e.note, 140) else '' end,
           '#events', e.created_by
    from public.clan_members cm where cm.clan_id = e.clan_id;
    update public.clan_events set reminded_at = now() where id = e.id;
    v_cnt := v_cnt + 1;
  end loop;
  return v_cnt;
end $$;
revoke all on function public.send_event_reminders() from public, anon, authenticated;

create or replace function public.send_weekly_digest()
returns integer language plpgsql security definer set search_path = 'public'
as $$
declare c record; s record; v_top text; v_miss text; v_new text; v_events integer; v_body text; v_sent integer := 0;
begin
  for c in select id, name from public.clans loop
    select count(distinct m.id) as n,
      count(distinct m.id) filter (where lower(coalesce(m.result, '')) like '%побед%' or m.place = 1) as w,
      coalesce(sum(st.k), 0) as k, coalesce(sum(st.d), 0) as d
    into s
    from public.matches m
    left join (select match_id,
      sum(case when not (kills=0 and deaths=0 and assists=0 and score=0) then kills else 0 end) as k,
      sum(case when not (kills=0 and deaths=0 and assists=0 and score=0) then deaths else 0 end) as d
      from public.match_stats where confirmed = true group by match_id) st on st.match_id = m.id
    where m.clan_id = c.id and m.played_at >= now() - interval '7 days';

    select p.nick into v_top from public.players p
    join public.match_stats st on st.player_id=p.id and st.confirmed=true
    where p.clan_id=c.id and p.active=true
      and not (st.kills=0 and st.deaths=0 and st.assists=0 and st.score=0)
    group by p.id,p.nick
    order by sum(st.kills)::numeric/greatest(sum(st.deaths),1) desc, sum(st.kills) desc limit 1;

    select string_agg(x.nick || ' (' || x.n || '/' || x.tot || ')', ', ' order by x.n::numeric/greatest(x.tot,1)) into v_miss
    from (select p.nick,
      (select count(*) from public.match_stats st join public.matches mm on mm.id=st.match_id
       where st.player_id=p.id and st.confirmed=true
         and not (st.kills=0 and st.deaths=0 and st.assists=0 and st.score=0)
         and mm.played_at >= now() - interval '7 days') as n,
      (select count(*) from public.matches mm where mm.clan_id=c.id
         and mm.played_at >= now() - interval '7 days'
         and (p.joined_at is null or mm.played_at >= p.joined_at)) as tot
      from public.players p where p.clan_id=c.id and p.active=true) x
    where x.tot > 0 and x.n::numeric/x.tot < 0.6;

    select string_agg(nick, ', ' order by nick) into v_new from public.players
    where clan_id=c.id and active=true and joined_at >= current_date - 7;

    select count(*) into v_events from public.clan_events
    where clan_id=c.id and starts_at >= now() and starts_at <= now() + interval '7 days';

    v_body := 'Боёв: ' || s.n || ', побед: ' || s.w || ', винрейт: ' ||
      case when s.n>0 then round(s.w::numeric/s.n*100) || '%' else '—' end ||
      ', K/D: ' || case when s.d>0 then round(s.k::numeric/s.d,2)::text else '—' end || '.';
    if v_top is not null then v_body := v_body || ' Лучший K/D: ' || v_top || '.'; end if;
    if v_miss is not null then v_body := v_body || ' Пропуски: ' || v_miss || '.'; end if;
    if v_new is not null then v_body := v_body || ' Новички: ' || v_new || '.'; end if;
    if v_events > 0 then v_body := v_body || ' Ближайших событий: ' || v_events || '.'; end if;

    insert into public.notifications (user_id,type,title,body,href)
    select cm.user_id,'digest','Сводка недели',v_body,'#stats'
    from public.clan_members cm where cm.clan_id=c.id;

    insert into public.clan_digests (clan_id,sent_at,body) values (c.id,now(),v_body)
    on conflict (clan_id) do update set sent_at=excluded.sent_at, body=excluded.body;
    v_sent := v_sent + 1;
  end loop;
  return v_sent;
end $$;
revoke all on function public.send_weekly_digest() from public, anon, authenticated;

create extension if not exists pg_cron with schema extensions;
do $$ begin perform cron.unschedule('clanpulse-event-reminders'); exception when others then null; end $$;
do $$ begin perform cron.unschedule('clanpulse-weekly-digest'); exception when others then null; end $$;
select cron.schedule('clanpulse-event-reminders','0 8 * * *','select public.send_event_reminders();');
select cron.schedule('clanpulse-weekly-digest','0 9 * * 1','select public.send_weekly_digest();');
