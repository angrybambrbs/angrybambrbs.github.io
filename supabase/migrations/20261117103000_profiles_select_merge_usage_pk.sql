-- 1. Одна SELECT-политика вместо трёх (устраняет multiple_permissive_policies)
--    и возвращает видимость собственного профиля, которую раньше давала ALL-политика.
DROP POLICY IF EXISTS profiles_applicants ON public.profiles;
DROP POLICY IF EXISTS profiles_clanmates ON public.profiles;
DROP POLICY IF EXISTS profiles_select_own ON public.profiles;
DROP POLICY IF EXISTS profiles_select ON public.profiles;
CREATE POLICY profiles_select ON public.profiles FOR SELECT TO public
  USING (
    user_id = (select auth.uid())
    OR shares_clan_with(user_id)
    OR EXISTS (
      SELECT 1 FROM clan_applications a
      WHERE a.user_id = profiles.user_id
        AND a.status = 'pending'
        AND can_edit_clan(a.clan_id)
    )
  );

-- 2. Первичный ключ для таблицы учёта распознаваний
ALTER TABLE public.parse_battle_usage
  ADD COLUMN IF NOT EXISTS id bigint GENERATED ALWAYS AS IDENTITY;
DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'parse_battle_usage_pkey') THEN
    ALTER TABLE public.parse_battle_usage ADD CONSTRAINT parse_battle_usage_pkey PRIMARY KEY (id);
  END IF;
END $$;
