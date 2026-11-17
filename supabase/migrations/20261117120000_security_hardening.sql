-- ============================================================
-- Миграция: усиление безопасности и производительности
-- Дата: 2026-11-17
-- Применение: Supabase Dashboard -> SQL Editor -> вставить целиком -> Run
-- Все операции идемпотентны, повторный запуск безопасен.
-- ============================================================

-- ------------------------------------------------------------
-- 1. Индексы на внешние ключи (находка linter'а unindexed_foreign_keys)
-- ------------------------------------------------------------
CREATE INDEX IF NOT EXISTS clan_applications_user_idx ON public.clan_applications (user_id);
CREATE INDEX IF NOT EXISTS clan_events_created_by_idx ON public.clan_events (created_by);
CREATE INDEX IF NOT EXISTS clan_invites_clan_idx ON public.clan_invites (clan_id);
CREATE INDEX IF NOT EXISTS clan_invites_created_by_idx ON public.clan_invites (created_by);
CREATE INDEX IF NOT EXISTS clan_members_user_idx ON public.clan_members (user_id);
CREATE INDEX IF NOT EXISTS clan_messages_user_idx ON public.clan_messages (user_id);
CREATE INDEX IF NOT EXISTS clan_verifications_reviewed_by_idx ON public.clan_verifications (reviewed_by);
CREATE INDEX IF NOT EXISTS clans_owner_idx ON public.clans (owner_id);
CREATE INDEX IF NOT EXISTS event_rsvps_user_idx ON public.event_rsvps (user_id);
CREATE INDEX IF NOT EXISTS match_stats_player_idx ON public.match_stats (player_id);
CREATE INDEX IF NOT EXISTS matches_created_by_idx ON public.matches (created_by);
CREATE INDEX IF NOT EXISTS players_user_idx ON public.players (user_id);

-- ------------------------------------------------------------
-- 2. Политики RLS: auth.uid() -> (select auth.uid())
--    (находка linter'а auth_rls_initplan: вызов auth-функции
--    выносится в initplan и не выполняется на каждую строку)
--    Логика политик НЕ меняется, только форма записи.
-- ------------------------------------------------------------
DROP POLICY IF EXISTS clans_select ON public.clans;
CREATE POLICY clans_select ON public.clans FOR SELECT TO public
  USING (owner_id = (select auth.uid()) OR is_clan_member(id));

DROP POLICY IF EXISTS clans_insert ON public.clans;
CREATE POLICY clans_insert ON public.clans FOR INSERT TO public
  WITH CHECK (owner_id = (select auth.uid()));

DROP POLICY IF EXISTS clans_update ON public.clans;
CREATE POLICY clans_update ON public.clans FOR UPDATE TO public
  USING (owner_id = (select auth.uid()))
  WITH CHECK (owner_id = (select auth.uid()));

DROP POLICY IF EXISTS clans_delete ON public.clans;
CREATE POLICY clans_delete ON public.clans FOR DELETE TO public
  USING (owner_id = (select auth.uid()));

DROP POLICY IF EXISTS apps_select ON public.clan_applications;
CREATE POLICY apps_select ON public.clan_applications FOR SELECT TO public
  USING (user_id = (select auth.uid()) OR can_edit_clan(clan_id));

DROP POLICY IF EXISTS apps_withdraw ON public.clan_applications;
CREATE POLICY apps_withdraw ON public.clan_applications FOR UPDATE TO public
  USING (user_id = (select auth.uid()) AND status = 'pending')
  WITH CHECK (user_id = (select auth.uid()) AND status = 'withdrawn');

-- profiles_own была ALL и дублировала три SELECT-политики:
-- разворачиваем на INSERT/UPDATE/DELETE (SELECT остаётся в других политиках)
DROP POLICY IF EXISTS profiles_own ON public.profiles;
CREATE POLICY profiles_insert ON public.profiles FOR INSERT TO public
  WITH CHECK (user_id = (select auth.uid()));
CREATE POLICY profiles_update ON public.profiles FOR UPDATE TO public
  USING (user_id = (select auth.uid()))
  WITH CHECK (user_id = (select auth.uid()));
CREATE POLICY profiles_delete ON public.profiles FOR DELETE TO public
  USING (user_id = (select auth.uid()));

DROP POLICY IF EXISTS cards_select ON public.user_cards;
CREATE POLICY cards_select ON public.user_cards FOR SELECT TO public
  USING ((select auth.uid()) IS NOT NULL);

DROP POLICY IF EXISTS cm_insert ON public.clan_messages;
CREATE POLICY cm_insert ON public.clan_messages FOR INSERT TO public
  WITH CHECK (
    user_id = (select auth.uid())
    AND is_clan_member(clan_id)
    AND (can_edit_clan(clan_id) OR EXISTS (
      SELECT 1 FROM clans c
      WHERE c.id = clan_messages.clan_id AND c.chat_mode = 'open'
    ))
  );

DROP POLICY IF EXISTS cm_delete ON public.clan_messages;
CREATE POLICY cm_delete ON public.clan_messages FOR DELETE TO public
  USING (user_id = (select auth.uid()) OR can_edit_clan(clan_id));

DROP POLICY IF EXISTS dm_select ON public.direct_messages;
CREATE POLICY dm_select ON public.direct_messages FOR SELECT TO public
  USING (sender_id = (select auth.uid()) OR recipient_id = (select auth.uid()));

DROP POLICY IF EXISTS dm_insert ON public.direct_messages;
CREATE POLICY dm_insert ON public.direct_messages FOR INSERT TO public
  WITH CHECK (sender_id = (select auth.uid()));

DROP POLICY IF EXISTS dm_read ON public.direct_messages;
CREATE POLICY dm_read ON public.direct_messages FOR UPDATE TO public
  USING (recipient_id = (select auth.uid()))
  WITH CHECK (recipient_id = (select auth.uid()));

-- ------------------------------------------------------------
-- 3. ALL-политики -> раздельные INSERT/UPDATE/DELETE
--    (находка linter'а multiple_permissive_policies:
--    политика ALL неявно включает SELECT и дублирует
--    уже существующие SELECT-политики тех же таблиц)
-- ------------------------------------------------------------
DROP POLICY IF EXISTS ev_write ON public.clan_events;
CREATE POLICY ev_insert ON public.clan_events FOR INSERT TO public WITH CHECK (can_edit_clan(clan_id));
CREATE POLICY ev_update ON public.clan_events FOR UPDATE TO public
  USING (can_edit_clan(clan_id)) WITH CHECK (can_edit_clan(clan_id));
CREATE POLICY ev_delete ON public.clan_events FOR DELETE TO public USING (can_edit_clan(clan_id));

DROP POLICY IF EXISTS rsvp_write ON public.event_rsvps;
CREATE POLICY rsvp_insert ON public.event_rsvps FOR INSERT TO public
  WITH CHECK (user_id = (select auth.uid()) AND EXISTS (
    SELECT 1 FROM clan_events e
    WHERE e.id = event_rsvps.event_id AND is_clan_member(e.clan_id)
  ));
CREATE POLICY rsvp_update ON public.event_rsvps FOR UPDATE TO public
  USING (user_id = (select auth.uid()))
  WITH CHECK (user_id = (select auth.uid()) AND EXISTS (
    SELECT 1 FROM clan_events e
    WHERE e.id = event_rsvps.event_id AND is_clan_member(e.clan_id)
  ));
CREATE POLICY rsvp_delete ON public.event_rsvps FOR DELETE TO public
  USING (user_id = (select auth.uid()));

DROP POLICY IF EXISTS matches_write ON public.matches;
CREATE POLICY matches_insert ON public.matches FOR INSERT TO public WITH CHECK (can_edit_clan(clan_id));
CREATE POLICY matches_update ON public.matches FOR UPDATE TO public
  USING (can_edit_clan(clan_id)) WITH CHECK (can_edit_clan(clan_id));
CREATE POLICY matches_delete ON public.matches FOR DELETE TO public USING (can_edit_clan(clan_id));

DROP POLICY IF EXISTS match_stats_write ON public.match_stats;
CREATE POLICY match_stats_insert ON public.match_stats FOR INSERT TO public WITH CHECK (can_edit_clan(clan_id));
CREATE POLICY match_stats_update ON public.match_stats FOR UPDATE TO public
  USING (can_edit_clan(clan_id)) WITH CHECK (can_edit_clan(clan_id));
CREATE POLICY match_stats_delete ON public.match_stats FOR DELETE TO public USING (can_edit_clan(clan_id));

DROP POLICY IF EXISTS players_write ON public.players;
CREATE POLICY players_insert ON public.players FOR INSERT TO public WITH CHECK (can_edit_clan(clan_id));
CREATE POLICY players_update ON public.players FOR UPDATE TO public
  USING (can_edit_clan(clan_id)) WITH CHECK (can_edit_clan(clan_id));
CREATE POLICY players_delete ON public.players FOR DELETE TO public USING (can_edit_clan(clan_id));

DROP POLICY IF EXISTS squads_write ON public.squads;
CREATE POLICY squads_insert ON public.squads FOR INSERT TO public WITH CHECK (can_edit_clan(clan_id));
CREATE POLICY squads_update ON public.squads FOR UPDATE TO public
  USING (can_edit_clan(clan_id)) WITH CHECK (can_edit_clan(clan_id));
CREATE POLICY squads_delete ON public.squads FOR DELETE TO public USING (can_edit_clan(clan_id));

-- ------------------------------------------------------------
-- 4. search_path у триггерной функции (находка function_search_path_mutable).
--    Тело функции не обращается к объектам по неквалифицированным именам,
--    поэтому пустой search_path безопасен.
-- ------------------------------------------------------------
ALTER FUNCTION public.protect_clan_verification() SET search_path = '';

-- ------------------------------------------------------------
-- 5. REVOKE EXECUTE от anon на мутационные RPC.
--    Все они требуют авторизацию внутри (auth.uid()), но нет смысла
--    давать anon возможность даже дёргать их. Helper-функции
--    (can_edit_clan, is_clan_member, is_clan_owner, is_platform_admin,
--    shares_clan_with) оставлены доступны: они используются в политиках.
-- ------------------------------------------------------------
REVOKE EXECUTE ON FUNCTION public.add_owner_member() FROM anon;
REVOKE EXECUTE ON FUNCTION public.handle_new_user_card() FROM anon;
REVOKE EXECUTE ON FUNCTION public.touch_card() FROM anon;
REVOKE EXECUTE ON FUNCTION public.touch_member(uuid) FROM anon;
REVOKE EXECUTE ON FUNCTION public.apply_to_clan(uuid, text) FROM anon;
REVOKE EXECUTE ON FUNCTION public.create_invite(uuid, text) FROM anon;
REVOKE EXECUTE ON FUNCTION public.decide_application(uuid, boolean) FROM anon;
REVOKE EXECUTE ON FUNCTION public.join_clan(text) FROM anon;
REVOKE EXECUTE ON FUNCTION public.request_verification(uuid, text, text, text, text) FROM anon;
REVOKE EXECUTE ON FUNCTION public.review_verification(uuid, boolean, text, text) FROM anon;

-- ------------------------------------------------------------
-- 6. Таблица учёта вызовов parse-battle (rate-limit на стороне Edge Function).
--    Пишется только из Edge Function через service-role ключ,
--    поэтому политик нет — клиенты её не видят вообще.
-- ------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.parse_battle_usage (
  user_id uuid NOT NULL,
  created_at timestamptz NOT NULL DEFAULT now()
);
ALTER TABLE public.parse_battle_usage ENABLE ROW LEVEL SECURITY;
CREATE INDEX IF NOT EXISTS parse_battle_usage_user_time_idx
  ON public.parse_battle_usage (user_id, created_at DESC);
