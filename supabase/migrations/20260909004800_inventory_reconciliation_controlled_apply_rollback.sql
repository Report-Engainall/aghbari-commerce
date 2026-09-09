-- Controlled Onyx -> Live inventory reconciliation.
-- Analysis remains read/compute-only; Live mutation is permitted only through these
-- tenant-scoped, role-checked RPCs after preview and explicit approval.

CREATE OR REPLACE FUNCTION public.create_inventory_reconciliation(p_dataset_id uuid, p_warehouse_id uuid)
RETURNS uuid LANGUAGE plpgsql SECURITY DEFINER SET search_path=public AS $$
DECLARE
  v_org uuid; v_role text; v_id uuid; v_source text; v_fp text;
  v_preview jsonb:='[]'::jsonb; v_conflicts jsonb:='[]'::jsonb;
  v_total integer:=0; v_matched integer:=0; v_missing integer:=0; v_invalid integer:=0;
  r record; v_sku text; v_qty numeric; v_product uuid; v_current integer; v_entry jsonb;
BEGIN
  IF auth.uid() IS NULL THEN RAISE EXCEPTION 'AUTH_REQUIRED'; END IF;
  SELECT organization_id,role::text INTO v_org,v_role FROM public.profiles WHERE id=auth.uid();
  IF v_org IS NULL THEN RAISE EXCEPTION 'PROFILE_NOT_FOUND'; END IF;
  IF v_role NOT IN ('owner','admin','warehouse') THEN RAISE EXCEPTION 'FORBIDDEN'; END IF;
  IF NOT EXISTS (SELECT 1 FROM public.onyx_datasets WHERE id=p_dataset_id AND organization_id=v_org) THEN RAISE EXCEPTION 'DATASET_NOT_FOUND'; END IF;
  IF NOT EXISTS (SELECT 1 FROM public.warehouses WHERE id=p_warehouse_id AND organization_id=v_org AND is_active) THEN RAISE EXCEPTION 'WAREHOUSE_NOT_FOUND'; END IF;
  SELECT source_name,source_fingerprint INTO v_source,v_fp FROM public.onyx_datasets WHERE id=p_dataset_id AND organization_id=v_org;
  FOR r IN SELECT row_number,normalized_data FROM public.onyx_dataset_rows WHERE dataset_id=p_dataset_id AND organization_id=v_org ORDER BY row_number LOOP
    v_total:=v_total+1;
    v_sku:=nullif(trim(coalesce(r.normalized_data->>'item_code',r.normalized_data->>'sku',r.normalized_data->>'SKU','')),'');
    BEGIN v_qty:=coalesce(nullif(r.normalized_data->>'quantity','')::numeric,nullif(r.normalized_data->>'Quantity','')::numeric,nullif(r.normalized_data->>'available_quantity','')::numeric); EXCEPTION WHEN others THEN v_qty:=NULL; END;
    IF v_sku IS NULL OR v_qty IS NULL OR v_qty<0 OR v_qty<>trunc(v_qty) THEN
      v_invalid:=v_invalid+1; v_conflicts:=v_conflicts||jsonb_build_array(jsonb_build_object('row_number',r.row_number,'reason','invalid_identity_or_quantity','item_code',v_sku,'quantity',v_qty)); CONTINUE;
    END IF;
    SELECT p.id,coalesce(ib.quantity,0) INTO v_product,v_current FROM public.products p LEFT JOIN public.inventory_balances ib ON ib.product_id=p.id AND ib.warehouse_id=p_warehouse_id AND ib.organization_id=v_org WHERE p.organization_id=v_org AND p.sku=v_sku LIMIT 1;
    IF v_product IS NULL THEN v_missing:=v_missing+1; v_conflicts:=v_conflicts||jsonb_build_array(jsonb_build_object('row_number',r.row_number,'reason','product_not_found','item_code',v_sku,'quantity',v_qty)); CONTINUE; END IF;
    v_matched:=v_matched+1;
    v_entry:=jsonb_build_object('row_number',r.row_number,'product_id',v_product,'item_code',v_sku,'current_quantity',v_current,'target_quantity',v_qty::integer,'delta',(v_qty::integer-v_current));
    v_preview:=v_preview||jsonb_build_array(v_entry);
  END LOOP;
  INSERT INTO public.inventory_reconciliations(organization_id,dataset_id,warehouse_id,status,source_name,source_fingerprint,summary,conflicts,preview,created_by)
  VALUES(v_org,p_dataset_id,p_warehouse_id,CASE WHEN jsonb_array_length(v_conflicts)=0 THEN 'ready' ELSE 'preview' END,v_source,v_fp,jsonb_build_object('total_rows',v_total,'matched',v_matched,'missing',v_missing,'invalid',v_invalid),v_conflicts,v_preview,auth.uid()) RETURNING id INTO v_id;
  INSERT INTO public.audit_events(organization_id,actor_id,action,target_type,target_id,result,metadata) VALUES(v_org,auth.uid(),'inventory_reconciliation_preview','inventory_reconciliation',v_id,'success',jsonb_build_object('dataset_id',p_dataset_id,'warehouse_id',p_warehouse_id,'summary',jsonb_build_object('total_rows',v_total,'matched',v_matched,'missing',v_missing,'invalid',v_invalid)));
  RETURN v_id;
END; $$;

CREATE OR REPLACE FUNCTION public.approve_inventory_reconciliation(p_reconciliation_id uuid)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path=public AS $$
DECLARE v_org uuid; v_role text; v_conflicts jsonb;
BEGIN
  SELECT organization_id,role::text INTO v_org,v_role FROM public.profiles WHERE id=auth.uid();
  IF v_org IS NULL OR v_role NOT IN ('owner','admin') THEN RAISE EXCEPTION 'FORBIDDEN'; END IF;
  SELECT conflicts INTO v_conflicts FROM public.inventory_reconciliations WHERE id=p_reconciliation_id AND organization_id=v_org FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'RECONCILIATION_NOT_FOUND'; END IF;
  IF jsonb_array_length(v_conflicts)>0 THEN RAISE EXCEPTION 'CONFLICTS_MUST_BE_RESOLVED'; END IF;
  UPDATE public.inventory_reconciliations SET status='ready' WHERE id=p_reconciliation_id AND organization_id=v_org AND status='preview';
  IF NOT FOUND THEN RAISE EXCEPTION 'INVALID_RECONCILIATION_STATE'; END IF;
  INSERT INTO public.audit_events(organization_id,actor_id,action,target_type,target_id,result,metadata) VALUES(v_org,auth.uid(),'inventory_reconciliation_approved','inventory_reconciliation',p_reconciliation_id,'success','{}'::jsonb);
END; $$;

CREATE OR REPLACE FUNCTION public.apply_inventory_reconciliation(p_reconciliation_id uuid)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path=public AS $$
DECLARE v_org uuid; v_role text; v_status text; v_warehouse uuid; v_preview jsonb; e jsonb; v_product uuid; v_old int; v_new int; v_delta int; v_count int:=0;
BEGIN
  SELECT organization_id,role::text,status,warehouse_id,preview INTO v_org,v_role,v_status,v_warehouse,v_preview FROM public.inventory_reconciliations WHERE id=p_reconciliation_id FOR UPDATE;
  IF v_org IS NULL OR v_role NOT IN ('owner','admin') THEN RAISE EXCEPTION 'FORBIDDEN'; END IF;
  IF v_status<>'ready' THEN RAISE EXCEPTION 'RECONCILIATION_NOT_APPROVED'; END IF;
  IF jsonb_array_length(coalesce(v_preview,'[]'::jsonb))=0 THEN RAISE EXCEPTION 'EMPTY_RECONCILIATION'; END IF;
  UPDATE public.inventory_reconciliations SET status='applied',applied_at=now() WHERE id=p_reconciliation_id;
  FOR e IN SELECT value FROM jsonb_array_elements(v_preview) LOOP
    v_product:=(e->>'product_id')::uuid; v_old:=(e->>'current_quantity')::int; v_new:=(e->>'target_quantity')::int; v_delta:=v_new-v_old;
    IF v_delta=0 THEN CONTINUE; END IF;
    INSERT INTO public.inventory_balances(organization_id,warehouse_id,product_id,quantity) VALUES(v_org,v_warehouse,v_product,v_new) ON CONFLICT (warehouse_id,product_id) DO UPDATE SET quantity=excluded.quantity,updated_at=now();
    INSERT INTO public.inventory_movements(organization_id,warehouse_id,product_id,delta,source_type,source_id,actor_id) VALUES(v_org,v_warehouse,v_product,v_delta,'inventory_reconciliation',p_reconciliation_id,auth.uid());
    v_count:=v_count+1;
  END LOOP;
  INSERT INTO public.intelligence_evidence(organization_id,source_type,source_id,transformation,metric_key,metric_value,recommendation,decision,confidence,provenance,created_by) VALUES(v_org,'onyx_reconciliation',p_reconciliation_id,'Onyx dataset compared to live inventory; approved preview applied transactionally','inventory_reconciliation.changed_items',jsonb_build_object('count',v_count),jsonb_build_object('action','apply'),jsonb_build_object('reconciliation_id',p_reconciliation_id),1,jsonb_build_object('reconciliation_id',p_reconciliation_id),auth.uid());
  INSERT INTO public.audit_events(organization_id,actor_id,action,target_type,target_id,result,metadata) VALUES(v_org,auth.uid(),'inventory_reconciliation_applied','inventory_reconciliation',p_reconciliation_id,'success',jsonb_build_object('changed_items',v_count));
  RETURN jsonb_build_object('reconciliation_id',p_reconciliation_id,'changed_items',v_count,'status','applied');
EXCEPTION WHEN others THEN
  UPDATE public.inventory_reconciliations SET status='failed' WHERE id=p_reconciliation_id AND organization_id=v_org AND status='ready';
  INSERT INTO public.audit_events(organization_id,actor_id,action,target_type,target_id,result,metadata) VALUES(v_org,auth.uid(),'inventory_reconciliation_apply','inventory_reconciliation',p_reconciliation_id,'failure',jsonb_build_object('error',sqlerrm));
  RAISE;
END; $$;

CREATE OR REPLACE FUNCTION public.rollback_inventory_reconciliation(p_reconciliation_id uuid)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path=public AS $$
DECLARE v_org uuid; v_role text; v_status text; v_warehouse uuid; v_preview jsonb; e jsonb; v_product uuid; v_old int; v_current int; v_delta int; v_count int:=0;
BEGIN
  SELECT organization_id,role::text,status,warehouse_id,preview INTO v_org,v_role,v_status,v_warehouse,v_preview FROM public.inventory_reconciliations WHERE id=p_reconciliation_id FOR UPDATE;
  IF v_org IS NULL OR v_role NOT IN ('owner','admin') THEN RAISE EXCEPTION 'FORBIDDEN'; END IF;
  IF v_status<>'applied' THEN RAISE EXCEPTION 'ONLY_APPLIED_RECONCILIATIONS_CAN_ROLL_BACK'; END IF;
  FOR e IN SELECT value FROM jsonb_array_elements(v_preview) LOOP
    v_product:=(e->>'product_id')::uuid; v_old:=(e->>'current_quantity')::int;
    SELECT quantity INTO v_current FROM public.inventory_balances WHERE organization_id=v_org AND warehouse_id=v_warehouse AND product_id=v_product FOR UPDATE;
    v_delta:=v_old-coalesce(v_current,0);
    INSERT INTO public.inventory_balances(organization_id,warehouse_id,product_id,quantity) VALUES(v_org,v_warehouse,v_product,v_old) ON CONFLICT (warehouse_id,product_id) DO UPDATE SET quantity=excluded.quantity,updated_at=now();
    IF v_delta<>0 THEN INSERT INTO public.inventory_movements(organization_id,warehouse_id,product_id,delta,source_type,source_id,actor_id) VALUES(v_org,v_warehouse,v_product,v_delta,'inventory_reconciliation_rollback',p_reconciliation_id,auth.uid()); END IF;
    v_count:=v_count+1;
  END LOOP;
  UPDATE public.inventory_reconciliations SET status='rolled_back',rolled_back_at=now() WHERE id=p_reconciliation_id AND organization_id=v_org;
  INSERT INTO public.audit_events(organization_id,actor_id,action,target_type,target_id,result,metadata) VALUES(v_org,auth.uid(),'inventory_reconciliation_rolled_back','inventory_reconciliation',p_reconciliation_id,'success',jsonb_build_object('restored_items',v_count));
  RETURN jsonb_build_object('reconciliation_id',p_reconciliation_id,'restored_items',v_count,'status','rolled_back');
END; $$;

REVOKE ALL ON FUNCTION public.create_inventory_reconciliation(uuid,uuid) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.approve_inventory_reconciliation(uuid) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.apply_inventory_reconciliation(uuid) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.rollback_inventory_reconciliation(uuid) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.create_inventory_reconciliation(uuid,uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.approve_inventory_reconciliation(uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.apply_inventory_reconciliation(uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.rollback_inventory_reconciliation(uuid) TO authenticated;
REVOKE EXECUTE ON FUNCTION public.create_inventory_reconciliation(uuid,uuid) FROM anon;
REVOKE EXECUTE ON FUNCTION public.approve_inventory_reconciliation(uuid) FROM anon;
REVOKE EXECUTE ON FUNCTION public.apply_inventory_reconciliation(uuid) FROM anon;
REVOKE EXECUTE ON FUNCTION public.rollback_inventory_reconciliation(uuid) FROM anon;
