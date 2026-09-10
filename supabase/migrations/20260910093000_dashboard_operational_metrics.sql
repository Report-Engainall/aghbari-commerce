-- Server-backed operational KPIs for the staff command center.
-- Values are computed from tenant-scoped source tables; the UI must not derive business truth
-- from a truncated recent-orders list.

create or replace function public.get_staff_dashboard_metrics()
returns table(
  orders_total bigint,
  orders_pending bigint,
  orders_confirmed bigint,
  orders_preparing bigint,
  orders_ready bigint,
  orders_completed bigint,
  orders_cancelled bigint,
  completed_sales numeric,
  active_customers bigint,
  active_products bigint,
  available_stock numeric,
  receivables_issued numeric
)
language sql
security invoker
set search_path = public, pg_catalog
as $$
  with org as (select public.current_organization_id() as organization_id)
  select
    (select count(*) from public.orders o, org where o.organization_id = org.organization_id),
    (select count(*) from public.orders o, org where o.organization_id = org.organization_id and o.status = 'pending'),
    (select count(*) from public.orders o, org where o.organization_id = org.organization_id and o.status = 'confirmed'),
    (select count(*) from public.orders o, org where o.organization_id = org.organization_id and o.status = 'preparing'),
    (select count(*) from public.orders o, org where o.organization_id = org.organization_id and o.status = 'ready'),
    (select count(*) from public.orders o, org where o.organization_id = org.organization_id and o.status = 'completed'),
    (select count(*) from public.orders o, org where o.organization_id = org.organization_id and o.status = 'cancelled'),
    coalesce((select sum(o.total) from public.orders o, org where o.organization_id = org.organization_id and o.status = 'completed'), 0),
    (select count(*) from public.customers c, org where c.organization_id = org.organization_id and c.is_active),
    (select count(*) from public.products p, org where p.organization_id = org.organization_id and p.status = 'active'),
    coalesce((select sum(ib.quantity) from public.inventory_balances ib, org where ib.organization_id = org.organization_id), 0),
    coalesce((select sum(i.total) from public.operational_invoices i, org where i.organization_id = org.organization_id and i.status = 'issued'), 0);
$$;

grant execute on function public.get_staff_dashboard_metrics() to authenticated;
revoke execute on function public.get_staff_dashboard_metrics() from anon;

comment on function public.get_staff_dashboard_metrics() is 'Returns tenant-scoped operational KPIs from canonical orders, customers, products, inventory and issued invoices.';

-- Enable the simple Postgres Changes signal for the operational surfaces.
-- RLS remains the authorization boundary; events are used as a refresh signal, not as source of truth.
do $$
begin
  if not exists (select 1 from pg_publication_tables where pubname = 'supabase_realtime' and schemaname = 'public' and tablename = 'orders') then
    execute 'alter publication supabase_realtime add table public.orders';
  end if;
  if not exists (select 1 from pg_publication_tables where pubname = 'supabase_realtime' and schemaname = 'public' and tablename = 'inventory_balances') then
    execute 'alter publication supabase_realtime add table public.inventory_balances';
  end if;
  if not exists (select 1 from pg_publication_tables where pubname = 'supabase_realtime' and schemaname = 'public' and tablename = 'customer_invitations') then
    execute 'alter publication supabase_realtime add table public.customer_invitations';
  end if;
exception when undefined_object then
  -- A local/non-Realtime database may not have the publication yet.
  null;
end $$;
