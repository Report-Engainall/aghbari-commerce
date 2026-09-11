-- Move customer payment history authorization to the base-table RLS boundary.
alter table public.payments enable row level security;
drop policy if exists payments_customer_read on public.payments;
create policy payments_customer_read on public.payments
for select to authenticated
using (
  organization_id = public.current_organization_id()
  and exists (
    select 1 from public.operational_invoices i
    where i.id = payments.invoice_id
      and i.organization_id = payments.organization_id
      and i.customer_id = public.current_customer_id()
  )
);

create or replace function public.get_customer_payments()
returns table(id uuid, invoice_id uuid, amount numeric, method text, reference text, paid_at timestamptz, created_at timestamptz)
language sql
security invoker
set search_path = ''
as $$
  select p.id,p.invoice_id,p.amount,p.method::text,p.reference,p.paid_at,p.created_at
  from public.payments p
  order by p.paid_at desc nulls last,p.created_at desc;
$$;
revoke all on function public.get_customer_payments() from public,anon;
grant execute on function public.get_customer_payments() to authenticated;
