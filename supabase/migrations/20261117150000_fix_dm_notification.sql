-- ============================================================
-- Фикс: уведомление о ЛС создаётся ровно один раз
-- ============================================================
CREATE OR REPLACE FUNCTION public.notify_new_dm() RETURNS trigger
LANGUAGE plpgsql SECURITY DEFINER SET search_path = '' AS $$
BEGIN
  INSERT INTO public.notifications (user_id, type, title, body, href, actor_id)
  SELECT NEW.recipient_id, 'dm', 'Личное сообщение',
         coalesce((SELECT uc.name FROM public.user_cards uc WHERE uc.user_id = NEW.sender_id), 'Кто-то')
           || ': ' || left(NEW.body, 120),
         '#dm', NEW.sender_id;
  RETURN NEW;
END $$;
