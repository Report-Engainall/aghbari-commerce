-- Dashboard KPIs are staff-only. Customer RLS visibility must never be enough to call a staff aggregate.
create or replace function public.get_staff_dashboard_metrics()
returns table(orders_total bigint,orders_pending bigint,orders_confirmed bigint,orders_preparing bigint,orders_ready bigint,orders_completed bigint,orders_cancelled bigint,completed_sales numeric,active_customers bigint,active_products bigint,available_stock numeric,receivables_issued numeric)
language plpgsql security invoker set search_path=public,pg_catalog as $$
declare v_company uuid:=public.current_company_id(); v_receivables numeric:=0; v_staff boolean;
begin
  if auth.uid() is null or v_company is null then raise exception using errcode='42501',message='authenticated staff context required'; end if;
  select exists(select 1 from public.company_memberships cm where cm.company_id=v_company and cm.user_id=auth.uid() and cm.is_active and cm.role in ('owner','admin','sales','warehouse')) into v_staff;
  if not v_staff then raise exception using errcode='42501',message='staff dashboard access required'; end if;
  if to_regclass('public.operational_invoices') is not null then execute 'select coalesce(sum(i.total),0) from public.operational_invoices i where i.company_id=$1 and i.status=''issued''' into v_receivables using v_company; end if;
  return query select (select count(*) from public.orders o where o.company_id=v_company),(select count(*) from public.orders o where o.company_id=v_company and o.status='pending'),(select count(*) from public.orders o where o.company_id=v_company and o.status='confirmed'),(select count(*) from public.orders o where o.company_id=v_company and o.status='preparing'),(select count(*) from public.orders o where o.company_id=v_company and o.status='ready'),(select count(*) from public.orders o where o.company_id=v_company and o.status='completed'),(select count(*) from public.orders o where o.company_id=v_company and o.status='cancelled'),coalesce((select sum(o.total) from public.orders o where o.company_id=v_company and o.status='completed'),0),(select count(*) from public.customers c where c.company_id=v_company),(select count(*) from public.products p where p.company_id=v_company and p.is_active),coalesce((select sum(ib.quantity) from public.inventory_balances ib where ib.company_id=v_company),0),v_receivables;
end; $$;
grant execute on function public.get_staff_dashboard_metrics() to authenticated;
revoke execute on function public.get_staff_dashboard_metrics() from public,anon;
