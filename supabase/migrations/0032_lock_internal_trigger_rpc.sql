-- Internal trigger routine: it is invoked by PostgreSQL, not by application clients.
revoke execute on function public.notify_order_status_change() from anon, authenticated;
