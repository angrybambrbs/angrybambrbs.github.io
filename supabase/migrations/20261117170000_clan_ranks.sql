-- ============================================================
-- Клановые звания (назначаются лидером клана)
-- ============================================================
ALTER TABLE public.clan_members ADD COLUMN IF NOT EXISTS rank text;
UPDATE public.clan_members
   SET rank = CASE role WHEN 'owner' THEN 'LEADER' WHEN 'officer' THEN 'OFFICER' ELSE 'PRIVATE' END
 WHERE rank IS NULL;
ALTER TABLE public.clan_members DROP CONSTRAINT IF EXISTS clan_members_rank_check;
ALTER TABLE public.clan_members ADD CONSTRAINT clan_members_rank_check
  CHECK (rank IS NULL OR rank IN ('RESERVE','PRIVATE','FIGHTER','SERGEANT','OFFICER','COLONEL','CALLER','LEADER'));

-- Убираем прежнее «самостоятельное» звание из профиля
ALTER TABLE public.profiles DROP CONSTRAINT IF EXISTS profiles_rank_check;
ALTER TABLE public.profiles DROP COLUMN IF EXISTS rank;
