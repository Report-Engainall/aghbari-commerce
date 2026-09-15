-- Forward-port of the verified transfer_inventory idempotency repair onto the current war-room lineage.
-- The RETURNS TABLE output parameter `transfer_id` must not shadow the table column
-- in the existing-idempotency lookup. All transfer lookup columns are explicitly qualified.
CREATE OR REPLACE FUNCTION public.transfer_inventory(
  p_source_warehouse_id uuid,
  p_destination_warehouse_id uuid,
  p_idempotency_key text,
  p_lines jsonb,
  p_notes text DEFAULT NULL
)
RETURNS TABLE(transfer_id uuid,transfer_status text,total_quantity bigint)
LANGUAGE plpgsql SECURITY DEFINER SET search_path=public AS $$
DECLARE
  v_org uuid:=public.current_organization_id(); v_role public.user_role:=public.current_role(); v_key text:=trim(coalesce(p_idempotency_key,'')); v_notes text:=nullif(trim(p_notes),'');
  v_transfer public.inventory_transfers%rowtype; v_existing public.inventory_transfers%rowtype; v_line jsonb; v_product uuid; v_qty integer; v_count integer; v_existing_count integer; v_source integer; v_total bigint:=0;
BEGIN
  IF v_org IS NULL OR v_role NOT IN ('owner','admin','warehouse') THEN RAISE EXCEPTION USING errcode='42501',message='inventory transfer access required'; END IF;
  IF p_source_warehouse_id=p_destination_warehouse_id THEN RAISE EXCEPTION USING errcode='22023',message='source and destination warehouses must differ'; END IF;
  IF NOT EXISTS(SELECT 1 FROM public.warehouses w WHERE w.id=p_source_warehouse_id AND w.organization_id=v_org AND w.is_active) THEN RAISE EXCEPTION USING errcode='P0002',message='source warehouse not found'; END IF;
  IF NOT EXISTS(SELECT 1 FROM public.warehouses w WHERE w.id=p_destination_warehouse_id AND w.organization_id=v_org AND w.is_active) THEN RAISE EXCEPTION USING errcode='P0002',message='destination warehouse not found'; END IF;
  IF length(v_key)<16 OR length(v_key)>128 THEN RAISE EXCEPTION USING errcode='22023',message='invalid idempotency key'; END IF;
  IF p_lines IS NULL OR jsonb_typeof(p_lines)<>'array' THEN RAISE EXCEPTION USING errcode='22023',message='transfer lines required'; END IF;
  v_count:=jsonb_array_length(p_lines); IF v_count=0 OR v_count>100 THEN RAISE EXCEPTION USING errcode='22023',message='transfer must contain between 1 and 100 lines'; END IF;
  PERFORM pg_advisory_xact_lock(hashtextextended(v_org::text||':transfer:'||v_key,0));
  SELECT * INTO v_existing FROM public.inventory_transfers t WHERE t.organization_id=v_org AND t.idempotency_key=v_key;
  IF FOUND THEN
    SELECT count(*) INTO v_existing_count FROM public.inventory_transfer_items i WHERE i.organization_id=v_org AND i.transfer_id=v_existing.id;
    IF v_existing.source_warehouse_id<>p_source_warehouse_id OR v_existing.destination_warehouse_id<>p_destination_warehouse_id OR coalesce(v_existing.notes,'')<>coalesce(v_notes,'') OR v_existing_count<>v_count THEN RAISE EXCEPTION USING errcode='40001',message='idempotency key payload conflict'; END IF;
    IF EXISTS (SELECT 1 FROM jsonb_array_elements(p_lines) x WHERE NOT EXISTS (SELECT 1 FROM public.inventory_transfer_items i WHERE i.organization_id=v_org AND i.transfer_id=v_existing.id AND i.product_id=(x->>'product_id')::uuid AND i.quantity=(x->>'quantity')::integer)) THEN RAISE EXCEPTION USING errcode='40001',message='idempotency key payload conflict'; END IF;
    SELECT coalesce(sum(i.quantity),0) INTO v_total FROM public.inventory_transfer_items i WHERE i.organization_id=v_org AND i.transfer_id=v_existing.id;
    RETURN QUERY SELECT v_existing.id,v_existing.status,v_total; RETURN;
  END IF;
  FOR v_line IN SELECT value FROM jsonb_array_elements(p_lines) ORDER BY value->>'product_id' LOOP
    BEGIN v_product:=(v_line->>'product_id')::uuid; v_qty:=(v_line->>'quantity')::integer; EXCEPTION WHEN invalid_text_representation OR numeric_value_out_of_range THEN RAISE EXCEPTION USING errcode='22023',message='invalid transfer line'; END;
    IF v_product IS NULL OR v_qty IS NULL OR v_qty<=0 OR v_qty>100000 THEN RAISE EXCEPTION USING errcode='22023',message='invalid transfer quantity'; END IF;
    IF NOT EXISTS(SELECT 1 FROM public.products p WHERE p.id=v_product AND p.organization_id=v_org AND p.status='active') THEN RAISE EXCEPTION USING errcode='P0002',message='product not found'; END IF;
    IF EXISTS(SELECT 1 FROM jsonb_array_elements(p_lines) x WHERE x->>'product_id'=v_product::text GROUP BY x->>'product_id' HAVING count(*)>1) THEN RAISE EXCEPTION USING errcode='22023',message='duplicate product line'; END IF;
    INSERT INTO public.inventory_balances(organization_id,warehouse_id,product_id,quantity) VALUES(v_org,p_source_warehouse_id,v_product,0) ON CONFLICT(warehouse_id,product_id) DO NOTHING;
    INSERT INTO public.inventory_balances(organization_id,warehouse_id,product_id,quantity) VALUES(v_org,p_destination_warehouse_id,v_product,0) ON CONFLICT(warehouse_id,product_id) DO NOTHING;
  END LOOP;
  PERFORM 1 FROM public.inventory_balances ib WHERE ib.organization_id=v_org AND ib.warehouse_id IN (p_source_warehouse_id,p_destination_warehouse_id) AND ib.product_id IN (SELECT (value->>'product_id')::uuid FROM jsonb_array_elements(p_lines) value) ORDER BY ib.warehouse_id,ib.product_id FOR UPDATE;
  FOR v_line IN SELECT value FROM jsonb_array_elements(p_lines) LOOP
    v_product:=(v_line->>'product_id')::uuid; v_qty:=(v_line->>'quantity')::integer;
    SELECT ib.quantity INTO v_source FROM public.inventory_balances ib WHERE ib.organization_id=v_org AND ib.warehouse_id=p_source_warehouse_id AND ib.product_id=v_product;
    IF coalesce(v_source,0)<v_qty THEN RAISE EXCEPTION USING errcode='22003',message='insufficient inventory for transfer'; END IF;
    v_total:=v_total+v_qty;
  END LOOP;
  INSERT INTO public.inventory_transfers(organization_id,source_warehouse_id,destination_warehouse_id,status,idempotency_key,notes,created_by) VALUES(v_org,p_source_warehouse_id,p_destination_warehouse_id,'posted',v_key,v_notes,auth.uid()) RETURNING * INTO v_transfer;
  FOR v_line IN SELECT value FROM jsonb_array_elements(p_lines) LOOP
    v_product:=(v_line->>'product_id')::uuid; v_qty:=(v_line->>'quantity')::integer;
    UPDATE public.inventory_balances ib SET quantity=ib.quantity-v_qty,updated_at=now() WHERE ib.organization_id=v_org AND ib.warehouse_id=p_source_warehouse_id AND ib.product_id=v_product;
    UPDATE public.inventory_balances ib SET quantity=ib.quantity+v_qty,updated_at=now() WHERE ib.organization_id=v_org AND ib.warehouse_id=p_destination_warehouse_id AND ib.product_id=v_product;
    INSERT INTO public.inventory_transfer_items(organization_id,transfer_id,product_id,quantity) VALUES(v_org,v_transfer.id,v_product,v_qty);
    INSERT INTO public.inventory_movements(organization_id,warehouse_id,product_id,delta,source_type,source_id,actor_id) VALUES(v_org,p_source_warehouse_id,v_product,-v_qty,'inventory_transfer',v_transfer.id,auth.uid()),(v_org,p_destination_warehouse_id,v_product,v_qty,'inventory_transfer',v_transfer.id,auth.uid());
  END LOOP;
  INSERT INTO public.audit_events(organization_id,actor_id,action,target_type,target_id,result,metadata) VALUES(v_org,auth.uid(),'inventory.transfer','inventory_transfer',v_transfer.id,'success',jsonb_build_object('source_warehouse_id',p_source_warehouse_id,'destination_warehouse_id',p_destination_warehouse_id,'total_quantity',v_total));
  INSERT INTO public.outbox_events(organization_id,aggregate_type,aggregate_id,event_type,payload) VALUES(v_org,'inventory_transfer',v_transfer.id,'inventory.transferred',jsonb_build_object('transfer_id',v_transfer.id,'source_warehouse_id',p_source_warehouse_id,'destination_warehouse_id',p_destination_warehouse_id,'total_quantity',v_total));
  RETURN QUERY SELECT v_transfer.id,v_transfer.status,v_total;
END; $$;
