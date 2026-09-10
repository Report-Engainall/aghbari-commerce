-- A customer membership is still a membership; the workflow must explicitly require a staff role.
create or replace function public.transition_order(p_order_id uuid,p_to_status text)
returns public.orders
language plpgsql security definer set search_path=public,pg_catalog as $$
declare v_company uuid:=public.current_company_id(); v_role text; v_order public.orders%rowtype; v_previous_status text; v_item record; v_allowed boolean:=false;
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
  if p_to_status='cancelled' then
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
  return v_order;
end; $$;
grant execute on function public.transition_order(uuid,text) to authenticated;
revoke execute on function public.transition_order(uuid,text) from public,anon;
