-- Customer portal payment history: safe read-only projection through a tenant/customer-scoped RPC.
-- The underlying payments table remains staff-only.
create or replace function public.get_customer_payments()
returns table(
  id uuid,
  invoice_id uuid,
  amount numeric,
  method text,
  reference text,
  paid_at timestamptz,
  created_at timestamptz
)
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_org uuid := public.current_organization_id();
  v_customer uuid := public.current_customer_id();
begin
  if auth.uid() is null or v_org is null or v_customer is null then
    raise exception 'authenticated customer context required' using errcode='42501';
  end if;
  return query
    select p.id,p.invoice_id,p.amount,p.method::text,p.reference,p.paid_at,p.created_at
    from public.payments p
    join public.operational_invoices i on i.id=p.invoice_id
      and i.organization_id=p.organization_id
      and i.customer_id=v_customer
    where p.organization_id=v_org
    order by p.paid_at desc nulls last,p.created_at desc;
end;
$$;
revoke all on function public.get_customer_payments() from public,anon;
grant execute on function public.get_customer_payments() to authenticated;
