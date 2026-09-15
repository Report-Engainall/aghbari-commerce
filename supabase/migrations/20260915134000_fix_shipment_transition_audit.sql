begin;
create or replace function public.transition_shipment(p_shipment_id uuid,p_to public.shipment_status,p_driver_name text default null,p_tracking_number text default null)
returns public.shipments language plpgsql security definer set search_path=public as $$
declare v_org uuid:=public.current_organization_id(); v_role public.user_role:=public.current_role(); v_ship public.shipments%rowtype; v_from public.shipment_status; v_ok boolean:=false;
begin
 if v_org is null or v_role not in ('owner','admin','warehouse','employee') then raise exception using errcode='42501',message='shipping transition access required'; end if;
 select * into v_ship from public.shipments where id=p_shipment_id and organization_id=v_org for update;
 if not found then raise exception using errcode='P0002',message='shipment not found'; end if;
 v_from:=v_ship.status;
 if p_to=v_from then raise exception using errcode='40001',message='duplicate shipment transition'; end if;
 if (v_from,p_to) in (('pending','packed'),('packed','shipped'),('shipped','delivered')) then v_ok:=true; end if;
 if not v_ok then raise exception using errcode='22023',message='invalid shipment transition'; end if;
 update public.shipments set status=p_to,driver_name=coalesce(nullif(trim(p_driver_name),''),driver_name),tracking_number=coalesce(nullif(trim(p_tracking_number),''),tracking_number),packed_at=case when p_to='packed' then now() else packed_at end,shipped_at=case when p_to='shipped' then now() else shipped_at end,delivered_at=case when p_to='delivered' then now() else delivered_at end,updated_at=now() where id=v_ship.id returning * into v_ship;
 insert into public.shipment_events(organization_id,shipment_id,from_status,to_status,actor_id) values(v_org,v_ship.id,v_from,p_to,auth.uid());
 insert into public.audit_events(organization_id,actor_id,action,target_type,target_id,result,metadata) values(v_org,auth.uid(),'shipment.transition','shipment',v_ship.id,'success',jsonb_build_object('from',v_from,'to',p_to));
 insert into public.outbox_events(organization_id,aggregate_type,aggregate_id,event_type,payload) values(v_org,'shipment',v_ship.id,'shipment.status_changed',jsonb_build_object('shipment_id',v_ship.id,'from',v_from,'status',p_to));
 return v_ship;
end; $$;
commit;
