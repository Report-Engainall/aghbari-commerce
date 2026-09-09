-- Security hardening: these SECURITY DEFINER routines all require an authenticated
-- identity in their function bodies and must not be callable through the anon role.
revoke execute on function public.bind_customer_device(text, text) from anon;
revoke execute on function public.mark_notification_read(uuid) from anon;
revoke execute on function public.notify_order_status_change() from anon;
revoke execute on function public.request_customer_device_change(text, text, text) from anon;
revoke execute on function public.review_device_change_request(uuid, boolean, text) from anon;
