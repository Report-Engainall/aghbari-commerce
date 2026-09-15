begin;

create type public.shipment_status as enum ('pending','packed','shipped','delivered','cancelled');
create type public.return_status as enum ('requested','under_review','approved','rejected','received','refunded','cancelled');
create type public.ledger_entry_type as enum ('debit','credit');

create table public.shipments (
  id uuid primary key default gen_random_uuid(), organization_id uuid not null references public.organizations(id) on delete restrict,
  order_id uuid not null, status public.shipment_status not null default 'pending', driver_name text, tracking_number text,
  packed_at timestamptz, shipped_at timestamptz, delivered_at timestamptz, created_by uuid references auth.users(id) on delete set null,
  created_at timestamptz not null default now(), updated_at timestamptz not null default now(),
  unique (organization_id,order_id), unique (organization_id,tracking_number),
  foreign key (order_id,organization_id) references public.orders(id,organization_id) on delete restrict
);
create table public.shipment_events (
  id uuid primary key default gen_random_uuid(), organization_id uuid not null references public.organizations(id) on delete restrict,
  shipment_id uuid not null, from_status public.shipment_status, to_status public.shipment_status not null,
  actor_id uuid references auth.users(id) on delete set null, metadata jsonb not null default '{}'::jsonb, created_at timestamptz not null default now(),
  foreign key (shipment_id,organization_id) references public.shipments(id,organization_id) on delete cascade
);
create index shipments_org_status_idx on public.shipments(organization_id,status,updated_at desc);
create index shipment_events_lookup_idx on public.shipment_events(organization_id,shipment_id,created_at desc);

create table public.returns (
  id uuid primary key default gen_random_uuid(), organization_id uuid not null references public.organizations(id) on delete restrict,
  order_id uuid not null, customer_id uuid not null, status public.return_status not null default 'requested', reason text not null,
  requested_by uuid references auth.users(id) on delete set null, reviewed_by uuid references auth.users(id) on delete set null,
  received_at timestamptz, refunded_at timestamptz, created_at timestamptz not null default now(), updated_at timestamptz not null default now(),
  unique (organization_id,id), foreign key (order_id,organization_id) references public.orders(id,organization_id) on delete restrict,
  foreign key (customer_id,organization_id) references public.customers(id,organization_id) on delete restrict
);
create table public.return_items (
  id uuid primary key default gen_random_uuid(), organization_id uuid not null references public.organizations(id) on delete restrict,
  return_id uuid not null, order_item_id uuid not null, quantity integer not null check(quantity>0), unit_amount numeric(18,2) not null check(unit_amount>=0),
  foreign key (return_id,organization_id) references public.returns(id,organization_id) on delete cascade,
  foreign key (order_item_id,organization_id) references public.order_items(id,organization_id) on delete restrict,
  unique(return_id,order_item_id)
);
create table public.return_refunds (
  id uuid primary key default gen_random_uuid(), organization_id uuid not null references public.organizations(id) on delete restrict,
  return_id uuid not null, invoice_id uuid, amount numeric(18,2) not null check(amount>0), method public.payment_method not null default 'other',
  cash_account_id uuid, actor_id uuid references auth.users(id) on delete set null, created_at timestamptz not null default now(),
  unique(organization_id,return_id),
  foreign key(return_id,organization_id) references public.returns(id,organization_id) on delete restrict,
  foreign key(invoice_id,organization_id) references public.operational_invoices(id,organization_id) on delete restrict,
  foreign key(cash_account_id,organization_id) references public.cash_accounts(id,organization_id) on delete restrict
);
create table public.operational_ledger_entries (
  id uuid primary key default gen_random_uuid(), organization_id uuid not null references public.organizations(id) on delete restrict,
  customer_id uuid, source_type text not null, source_id uuid not null, entry_type public.ledger_entry_type not null,
  amount numeric(18,2) not null check(amount>0), currency text not null default 'YER', description text, actor_id uuid references auth.users(id) on delete set null,
  created_at timestamptz not null default now(),
  foreign key(customer_id,organization_id) references public.customers(id,organization_id) on delete restrict
);
create index return_org_status_idx on public.returns(organization_id,status,created_at desc);
create index return_items_lookup_idx on public.return_items(organization_id,return_id);
create index ledger_customer_time_idx on public.operational_ledger_entries(organization_id,customer_id,created_at desc);

alter table public.shipments enable row level security;
alter table public.shipment_events enable row level security;
alter table public.returns enable row level security;
alter table public.return_items enable row level security;
alter table public.return_refunds enable row level security;
alter table public.operational_ledger_entries enable row level security;
create policy shipments_read on public.shipments for select to authenticated using(organization_id=public.current_organization_id() and (public.is_staff() or exists(select 1 from public.orders o where o.id=shipments.order_id and o.organization_id=shipments.organization_id and o.customer_id=public.current_customer_id())));
create policy shipment_events_read on public.shipment_events for select to authenticated using(organization_id=public.current_organization_id() and public.is_staff());
create policy returns_read on public.returns for select to authenticated using(organization_id=public.current_organization_id() and (public.is_staff() or customer_id=public.current_customer_id()));
create policy return_items_read on public.return_items for select to authenticated using(organization_id=public.current_organization_id() and exists(select 1 from public.returns r where r.id=return_items.return_id and r.organization_id=return_items.organization_id and (r.customer_id=public.current_customer_id() or public.is_staff())));
create policy return_refunds_read on public.return_refunds for select to authenticated using(organization_id=public.current_organization_id() and public.is_staff());
create policy ledger_read on public.operational_ledger_entries for select to authenticated using(organization_id=public.current_organization_id() and (public.is_staff() or customer_id=public.current_customer_id()));

create or replace function public.create_shipment(p_order_id uuid,p_driver_name text default null,p_tracking_number text default null)
returns public.shipments language plpgsql security definer set search_path=public as $$
declare v_org uuid:=public.current_organization_id(); v_role public.user_role:=public.current_role(); v_order public.orders%rowtype; v_ship public.shipments%rowtype;
begin
 if v_org is null or v_role not in ('owner','admin','warehouse','employee') then raise exception using errcode='42501',message='shipping access required'; end if;
 select * into v_order from public.orders where id=p_order_id and organization_id=v_org for update;
 if not found then raise exception using errcode='P0002',message='order not found'; end if;
 if v_order.status not in ('ready','completed') then raise exception using errcode='22023',message='order not ready for shipment'; end if;
 select * into v_ship from public.shipments where organization_id=v_org and order_id=p_order_id;
 if found then return v_ship; end if;
 insert into public.shipments(organization_id,order_id,driver_name,tracking_number,created_by) values(v_org,p_order_id,nullif(trim(p_driver_name),''),nullif(trim(p_tracking_number),''),auth.uid()) returning * into v_ship;
 insert into public.shipment_events(organization_id,shipment_id,from_status,to_status,actor_id) values(v_org,v_ship.id,null,'pending',auth.uid());
 insert into public.audit_events(organization_id,actor_id,action,target_type,target_id,result,metadata) values(v_org,auth.uid(),'shipment.create','shipment',v_ship.id,'success',jsonb_build_object('order_id',p_order_id));
 insert into public.outbox_events(organization_id,aggregate_type,aggregate_id,event_type,payload) values(v_org,'shipment',v_ship.id,'shipment.created',jsonb_build_object('shipment_id',v_ship.id,'order_id',p_order_id));
 return v_ship;
end; $$;

create or replace function public.transition_shipment(p_shipment_id uuid,p_to public.shipment_status,p_driver_name text default null,p_tracking_number text default null)
returns public.shipments language plpgsql security definer set search_path=public as $$
declare v_org uuid:=public.current_organization_id(); v_role public.user_role:=public.current_role(); v_ship public.shipments%rowtype; v_ok boolean:=false;
begin
 if v_org is null or v_role not in ('owner','admin','warehouse','employee') then raise exception using errcode='42501',message='shipping transition access required'; end if;
 select * into v_ship from public.shipments where id=p_shipment_id and organization_id=v_org for update;
 if not found then raise exception using errcode='P0002',message='shipment not found'; end if;
 if p_to=v_ship.status then raise exception using errcode='40001',message='duplicate shipment transition'; end if;
 if (v_ship.status,p_to) in (('pending','packed'),('packed','shipped'),('shipped','delivered')) then v_ok:=true; end if;
 if not v_ok then raise exception using errcode='22023',message='invalid shipment transition'; end if;
 update public.shipments set status=p_to,driver_name=coalesce(nullif(trim(p_driver_name),''),driver_name),tracking_number=coalesce(nullif(trim(p_tracking_number),''),tracking_number),packed_at=case when p_to='packed' then now() else packed_at end,shipped_at=case when p_to='shipped' then now() else shipped_at end,delivered_at=case when p_to='delivered' then now() else delivered_at end,updated_at=now() where id=v_ship.id returning * into v_ship;
 insert into public.shipment_events(organization_id,shipment_id,from_status,to_status,actor_id) values(v_org,v_ship.id,(select status from public.shipments where id=v_ship.id),p_to,auth.uid());
 insert into public.audit_events(organization_id,actor_id,action,target_type,target_id,result,metadata) values(v_org,auth.uid(),'shipment.transition','shipment',v_ship.id,'success',jsonb_build_object('to',p_to));
 insert into public.outbox_events(organization_id,aggregate_type,aggregate_id,event_type,payload) values(v_org,'shipment',v_ship.id,'shipment.status_changed',jsonb_build_object('shipment_id',v_ship.id,'status',p_to));
 return v_ship;
end; $$;

create or replace function public.create_return(p_order_id uuid,p_reason text,p_items jsonb)
returns public.returns language plpgsql security definer set search_path=public as $$
declare v_org uuid:=public.current_organization_id(); v_customer uuid:=public.current_customer_id(); v_role public.user_role:=public.current_role(); v_order public.orders%rowtype; v_return public.returns%rowtype; x jsonb; v_item public.order_items%rowtype; v_qty int; v_unit numeric;
begin
 if v_org is null or (v_customer is null and v_role not in ('owner','admin','sales','employee')) then raise exception using errcode='42501',message='return customer context required'; end if;
 select * into v_order from public.orders where id=p_order_id and organization_id=v_org for update;
 if not found then raise exception using errcode='P0002',message='order not found'; end if;
 if v_customer is not null and v_order.customer_id<>v_customer then raise exception using errcode='42501',message='return order ownership denied'; end if;
 if v_order.status not in ('completed','cancelled') then raise exception using errcode='22023',message='order not returnable'; end if;
 if p_reason is null or trim(p_reason)='' or jsonb_typeof(p_items)<>'array' or jsonb_array_length(p_items)=0 then raise exception using errcode='22023',message='return reason and items required'; end if;
 if exists(select 1 from public.returns where organization_id=v_org and order_id=p_order_id and status not in ('rejected','cancelled')) then raise exception using errcode='40001',message='active return already exists'; end if;
 insert into public.returns(organization_id,order_id,customer_id,reason,requested_by) values(v_org,p_order_id,v_order.customer_id,trim(p_reason),auth.uid()) returning * into v_return;
 for x in select * from jsonb_array_elements(p_items) loop
  select * into v_item from public.order_items where id=(x->>'order_item_id')::uuid and organization_id=v_org and order_id=p_order_id;
  if not found then raise exception using errcode='42501',message='return item does not belong to order'; end if;
  v_qty:=(x->>'quantity')::int; if v_qty is null or v_qty<=0 or v_qty>v_item.quantity then raise exception using errcode='22023',message='invalid return quantity'; end if;
  insert into public.return_items(organization_id,return_id,order_item_id,quantity,unit_amount) values(v_org,v_return.id,v_item.id,v_qty,v_item.unit_price);
 end loop;
 insert into public.audit_events(organization_id,actor_id,action,target_type,target_id,result,metadata) values(v_org,auth.uid(),'return.request','return',v_return.id,'success',jsonb_build_object('order_id',p_order_id));
 insert into public.outbox_events(organization_id,aggregate_type,aggregate_id,event_type,payload) values(v_org,'return',v_return.id,'return.requested',jsonb_build_object('return_id',v_return.id,'order_id',p_order_id));
 return v_return;
end; $$;

create or replace function public.review_return(p_return_id uuid,p_approve boolean)
returns public.returns language plpgsql security definer set search_path=public as $$
declare v_org uuid:=public.current_organization_id(); v_role public.user_role:=public.current_role(); v_return public.returns%rowtype;
begin
 if v_org is null or v_role not in ('owner','admin','sales','employee') then raise exception using errcode='42501',message='return review access required'; end if;
 select * into v_return from public.returns where id=p_return_id and organization_id=v_org for update;
 if not found then raise exception using errcode='P0002',message='return not found'; end if;
 if v_return.status<>'requested' then raise exception using errcode='22023',message='return is not awaiting review'; end if;
 update public.returns set status=case when p_approve then 'approved' else 'rejected' end,reviewed_by=auth.uid(),updated_at=now() where id=v_return.id returning * into v_return;
 insert into public.audit_events(organization_id,actor_id,action,target_type,target_id,result,metadata) values(v_org,auth.uid(),'return.review','return',v_return.id,'success',jsonb_build_object('approved',p_approve));
 return v_return;
end; $$;

create or replace function public.receive_return(p_return_id uuid,p_warehouse_id uuid)
returns public.returns language plpgsql security definer set search_path=public as $$
declare v_org uuid:=public.current_organization_id(); v_role public.user_role:=public.current_role(); v_return public.returns%rowtype; x record;
begin
 if v_org is null or v_role not in ('owner','admin','warehouse','employee') then raise exception using errcode='42501',message='return receiving access required'; end if;
 select * into v_return from public.returns where id=p_return_id and organization_id=v_org for update;
 if not found then raise exception using errcode='P0002',message='return not found'; end if;
 if v_return.status<>'approved' then raise exception using errcode='22023',message='return must be approved'; end if;
 if not exists(select 1 from public.warehouses where id=p_warehouse_id and organization_id=v_org and is_active) then raise exception using errcode='42501',message='warehouse not available'; end if;
 for x in select ri.quantity,oi.product_id from public.return_items ri join public.order_items oi on oi.id=ri.order_item_id and oi.organization_id=ri.organization_id where ri.return_id=v_return.id and ri.organization_id=v_org loop
  insert into public.inventory_balances(organization_id,warehouse_id,product_id,quantity) values(v_org,p_warehouse_id,x.product_id,x.quantity) on conflict(warehouse_id,product_id) do update set quantity=public.inventory_balances.quantity+excluded.quantity,updated_at=now();
  insert into public.inventory_movements(organization_id,warehouse_id,product_id,delta,source_type,source_id,actor_id) values(v_org,p_warehouse_id,x.product_id,x.quantity,'return',v_return.id,auth.uid());
 end loop;
 update public.returns set status='received',received_at=now(),updated_at=now() where id=v_return.id returning * into v_return;
 insert into public.audit_events(organization_id,actor_id,action,target_type,target_id,result,metadata) values(v_org,auth.uid(),'return.receive','return',v_return.id,'success',jsonb_build_object('warehouse_id',p_warehouse_id));
 insert into public.outbox_events(organization_id,aggregate_type,aggregate_id,event_type,payload) values(v_org,'return',v_return.id,'return.received',jsonb_build_object('return_id',v_return.id));
 return v_return;
end; $$;

create or replace function public.post_return_refund(p_return_id uuid,p_method public.payment_method default 'other',p_cash_account_id uuid default null)
returns public.return_refunds language plpgsql security definer set search_path=public as $$
declare v_org uuid:=public.current_organization_id(); v_role public.user_role:=public.current_role(); v_return public.returns%rowtype; v_ref public.return_refunds%rowtype; v_total numeric(18,2); v_invoice uuid; v_currency text; v_account public.cash_accounts%rowtype;
begin
 if v_org is null or v_role not in ('owner','admin','finance') then raise exception using errcode='42501',message='refund access required'; end if;
 select * into v_return from public.returns where id=p_return_id and organization_id=v_org for update;
 if not found then raise exception using errcode='P0002',message='return not found'; end if;
 if v_return.status<>'received' then raise exception using errcode='22023',message='return must be received before refund'; end if;
 select rr.* into v_ref from public.return_refunds rr where rr.return_id=v_return.id and rr.organization_id=v_org;
 if found then return v_ref; end if;
 select coalesce(sum(ri.quantity*ri.unit_amount),0) into v_total from public.return_items ri where ri.return_id=v_return.id and ri.organization_id=v_org;
 select oi.id into v_invoice from public.operational_invoices oi where oi.order_id=v_return.order_id and oi.organization_id=v_org limit 1;
 if v_invoice is not null then select currency into v_currency from public.operational_invoices where id=v_invoice and organization_id=v_org; else v_currency:='YER'; end if;
 if p_method='cash' then
  if p_cash_account_id is null then raise exception using errcode='22023',message='cash account required'; end if;
  select * into v_account from public.cash_accounts where id=p_cash_account_id and organization_id=v_org and is_active for update;
  if not found or v_account.currency<>v_currency then raise exception using errcode='22023',message='cash account mismatch'; end if;
 end if;
 insert into public.return_refunds(organization_id,return_id,invoice_id,amount,method,cash_account_id,actor_id) values(v_org,v_return.id,v_invoice,v_total,p_method,p_cash_account_id,auth.uid()) returning * into v_ref;
 if p_cash_account_id is not null then insert into public.cash_transactions(organization_id,cash_account_id,direction,amount,source_type,source_id,note,actor_id) values(v_org,p_cash_account_id,'out',v_total,'return_refund',v_ref.id,'Return refund',auth.uid()); end if;
 insert into public.operational_ledger_entries(organization_id,customer_id,source_type,source_id,entry_type,amount,currency,description,actor_id) values(v_org,v_return.customer_id,'return_refund',v_ref.id,'credit',v_total,v_currency,'Customer return credit',auth.uid());
 update public.returns set status='refunded',refunded_at=now(),updated_at=now() where id=v_return.id;
 insert into public.audit_events(organization_id,actor_id,action,target_type,target_id,result,metadata) values(v_org,auth.uid(),'return.refund','return',v_return.id,'success',jsonb_build_object('refund_id',v_ref.id,'amount',v_total));
 insert into public.outbox_events(organization_id,aggregate_type,aggregate_id,event_type,payload) values(v_org,'return',v_return.id,'return.refunded',jsonb_build_object('return_id',v_return.id,'refund_id',v_ref.id,'amount',v_total));
 return v_ref;
end; $$;

commit;
