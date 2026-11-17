-- ============================================================
-- Уведомления: заявки, ЛС, RSVP, запросы верификации
-- ============================================================
CREATE TABLE IF NOT EXISTS public.notifications (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id uuid NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  type text NOT NULL CHECK (type IN ('application','dm','rsvp','verification')),
  title text NOT NULL,
  body text,
  href text,
  actor_id uuid REFERENCES auth.users(id) ON DELETE SET NULL,
  created_at timestamptz NOT NULL DEFAULT now(),
  read_at timestamptz
);
CREATE INDEX IF NOT EXISTS notifications_user_time_idx ON public.notifications (user_id, created_at DESC);
ALTER TABLE public.notifications ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS notifications_select ON public.notifications;
CREATE POLICY notifications_select ON public.notifications FOR SELECT TO public
  USING (user_id = (select auth.uid()));
DROP POLICY IF EXISTS notifications_read ON public.notifications;
CREATE POLICY notifications_read ON public.notifications FOR UPDATE TO public
  USING (user_id = (select auth.uid()))
  WITH CHECK (user_id = (select auth.uid()));
DROP POLICY IF EXISTS notifications_delete ON public.notifications;
CREATE POLICY notifications_delete ON public.notifications FOR DELETE TO public
  USING (user_id = (select auth.uid()));

-- Realtime
DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_publication_tables WHERE pubname='supabase_realtime' AND schemaname='public' AND tablename='notifications') THEN
    ALTER PUBLICATION supabase_realtime ADD TABLE public.notifications;
  END IF;
END $$;

-- 1. Новая заявка -> владельцу клана
CREATE OR REPLACE FUNCTION public.notify_new_application() RETURNS trigger
LANGUAGE plpgsql SECURITY DEFINER SET search_path = '' AS $$
BEGIN
  INSERT INTO public.notifications (user_id, type, title, body, href, actor_id)
  SELECT c.owner_id, 'application', 'Заявка в ' || c.name,
         coalesce(uc.name, 'Игрок') || ' хочет вступить в клан',
         '#apps', NEW.user_id
  FROM public.clans c
  LEFT JOIN public.user_cards uc ON uc.user_id = NEW.user_id
  WHERE c.id = NEW.clan_id AND c.owner_id IS DISTINCT FROM NEW.user_id;
  RETURN NEW;
END $$;
DROP TRIGGER IF EXISTS trg_notify_application ON public.clan_applications;
CREATE TRIGGER trg_notify_application AFTER INSERT ON public.clan_applications
  FOR EACH ROW EXECUTE FUNCTION public.notify_new_application();

-- 2. Новое личное сообщение -> получателю
CREATE OR REPLACE FUNCTION public.notify_new_dm() RETURNS trigger
LANGUAGE plpgsql SECURITY DEFINER SET search_path = '' AS $$
BEGIN
  INSERT INTO public.notifications (user_id, type, title, body, href, actor_id)
  SELECT NEW.recipient_id, 'dm', 'Личное сообщение',
         coalesce(uc.name, 'Кто-то') || ': ' || left(NEW.body, 120),
         '#dm', NEW.sender_id
  FROM public.user_cards uc
  WHERE uc.user_id = NEW.sender_id
     OR NOT EXISTS (SELECT 1 FROM public.user_cards WHERE user_id = NEW.sender_id);
  RETURN NEW;
END $$;
DROP TRIGGER IF EXISTS trg_notify_dm ON public.direct_messages;
CREATE TRIGGER trg_notify_dm AFTER INSERT ON public.direct_messages
  FOR EACH ROW EXECUTE FUNCTION public.notify_new_dm();

-- 3. RSVP на событие -> автору события
CREATE OR REPLACE FUNCTION public.notify_new_rsvp() RETURNS trigger
LANGUAGE plpgsql SECURITY DEFINER SET search_path = '' AS $$
BEGIN
  INSERT INTO public.notifications (user_id, type, title, body, href, actor_id)
  SELECT e.created_by, 'rsvp', 'Ответ на событие',
         coalesce(uc.name, 'Игрок') || ': ' || NEW.answer || ' — ' || e.title,
         '#events', NEW.user_id
  FROM public.clan_events e
  LEFT JOIN public.user_cards uc ON uc.user_id = NEW.user_id
  WHERE e.id = NEW.event_id
    AND e.created_by IS DISTINCT FROM NEW.user_id
    AND (TG_OP = 'INSERT' OR NEW.answer IS DISTINCT FROM OLD.answer);
  RETURN NEW;
END $$;
DROP TRIGGER IF EXISTS trg_notify_rsvp ON public.event_rsvps;
CREATE TRIGGER trg_notify_rsvp AFTER INSERT OR UPDATE ON public.event_rsvps
  FOR EACH ROW EXECUTE FUNCTION public.notify_new_rsvp();

-- 4. Запрос верификации -> всем платформенным админам
CREATE OR REPLACE FUNCTION public.notify_verification() RETURNS trigger
LANGUAGE plpgsql SECURITY DEFINER SET search_path = '' AS $$
BEGIN
  INSERT INTO public.notifications (user_id, type, title, body, href, actor_id)
  SELECT pa.user_id, 'verification', 'Запрос верификации',
         NEW.clan_name || ' — тир ' || NEW.requested_tier,
         '#admin', NULL
  FROM public.platform_admins pa;
  RETURN NEW;
END $$;
DROP TRIGGER IF EXISTS trg_notify_verification ON public.clan_verifications;
CREATE TRIGGER trg_notify_verification AFTER INSERT ON public.clan_verifications
  FOR EACH ROW EXECUTE FUNCTION public.notify_verification();
