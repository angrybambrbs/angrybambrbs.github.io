-- Отзываем EXECUTE у PUBLIC (дефолт Postgres) на мутационные RPC
-- и выдаём явно только тем ролям, кто реально их вызывает.
-- Helper-функции (can_edit_clan, is_clan_member, ...) не трогаем:
-- они нужны anon/authenticated для вычисления политик RLS.

REVOKE EXECUTE ON FUNCTION public.add_owner_member() FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.add_owner_member() TO authenticated, service_role;

REVOKE EXECUTE ON FUNCTION public.handle_new_user_card() FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.handle_new_user_card() TO service_role;

REVOKE EXECUTE ON FUNCTION public.touch_card() FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.touch_card() TO authenticated, service_role;

REVOKE EXECUTE ON FUNCTION public.touch_member(uuid) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.touch_member(uuid) TO authenticated, service_role;

REVOKE EXECUTE ON FUNCTION public.apply_to_clan(uuid, text) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.apply_to_clan(uuid, text) TO authenticated, service_role;

REVOKE EXECUTE ON FUNCTION public.create_invite(uuid, text) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.create_invite(uuid, text) TO authenticated, service_role;

REVOKE EXECUTE ON FUNCTION public.decide_application(uuid, boolean) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.decide_application(uuid, boolean) TO authenticated, service_role;

REVOKE EXECUTE ON FUNCTION public.join_clan(text) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.join_clan(text) TO authenticated, service_role;

REVOKE EXECUTE ON FUNCTION public.request_verification(uuid, text, text, text, text) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.request_verification(uuid, text, text, text, text) TO authenticated, service_role;

REVOKE EXECUTE ON FUNCTION public.review_verification(uuid, boolean, text, text) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.review_verification(uuid, boolean, text, text) TO authenticated, service_role;
