-- Remove the stale customer is_active predicate from the live order command.
create or replace function public.create_order(p_idempotency_key text,p_warehouse_id uuid,p_lines jsonb)
returns table(id uuid,order_number bigint)
language plpgsql security definer set search_path=public,pg_catalog as $$
declare v_company uuid:=public.current_customer_company_id(); v_customer uuid:=public.current_customer_id(); v_order_id uuid; v_order_number bigint; v_existing public.orders%rowtype; v_line jsonb; v_product uuid; v_qty integer; v_available numeric; v_price numeric(18,2); v_currency text; v_order_currency text; v_tier text; v_subtotal numeric(18,2):=0; v_requested_key text:=trim(coalesce(p_idempotency_key,'')); v_line_count integer; v_existing_count integer;
begin
  if auth.uid() is null or v_company is null or v_customer is null then raise exception using errcode='42501',message='authenticated customer context required'; end if;
  if length(v_requested_key)<16 or length(v_requested_key)>128 then raise exception using errcode='22023',message='invalid idempotency key'; end if;
  if p_warehouse_id is null or not exists(select 1 from public.warehouses w where w.id=p_warehouse_id and w.company_id=v_company and w.is_active) then raise exception using errcode='42501',message='warehouse not available'; end if;
  if p_lines is null or jsonb_typeof(p_lines)<>'array' then raise exception using errcode='22023',message='order lines required'; end if;
  v_line_count:=jsonb_array_length(p_lines); if v_line_count<1 or v_line_count>100 then raise exception using errcode='22023',message='order must contain between 1 and 100 lines'; end if;
  if not exists(select 1 from public.customers c where c.id=v_customer and c.company_id=v_company) then raise exception using errcode='42501',message='customer required'; end if;
  select c.tier::text into v_tier from public.customers c where c.id=v_customer and c.company_id=v_company;
  perform pg_advisory_xact_lock(hashtextextended(v_company::text||':'||v_requested_key,0));
  select o.* into v_existing from public.orders o where o.company_id=v_company and o.idempotency_key=v_requested_key for update;
  if found then
    if v_existing.customer_id<>v_customer or v_existing.warehouse_id<>p_warehouse_id then raise exception using errcode='40001',message='idempotency key payload conflict'; end if;
    select count(*) into v_existing_count from public.order_items oi where oi.company_id=v_company and oi.order_id=v_existing.id;
    if v_existing_count<>v_line_count or exists(select 1 from jsonb_array_elements(p_lines) l where not exists(select 1 from public.order_items oi where oi.company_id=v_company and oi.order_id=v_existing.id and oi.product_id=(l->>'productId')::uuid and oi.quantity=(l->>'quantity')::numeric)) then raise exception using errcode='40001',message='idempotency key payload conflict'; end if;
    return query select v_existing.id,v_existing.order_number; return;
  end if;
  for v_line in select value from jsonb_array_elements(p_lines) loop
    begin v_product:=(v_line->>'productId')::uuid; exception when invalid_text_representation then raise exception using errcode='22023',message='invalid product id'; end;
    if v_product is null or v_line->>'quantity' is null or v_line->>'quantity' !~ '^[0-9]+$' then raise exception using errcode='22023',message='invalid order line'; end if;
    v_qty:=(v_line->>'quantity')::integer; if v_qty<1 or v_qty>10000 then raise exception using errcode='22023',message='invalid quantity'; end if;
  end loop;
  if exists(select 1 from(select value->>'productId' product_id from jsonb_array_elements(p_lines)) x group by product_id having count(*)>1) then raise exception using errcode='22023',message='duplicate product line'; end if;
  for v_line in select value from jsonb_array_elements(p_lines) order by value->>'productId' loop
    v_product:=(v_line->>'productId')::uuid; v_qty:=(v_line->>'quantity')::integer;
    if not exists(select 1 from public.products p where p.id=v_product and p.company_id=v_company and p.is_active) then raise exception using errcode='P0001',message='product unavailable'; end if;
    select cpt.unit_price,cpt.currency into v_price,v_currency from public.customer_price_tiers cpt where cpt.company_id=v_company and cpt.customer_id=v_customer and cpt.product_id=v_product and cpt.min_quantity<=v_qty order by cpt.min_quantity desc,cpt.created_at desc limit 1;
    if v_price is null then select p.selling_price into v_price from public.products p where p.id=v_product and p.company_id=v_company and p.is_active; v_currency:='YER'; end if;
    if v_price is null or v_price<0 then raise exception using errcode='P0001',message='authorized price unavailable'; end if;
    v_currency:=coalesce(nullif(trim(v_currency),''),'YER'); if v_order_currency is null then v_order_currency:=v_currency; elsif v_order_currency<>v_currency then raise exception using errcode='22023',message='mixed order currencies are not allowed'; end if;
    select ib.quantity into v_available from public.inventory_balances ib where ib.company_id=v_company and ib.warehouse_id=p_warehouse_id and ib.product_id=v_product for update;
    if not found or v_available<v_qty then raise exception using errcode='P0001',message='insufficient stock'; end if;
    v_subtotal:=v_subtotal+round(v_price*v_qty,2);
  end loop;
  insert into public.orders(company_id,customer_id,warehouse_id,status,total,currency,idempotency_key,quantity_confirmed_at,created_by) values(v_company,v_customer,p_warehouse_id,'pending',v_subtotal,coalesce(v_order_currency,'YER'),v_requested_key,now(),auth.uid()) returning orders.id,orders.order_number into v_order_id,v_order_number;
  for v_line in select value from jsonb_array_elements(p_lines) order by value->>'productId' loop
    v_product:=(v_line->>'productId')::uuid; v_qty:=(v_line->>'quantity')::integer;
    select cpt.unit_price into v_price from public.customer_price_tiers cpt where cpt.company_id=v_company and cpt.customer_id=v_customer and cpt.product_id=v_product and cpt.min_quantity<=v_qty order by cpt.min_quantity desc,cpt.created_at desc limit 1;
    if v_price is null then select p.selling_price into v_price from public.products p where p.id=v_product and p.company_id=v_company and p.is_active; end if;
    update public.inventory_balances ib set quantity=ib.quantity-v_qty,updated_at=now() where ib.company_id=v_company and ib.warehouse_id=p_warehouse_id and ib.product_id=v_product and ib.quantity>=v_qty;
    if not found then raise exception using errcode='P0001',message='inventory changed; retry order'; end if;
    insert into public.inventory_movements(company_id,warehouse_id,product_id,movement_type,quantity,reference_type,reference_id,movement_date,notes) values(v_company,p_warehouse_id,v_product,'sale',v_qty,'order',v_order_id,current_date,'B2B order checkout');
    insert into public.order_items(order_id,company_id,product_id,quantity,unit,unit_price,line_total) select v_order_id,v_company,v_product,v_qty,p.unit,v_price,round(v_price*v_qty,2) from public.products p where p.id=v_product and p.company_id=v_company;
  end loop;
  insert into public.order_status_history(company_id,order_id,from_status,to_status,actor_id) values(v_company,v_order_id,null,'pending',auth.uid());
  insert into public.order_outbox_events(company_id,order_id,event_type,payload) values(v_company,v_order_id,'order.created',jsonb_build_object('order_id',v_order_id,'order_number',v_order_number));
  insert into public.audit_logs(company_id,action,entity_type,entity_id,new_value,source) values(v_company,'order_created','order',v_order_id,jsonb_build_object('order_number',v_order_number,'customer_id',v_customer,'warehouse_id',p_warehouse_id,'total',v_subtotal),'b2b_checkout');
  return query select v_order_id,v_order_number;
end; $$;
grant execute on function public.create_order(text,uuid,jsonb) to authenticated;
revoke execute on function public.create_order(text,uuid,jsonb) from public,anon;
