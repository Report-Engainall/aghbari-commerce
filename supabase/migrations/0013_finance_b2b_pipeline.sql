-- B2B finance pipeline: order -> invoice -> payments -> receivables.
-- Idempotent where practical so this migration can reconcile environments safely.

alter table public.sales_invoices add column if not exists order_id uuid;

do $$ begin
  if not exists (select 1 from pg_constraint where conrelid='public.sales_invoices'::regclass and conname='sales_invoices_order_id_fkey') then
    alter table public.sales_invoices add constraint sales_invoices_order_id_fkey foreign key (order_id) references public.orders(id) on delete set null;
  end if;
end $$;

create unique index if not exists uq_sales_invoices_order_id on public.sales_invoices(order_id) where order_id is not null;

create table if not exists public.cash_accounts (
  id uuid primary key default gen_random_uuid(),
  company_id uuid not null references public.companies(id) on delete cascade,
  branch_id uuid not null,
  name text not null,
  currency text not null,
  opening_balance numeric not null default 0,
  received numeric not null default 0,
  spent numeric not null default 0,
  current_balance numeric generated always as (opening_balance + received - spent) stored,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint cash_accounts_branch_company_fkey foreign key (company_id,branch_id) references public.branches(company_id,id),
  constraint cash_accounts_currency_format check (currency=upper(btrim(currency)) and length(btrim(currency))=3),
  constraint cash_accounts_nonnegative check (opening_balance>=0 and received>=0 and spent>=0)
);
create index if not exists idx_cash_accounts_company_branch on public.cash_accounts(company_id,branch_id);
alter table public.cash_accounts enable row level security;
drop policy if exists cash_accounts_tenant_select on public.cash_accounts;
create policy cash_accounts_tenant_select on public.cash_accounts for select to authenticated using (company_id=public.current_company_id());
revoke all on public.cash_accounts from anon;
revoke insert,update,delete on public.cash_accounts from authenticated;
grant select on public.cash_accounts to authenticated;

create or replace function public.create_cash_account(p_branch_id uuid,p_name text,p_currency text,p_opening_balance numeric default 0)
returns public.cash_accounts language plpgsql security definer set search_path='' as $$
declare v_company uuid:=public.current_company_id(); v_role text; v_row public.cash_accounts;
begin
  if auth.uid() is null or v_company is null then raise exception using errcode='42501',message='authenticated company context required'; end if;
  select cm.role into v_role from public.company_memberships cm where cm.company_id=v_company and cm.user_id=auth.uid() and cm.is_active limit 1;
  if v_role not in ('owner','admin') then raise exception using errcode='42501',message='admin finance role required'; end if;
  if p_name is null or btrim(p_name)='' or length(btrim(p_name))>200 then raise exception 'invalid_cash_account_name'; end if;
  if p_currency is null or upper(btrim(p_currency)) !~ '^[A-Z]{3}$' then raise exception 'invalid_currency'; end if;
  if coalesce(p_opening_balance,0)<0 then raise exception 'invalid_opening_balance'; end if;
  insert into public.cash_accounts(company_id,branch_id,name,currency,opening_balance) values(v_company,p_branch_id,btrim(p_name),upper(btrim(p_currency)),coalesce(p_opening_balance,0)) returning * into v_row;
  return v_row;
end $$;
revoke all on function public.create_cash_account(uuid,text,text,numeric) from public;
grant execute on function public.create_cash_account(uuid,text,text,numeric) to authenticated;

create or replace function public.create_invoice_from_order(p_order_id uuid)
returns public.sales_invoices language plpgsql security definer set search_path='' as $$
declare v_company uuid:=public.current_company_id(); v_role text; v_order public.orders%rowtype; v_invoice public.sales_invoices%rowtype; v_number text;
begin
  if auth.uid() is null or v_company is null then raise exception using errcode='42501',message='authenticated staff context required'; end if;
  select cm.role into v_role from public.company_memberships cm where cm.company_id=v_company and cm.user_id=auth.uid() and cm.is_active limit 1;
  if v_role not in ('owner','admin','sales') then raise exception using errcode='42501',message='staff finance role required'; end if;
  select * into v_order from public.orders o where o.id=p_order_id and o.company_id=v_company for update;
  if not found then raise exception 'order_not_found'; end if;
  if v_order.status <> 'completed' then raise exception 'order_must_be_completed'; end if;
  select * into v_invoice from public.sales_invoices si where si.order_id=v_order.id and si.company_id=v_company limit 1;
  if found then return v_invoice; end if;
  v_number:='INV-'||v_order.order_number::text;
  insert into public.sales_invoices(company_id,branch_id,customer_id,invoice_number,invoice_date,due_date,status,subtotal,discount_amount,tax_amount,total,paid_amount,currency,order_id,created_at)
  values(v_company,null,v_order.customer_id,v_number,current_date,null,'confirmed',v_order.total,0,0,v_order.total,0,v_order.currency,v_order.id,now()) returning * into v_invoice;
  insert into public.audit_logs(company_id,action,entity_type,entity_id,new_value,source)
  values(v_company,'invoice_created','sales_invoice',v_invoice.id,jsonb_build_object('order_id',v_order.id,'invoice_number',v_number,'total',v_order.total,'currency',v_order.currency),'order_completion');
  return v_invoice;
end $$;
revoke all on function public.create_invoice_from_order(uuid) from public;
grant execute on function public.create_invoice_from_order(uuid) to authenticated;

create or replace function public.record_payment(p_invoice_id uuid,p_amount numeric,p_method text default 'cash',p_cash_account_id uuid default null,p_reference text default null)
returns jsonb language plpgsql security definer set search_path='' as $$
declare v_company uuid:=public.current_company_id(); v_role text; v_invoice public.sales_invoices%rowtype; v_account public.cash_accounts%rowtype; v_paid numeric; v_remaining numeric; v_new_paid numeric; v_status text; v_payment_id uuid;
begin
  if auth.uid() is null or v_company is null then raise exception using errcode='42501',message='authenticated company context required'; end if;
  select cm.role into v_role from public.company_memberships cm where cm.company_id=v_company and cm.user_id=auth.uid() and cm.is_active limit 1;
  if v_role not in ('owner','admin','sales') then raise exception using errcode='42501',message='staff finance role required'; end if;
  if p_amount is null or p_amount<=0 then raise exception 'invalid_payment_amount'; end if;
  select * into v_invoice from public.sales_invoices where id=p_invoice_id and company_id=v_company for update;
  if not found then raise exception 'invoice_not_found'; end if;
  if v_invoice.status in ('void','cancelled','draft') then raise exception 'invoice_not_payable'; end if;
  v_paid:=coalesce(v_invoice.paid_amount,0); v_remaining:=greatest(coalesce(v_invoice.total,0)-v_paid,0);
  if p_amount>v_remaining then raise exception 'payment_exceeds_balance'; end if;
  if upper(coalesce(p_method,'CASH'))='CASH' then
    if p_cash_account_id is null then raise exception 'cash_account_required'; end if;
    select * into v_account from public.cash_accounts where id=p_cash_account_id and company_id=v_company for update;
    if not found then raise exception 'cash_account_not_found'; end if;
    if v_account.currency<>v_invoice.currency then raise exception 'payment_currency_mismatch'; end if;
    update public.cash_accounts set received=received+p_amount,updated_at=now() where id=v_account.id;
  end if;
  insert into public.payments(company_id,direction,customer_id,invoice_id,amount,payment_date,method,reference,currency)
  values(v_company,'in',v_invoice.customer_id,v_invoice.id,p_amount,current_date,lower(coalesce(p_method,'cash')),nullif(btrim(p_reference),''),v_invoice.currency) returning id into v_payment_id;
  v_new_paid:=v_paid+p_amount; v_status:=case when v_new_paid>=coalesce(v_invoice.total,0) then 'paid' else 'partially_paid' end;
  update public.sales_invoices set paid_amount=v_new_paid,status=v_status where id=v_invoice.id;
  insert into public.audit_logs(company_id,action,entity_type,entity_id,new_value,source)
  values(v_company,'payment_recorded','payment',v_payment_id,jsonb_build_object('invoice_id',v_invoice.id,'amount',p_amount,'new_paid_amount',v_new_paid,'status',v_status),'finance');
  return jsonb_build_object('payment_id',v_payment_id,'invoice_id',v_invoice.id,'paid_amount',v_new_paid,'remaining_balance',greatest(v_invoice.total-v_new_paid,0),'status',v_status);
end $$;
revoke all on function public.record_payment(uuid,numeric,text,uuid,text) from public;
grant execute on function public.record_payment(uuid,numeric,text,uuid,text) to authenticated;

create or replace function public.get_cash_account_balances()
returns setof public.cash_accounts language sql security definer set search_path='' as $$
  select ca.* from public.cash_accounts ca where ca.company_id=public.current_company_id() order by ca.name
$$;
revoke all on function public.get_cash_account_balances() from public;
grant execute on function public.get_cash_account_balances() to authenticated;

revoke insert,update,delete on public.sales_invoices from authenticated;
revoke insert,update,delete on public.payments from authenticated;
grant select on public.sales_invoices,public.payments to authenticated;

create or replace function public.get_staff_receivables()
returns numeric language sql security definer set search_path='' as $$
  select coalesce(sum(greatest(coalesce(si.total,0)-coalesce(si.paid_amount,0),0)),0)::numeric
  from public.sales_invoices si
  where si.company_id=public.current_company_id()
    and si.status not in ('cancelled','void','draft')
    and coalesce(si.total,0)>coalesce(si.paid_amount,0)
$$;
revoke all on function public.get_staff_receivables() from public;
grant execute on function public.get_staff_receivables() to authenticated;

create or replace function public.get_staff_dashboard_metrics()
returns table(orders_total bigint,orders_pending bigint,orders_confirmed bigint,orders_preparing bigint,orders_ready bigint,orders_completed bigint,orders_cancelled bigint,completed_sales numeric,active_customers bigint,active_products bigint,available_stock numeric,receivables_issued numeric)
language plpgsql set search_path='public','pg_catalog' as $$
declare v_company uuid:=public.current_company_id(); v_receivables numeric:=0; v_staff boolean;
begin
  if auth.uid() is null or v_company is null then raise exception using errcode='42501',message='authenticated staff context required'; end if;
  select exists(select 1 from public.company_memberships cm where cm.company_id=v_company and cm.user_id=auth.uid() and cm.is_active and cm.role in ('owner','admin','sales','warehouse')) into v_staff;
  if not v_staff then raise exception using errcode='42501',message='staff dashboard access required'; end if;
  select coalesce(sum(greatest(coalesce(i.total,0)-coalesce(i.paid_amount,0),0)),0) into v_receivables
  from public.sales_invoices i where i.company_id=v_company and i.status not in ('cancelled','void','draft') and coalesce(i.total,0)>coalesce(i.paid_amount,0);
  return query select
    (select count(*) from public.orders o where o.company_id=v_company),
    (select count(*) from public.orders o where o.company_id=v_company and o.status='pending'),
    (select count(*) from public.orders o where o.company_id=v_company and o.status='confirmed'),
    (select count(*) from public.orders o where o.company_id=v_company and o.status='preparing'),
    (select count(*) from public.orders o where o.company_id=v_company and o.status='ready'),
    (select count(*) from public.orders o where o.company_id=v_company and o.status='completed'),
    (select count(*) from public.orders o where o.company_id=v_company and o.status='cancelled'),
    coalesce((select sum(o.total) from public.orders o where o.company_id=v_company and o.status='completed'),0),
    (select count(*) from public.customers c where c.company_id=v_company),
    (select count(*) from public.products p where p.company_id=v_company and p.is_active),
    coalesce((select sum(ib.quantity) from public.inventory_balances ib where ib.company_id=v_company),0),
    v_receivables;
end $$;

-- Completing an order is the single authoritative invoice trigger.
create or replace function public.transition_order(p_order_id uuid,p_to_status text)
returns public.orders language plpgsql security definer set search_path='' as $$
declare v_company uuid:=public.current_company_id(); v_role text; v_order public.orders%rowtype; v_previous_status text; v_item record; v_allowed boolean:=false; v_invoice public.sales_invoices%rowtype;
begin
  if auth.uid() is null or v_company is null then raise exception using errcode='42501',message='authenticated staff context required'; end if;
  select cm.role into v_role from public.company_memberships cm where cm.company_id=v_company and cm.user_id=auth.uid() and cm.is_active limit 1;
  if v_role is null or v_role not in ('owner','admin','sales','warehouse') then raise exception using errcode='42501',message='staff membership required'; end if;
  select o.* into v_order from public.orders o where o.id=p_order_id and o.company_id=v_company for update;
  if not found then raise exception using errcode='P0002',message='order not found'; end if;
  if p_to_status not in ('pending','confirmed','preparing','ready','completed','cancelled') then raise exception using errcode='22023',message='invalid order status'; end if;
  v_previous_status:=v_order.status;
  v_allowed:=(v_previous_status='pending' and p_to_status in ('confirmed','cancelled') and v_role in ('owner','admin','sales')) or (v_previous_status='confirmed' and p_to_status in ('preparing','cancelled') and v_role in ('owner','admin','warehouse')) or (v_previous_status='preparing' and p_to_status in ('ready','cancelled') and v_role in ('owner','admin','warehouse')) or (v_previous_status='ready' and p_to_status='completed' and v_role in ('owner','admin','warehouse','sales'));
  if not v_allowed then raise exception using errcode='42501',message='order transition not allowed'; end if;
  if p_to_status='cancelled' and v_previous_status<>'cancelled' then
    for v_item in select oi.product_id,oi.quantity from public.order_items oi where oi.company_id=v_company and oi.order_id=v_order.id order by oi.product_id loop
      update public.inventory_balances ib set quantity=ib.quantity+v_item.quantity,updated_at=now() where ib.company_id=v_company and ib.warehouse_id=v_order.warehouse_id and ib.product_id=v_item.product_id;
      if not found then raise exception using errcode='P0001',message='inventory balance missing while cancelling order'; end if;
      insert into public.inventory_movements(company_id,warehouse_id,product_id,movement_type,quantity,reference_type,reference_id,movement_date,notes) values(v_company,v_order.warehouse_id,v_item.product_id,'return',v_item.quantity,'order',v_order.id,current_date,'Order cancellation stock restoration');
    end loop;
  end if;
  update public.orders set status=p_to_status,updated_at=now() where id=v_order.id returning * into v_order;
  insert into public.order_status_history(company_id,order_id,from_status,to_status,actor_id) values(v_company,v_order.id,v_previous_status,p_to_status,auth.uid());
  insert into public.order_outbox_events(company_id,order_id,event_type,payload) values(v_company,v_order.id,'order.status_changed',jsonb_build_object('order_id',v_order.id,'order_number',v_order.order_number,'from_status',v_previous_status,'to_status',p_to_status));
  insert into public.audit_logs(company_id,action,entity_type,entity_id,old_value,new_value,source) values(v_company,'order_status_changed','order',v_order.id,jsonb_build_object('status',v_previous_status),jsonb_build_object('status',p_to_status),'order_workflow');
  if p_to_status='completed' then
    select * into v_invoice from public.sales_invoices where company_id=v_company and order_id=v_order.id limit 1;
    if not found then
      insert into public.sales_invoices(company_id,branch_id,customer_id,invoice_number,invoice_date,due_date,status,subtotal,discount_amount,tax_amount,total,paid_amount,currency,order_id,created_at)
      values(v_company,null,v_order.customer_id,'INV-'||v_order.order_number::text,current_date,null,'confirmed',v_order.total,0,0,v_order.total,0,v_order.currency,v_order.id,now()) returning * into v_invoice;
      insert into public.audit_logs(company_id,action,entity_type,entity_id,new_value,source) values(v_company,'invoice_created','sales_invoice',v_invoice.id,jsonb_build_object('order_id',v_order.id,'invoice_number',v_invoice.invoice_number,'total',v_order.total,'currency',v_order.currency),'order_completion');
    end if;
  end if;
  return v_order;
end $$;
revoke all on function public.transition_order(uuid,text) from public;
grant execute on function public.transition_order(uuid,text) to authenticated;
