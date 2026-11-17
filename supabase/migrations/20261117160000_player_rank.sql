-- ============================================================
-- Звание игрока в профиле (ранги игры)
-- ============================================================
ALTER TABLE public.profiles ADD COLUMN IF NOT EXISTS rank text;
ALTER TABLE public.profiles DROP CONSTRAINT IF EXISTS profiles_rank_check;
ALTER TABLE public.profiles ADD CONSTRAINT profiles_rank_check
  CHECK (rank IS NULL OR rank IN ('NEWBIE','STALKER','VETERAN','MASTER','LEGEND'));
