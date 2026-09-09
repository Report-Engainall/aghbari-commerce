-- Scale hardening for notification reads/updates and device security lookups.
drop policy if exists notifications_read on public.notifications;
drop policy if exists notifications_update_self on public.notifications;
create policy notifications_read on public.notifications
  for select to authenticated
  using ((organization_id = (select public.current_organization_id()) and ((customer_id = (select public.current_customer_id())) or (recipient_user_id = (select auth.uid())) or (select public.is_staff()))));
create policy notifications_update_self on public.notifications
  for update to authenticated
  using ((organization_id = (select public.current_organization_id()) and ((customer_id = (select public.current_customer_id())) or (recipient_user_id = (select auth.uid())))))
  with check ((organization_id = (select public.current_organization_id()) and ((customer_id = (select public.current_customer_id())) or (recipient_user_id = (select auth.uid())))));

create index if not exists customer_devices_customer_idx on public.customer_devices (customer_id);
create index if not exists device_change_requests_current_device_idx on public.device_change_requests (current_device_id);
create index if not exists device_change_requests_customer_idx on public.device_change_requests (customer_id);
create index if not exists device_change_requests_reviewed_by_idx on public.device_change_requests (reviewed_by);
create index if not exists notifications_customer_fk_idx on public.notifications (customer_id);
create index if not exists notifications_recipient_user_fk_idx on public.notifications (recipient_user_id);
