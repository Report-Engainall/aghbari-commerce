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
language plpgsql
security invoker
set search_path = public, pg_catalog
as $$
declare
  v_company uuid := public.current_company_id();
  v_receivables numeric := 0;
begin
  if v_company is null then
    return query select 0::bigint,0::bigint,0::bigint,0::bigint,0::bigint,0::bigint,0::bigint,0::numeric,0::bigint,0::bigint,0::numeric,0::numeric;
    return;
  end if;

  -- Finance is optional in the current schema lineage. If invoices exist, include only
  -- issued invoices so the KPI never invents a receivable from an unavailable source.
  if to_regclass('public.operational_invoices') is not null then
    execute 'select coalesce(sum(total),0) from public.operational_invoices where company_id = $1 and status = ''issued''' into v_receivables using v_company;
  end if;

  return query
  select
    (select count(*) from public.orders o where o.company_id = v_company),
    (select count(*) from public.orders o where o.company_id = v_company and o.status = 'pending'),
    (select count(*) from public.orders o where o.company_id = v_company and o.status = 'confirmed'),
    (select count(*) from public.orders o where o.company_id = v_company and o.status = 'preparing'),
    (select count(*) from public.orders o where o.company_id = v_company and o.status = 'ready'),
    (select count(*) from public.orders o where o.company_id = v_company and o.status = 'completed'),
    (select count(*) from public.orders o where o.company_id = v_company and o.status = 'cancelled'),
    coalesce((select sum(o.total) from public.orders o where o.company_id = v_company and o.status = 'completed'), 0),
    (select count(*) from public.customers c where c.company_id = v_company and c.is_active),
    (select count(*) from public.products p where p.company_id = v_company and p.is_active),
    coalesce((select sum(ib.quantity) from public.inventory_balances ib where ib.company_id = v_company), 0),
    v_receivables;
end;
$$;

grant execute on function public.get_staff_dashboard_metrics() to authenticated;
revoke execute on function public.get_staff_dashboard_metrics() from anon;

comment on function public.get_staff_dashboard_metrics() is 'Returns tenant-scoped operational KPIs from canonical orders, customers, products, inventory and optional issued invoices.';

-- Enable Postgres Changes as a refresh signal. RLS remains the authorization boundary;
-- realtime events are never treated as the source of business truth.
do $$
begin
  if not exists (select 1 from pg_publication_tables where pubname = 'supabase_realtime' and schemaname = 'public' and tablename = 'orders') then
    execute 'alter publication supabase_realtime add table public.orders';
  end if;
  if not exists (select 1 from pg_publication_tables where pubname = 'supabase_realtime' and schemaname = 'public' and tablename = 'inventory_balances') then
    execute 'alter publication supabase_realtime add table public.inventory_balances';
  end if;
  if to_regclass('public.customer_invitations') is not null and not exists (select 1 from pg_publication_tables where pubname = 'supabase_realtime' and schemaname = 'public' and tablename = 'customer_invitations') then
    execute 'alter publication supabase_realtime add table public.customer_invitations';
  end if;
exception when undefined_object then
  null;
end $$;
