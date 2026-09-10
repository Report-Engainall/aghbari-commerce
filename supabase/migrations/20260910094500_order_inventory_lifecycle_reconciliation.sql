-- Reconcile the live company-based schema with the B2B order contract.
-- The command is atomic: idempotency + price lock + deterministic inventory locks + deduction
-- happen in one transaction. Cancellation restores the exact quantities once.

create table if not exists public.order_status_history (
  id uuid primary key default gen_random_uuid(),
  company_id uuid not null references public.companies(id) on delete restrict,
  order_id uuid not null references public.orders(id) on delete cascade,
  from_status text,
  to_status text not null,
  actor_id uuid references auth.users(id) on delete set null,
  created_at timestamptz not null default now()
);
create index if not exists order_status_history_order_idx on public.order_status_history(company_id, order_id, created_at desc);

create table if not exists public.order_outbox_events (
  id uuid primary key default gen_random_uuid(),
  company_id uuid not null references public.companies(id) on delete restrict,
  order_id uuid not null references public.orders(id) on delete cascade,
  event_type text not null,
  payload jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now(),
  delivered_at timestamptz
);
create index if not exists order_outbox_pending_idx on public.order_outbox_events(company_id, delivered_at, created_at);

alter table public.order_status_history enable row level security;
alter table public.order_outbox_events enable row level security;
drop policy if exists order_status_history_staff_read on public.order_status_history;
create policy order_status_history_staff_read on public.order_status_history for select to authenticated using (
  company_id = public.current_company_id()
  and exists (select 1 from public.company_memberships cm where cm.company_id = order_status_history.company_id and cm.user_id = auth.uid() and cm.is_active and cm.role in ('owner','admin','sales','warehouse'))
);
drop policy if exists order_outbox_staff_read on public.order_outbox_events;
create policy order_outbox_staff_read on public.order_outbox_events for select to authenticated using (
  company_id = public.current_company_id()
  and exists (select 1 from public.company_memberships cm where cm.company_id = order_outbox_events.company_id and cm.user_id = auth.uid() and cm.is_active and cm.role in ('owner','admin','sales','warehouse'))
);

create or replace function public.create_order(
  p_idempotency_key text,
  p_warehouse_id uuid,
  p_lines jsonb
)
returns table(id uuid, order_number bigint)
language plpgsql
security definer
set search_path = public, pg_catalog
as $$
declare
  v_company uuid := public.current_customer_company_id();
  v_customer uuid := public.current_customer_id();
  v_order_id uuid;
  v_order_number bigint;
  v_existing public.orders%rowtype;
  v_line jsonb;
  v_product uuid;
  v_qty integer;
  v_available numeric;
  v_price numeric(18,2);
  v_currency text;
  v_tier text;
  v_subtotal numeric(18,2) := 0;
  v_requested_key text := trim(coalesce(p_idempotency_key, ''));
  v_line_count integer;
  v_existing_count integer;
begin
  if auth.uid() is null or v_company is null or v_customer is null then
    raise exception using errcode='42501', message='authenticated customer context required';
  end if;
  if length(v_requested_key) < 16 or length(v_requested_key) > 128 then
    raise exception using errcode='22023', message='invalid idempotency key';
  end if;
  if p_warehouse_id is null or not exists (select 1 from public.warehouses where id=p_warehouse_id and company_id=v_company and is_active) then
    raise exception using errcode='42501', message='warehouse not available';
  end if;
  if p_lines is null or jsonb_typeof(p_lines) <> 'array' then
    raise exception using errcode='22023', message='order lines required';
  end if;
  v_line_count := jsonb_array_length(p_lines);
  if v_line_count < 1 or v_line_count > 100 then
    raise exception using errcode='22023', message='order must contain between 1 and 100 lines';
  end if;

  if not exists (select 1 from public.customers where id=v_customer and company_id=v_company and is_active) then
    raise exception using errcode='42501', message='active customer required';
  end if;
  select c.tier::text into v_tier from public.customers c where c.id=v_customer and c.company_id=v_company;

  perform pg_advisory_xact_lock(hashtextextended(v_company::text || ':' || v_requested_key, 0));
  select * into v_existing from public.orders where company_id=v_company and idempotency_key=v_requested_key for update;
  if found then
    if v_existing.customer_id <> v_customer or v_existing.warehouse_id <> p_warehouse_id then
      raise exception using errcode='40001', message='idempotency key payload conflict';
    end if;
    select count(*) into v_existing_count from public.order_items where company_id=v_company and order_id=v_existing.id;
    if v_existing_count <> v_line_count or exists (
      select 1 from jsonb_array_elements(p_lines) l
      where not exists (
        select 1 from public.order_items oi
        where oi.company_id=v_company and oi.order_id=v_existing.id
          and oi.product_id=(l->>'productId')::uuid and oi.quantity=(l->>'quantity')::numeric
      )
    ) then
      raise exception using errcode='40001', message='idempotency key payload conflict';
    end if;
    return query select v_existing.id, v_existing.order_number;
    return;
  end if;

  -- Validate shape before mutating anything.
  for v_line in select value from jsonb_array_elements(p_lines) loop
    begin
      v_product := (v_line->>'productId')::uuid;
    exception when invalid_text_representation then
      raise exception using errcode='22023', message='invalid product id';
    end;
    if v_product is null or v_line->>'quantity' is null or v_line->>'quantity' !~ '^[0-9]+$' then
      raise exception using errcode='22023', message='invalid order line';
    end if;
    v_qty := (v_line->>'quantity')::integer;
    if v_qty < 1 or v_qty > 10000 then raise exception using errcode='22023', message='invalid quantity'; end if;
  end loop;
  if exists (select 1 from (select value->>'productId' product_id from jsonb_array_elements(p_lines)) x group by product_id having count(*) > 1) then
    raise exception using errcode='22023', message='duplicate product line';
  end if;

  -- Deterministic product order makes concurrent multi-line orders acquire locks consistently.
  for v_line in select value from jsonb_array_elements(p_lines) order by value->>'productId' loop
    v_product := (v_line->>'productId')::uuid;
    v_qty := (v_line->>'quantity')::integer;
    if not exists (select 1 from public.products p where p.id=v_product and p.company_id=v_company and p.is_active) then
      raise exception using errcode='P0001', message='product unavailable';
    end if;

    select cpt.unit_price, cpt.currency into v_price, v_currency
    from public.customer_price_tiers cpt
    where cpt.company_id=v_company and cpt.customer_id=v_customer and cpt.product_id=v_product and cpt.min_quantity <= v_qty
    order by cpt.min_quantity desc, cpt.created_at desc limit 1;
    if v_price is null then
      select p.selling_price into v_price from public.products p where p.id=v_product and p.company_id=v_company and p.is_active;
      v_currency := 'YER';
    end if;
    if v_price is null or v_price < 0 then raise exception using errcode='P0001', message='authorized price unavailable'; end if;
    if v_currency is null then v_currency := 'YER'; end if;
    if exists (select 1 where v_subtotal > 0 and v_currency <> (select currency from public.orders where id=v_order_id)) then null; end if;

    select quantity into v_available
    from public.inventory_balances
    where id is not null and company_id=v_company and warehouse_id=p_warehouse_id and product_id=v_product
    for update;
    if not found or v_available < v_qty then
      raise exception using errcode='P0001', message='insufficient stock';
    end if;
    v_subtotal := v_subtotal + round(v_price * v_qty, 2);
  end loop;

  insert into public.orders(company_id,customer_id,warehouse_id,status,total,currency,idempotency_key,quantity_confirmed_at,created_by)
  values(v_company,v_customer,p_warehouse_id,'pending',v_subtotal,coalesce(v_currency,'YER'),v_requested_key,now(),auth.uid())
  returning id,order_number into v_order_id,v_order_number;

  for v_line in select value from jsonb_array_elements(p_lines) order by value->>'productId' loop
    v_product := (v_line->>'productId')::uuid;
    v_qty := (v_line->>'quantity')::integer;
    select cpt.unit_price into v_price from public.customer_price_tiers cpt where cpt.company_id=v_company and cpt.customer_id=v_customer and cpt.product_id=v_product and cpt.min_quantity <= v_qty order by cpt.min_quantity desc,cpt.created_at desc limit 1;
    if v_price is null then select p.selling_price into v_price from public.products p where p.id=v_product and p.company_id=v_company and p.is_active; end if;
    update public.inventory_balances set quantity=quantity-v_qty,updated_at=now() where id is not null and company_id=v_company and warehouse_id=p_warehouse_id and product_id=v_product and quantity>=v_qty;
    if not found then raise exception using errcode='P0001',message='inventory changed; retry order'; end if;
    insert into public.inventory_movements(company_id,warehouse_id,product_id,movement_type,quantity,reference_type,reference_id,movement_date,notes)
    values(v_company,p_warehouse_id,v_product,'sale',v_qty,'order',v_order_id,current_date,'B2B order checkout');
    insert into public.order_items(order_id,company_id,product_id,quantity,unit,unit_price,line_total)
    select v_order_id,v_company,v_product,v_qty,p.unit,v_price,round(v_price*v_qty,2) from public.products p where p.id=v_product and p.company_id=v_company;
  end loop;

  insert into public.order_status_history(company_id,order_id,from_status,to_status,actor_id) values(v_company,v_order_id,null,'pending',auth.uid());
  insert into public.order_outbox_events(company_id,order_id,event_type,payload) values(v_company,v_order_id,'order.created',jsonb_build_object('order_id',v_order_id,'order_number',v_order_number));
  insert into public.audit_logs(company_id,action,entity_type,entity_id,new_value,source) values(v_company,'order_created','order',v_order_id,jsonb_build_object('order_number',v_order_number,'customer_id',v_customer,'warehouse_id',p_warehouse_id,'total',v_subtotal),'b2b_checkout');

  return query select v_order_id,v_order_number;
end;
$$;

grant execute on function public.create_order(text,uuid,jsonb) to authenticated;
revoke execute on function public.create_order(text,uuid,jsonb) from public,anon;

create or replace function public.transition_order(p_order_id uuid,p_to_status text)
returns public.orders
language plpgsql
security definer
set search_path = public, pg_catalog
as $$
declare
  v_company uuid := public.current_company_id();
  v_role text;
  v_order public.orders%rowtype;
  v_item record;
  v_allowed boolean := false;
begin
  if auth.uid() is null or v_company is null then raise exception using errcode='42501',message='authenticated staff context required'; end if;
  select cm.role into v_role from public.company_memberships cm where cm.company_id=v_company and cm.user_id=auth.uid() and cm.is_active limit 1;
  if v_role is null then raise exception using errcode='42501',message='staff membership required'; end if;
  select * into v_order from public.orders where id=p_order_id and company_id=v_company for update;
  if not found then raise exception using errcode='P0002',message='order not found'; end if;
  if p_to_status not in ('pending','confirmed','preparing','ready','completed','cancelled') then raise exception using errcode='22023',message='invalid order status'; end if;
  v_allowed := (v_order.status='pending' and p_to_status in ('confirmed','cancelled') and v_role in ('owner','admin','sales'))
    or (v_order.status='confirmed' and p_to_status in ('preparing','cancelled') and v_role in ('owner','admin','warehouse'))
    or (v_order.status='preparing' and p_to_status in ('ready','cancelled') and v_role in ('owner','admin','warehouse'))
    or (v_order.status='ready' and p_to_status='completed' and v_role in ('owner','admin','warehouse','sales'));
  if not v_allowed then raise exception using errcode='42501',message='order transition not allowed'; end if;

  if p_to_status='cancelled' then
    for v_item in select product_id,quantity from public.order_items where company_id=v_company and order_id=v_order.id order by product_id loop
      update public.inventory_balances set quantity=quantity+v_item.quantity,updated_at=now() where id is not null and company_id=v_company and warehouse_id=v_order.warehouse_id and product_id=v_item.product_id;
      if not found then raise exception using errcode='P0001',message='inventory balance missing while cancelling order'; end if;
      insert into public.inventory_movements(company_id,warehouse_id,product_id,movement_type,quantity,reference_type,reference_id,movement_date,notes)
      values(v_company,v_order.warehouse_id,v_item.product_id,'return',v_item.quantity,'order',v_order.id,current_date,'Order cancellation stock restoration');
    end loop;
  end if;

  update public.orders set status=p_to_status,updated_at=now() where id=v_order.id returning * into v_order;
  insert into public.order_status_history(company_id,order_id,from_status,to_status,actor_id) values(v_company,v_order.id,v_order.status,p_to_status,auth.uid());
  insert into public.order_outbox_events(company_id,order_id,event_type,payload) values(v_company,v_order.id,'order.status_changed',jsonb_build_object('order_id',v_order.id,'order_number',v_order.order_number,'from_status',v_order.status,'to_status',p_to_status));
  insert into public.audit_logs(company_id,action,entity_type,entity_id,old_value,new_value,source) values(v_company,'order_status_changed','order',v_order.id,jsonb_build_object('status',v_order.status),jsonb_build_object('status',p_to_status),'order_workflow');
  return v_order;
end;
$$;

grant execute on function public.transition_order(uuid,text) to authenticated;
revoke execute on function public.transition_order(uuid,text) from public,anon;
comment on function public.create_order(text,uuid,jsonb) is 'Atomic B2B checkout with idempotency, server-authoritative price snapshot, deterministic row locks, warehouse-specific stock deduction and audit/outbox evidence.';
comment on function public.transition_order(uuid,text) is 'Role-controlled order workflow with one-time cancellation stock restoration and audit/outbox evidence.';
