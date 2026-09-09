-- Runtime-discovered fix: roles are resolved from profiles scoped to the reconciliation organization.
CREATE OR REPLACE FUNCTION public.apply_inventory_reconciliation(p_reconciliation_id uuid)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path=public AS $$
DECLARE v_org uuid; v_role text; v_status text; v_warehouse uuid; v_preview jsonb; e jsonb; v_product uuid; v_old int; v_new int; v_delta int; v_count int:=0;
BEGIN
 SELECT organization_id,status,warehouse_id,preview INTO v_org,v_status,v_warehouse,v_preview FROM public.inventory_reconciliations WHERE id=p_reconciliation_id FOR UPDATE;
 IF NOT FOUND THEN RAISE EXCEPTION 'RECONCILIATION_NOT_FOUND'; END IF;
 SELECT role::text INTO v_role FROM public.profiles WHERE id=auth.uid() AND organization_id=v_org;
 IF v_role NOT IN ('owner','admin') THEN RAISE EXCEPTION 'FORBIDDEN'; END IF;
 IF v_status<>'ready' THEN RAISE EXCEPTION 'RECONCILIATION_NOT_APPROVED'; END IF;
 IF jsonb_array_length(coalesce(v_preview,'[]'::jsonb))=0 THEN RAISE EXCEPTION 'EMPTY_RECONCILIATION'; END IF;
 UPDATE public.inventory_reconciliations SET status='applied',applied_at=now() WHERE id=p_reconciliation_id AND organization_id=v_org;
 FOR e IN SELECT value FROM jsonb_array_elements(v_preview) LOOP
  v_product:=(e->>'product_id')::uuid; v_old:=(e->>'current_quantity')::int; v_new:=(e->>'target_quantity')::int; v_delta:=v_new-v_old;
  IF v_delta=0 THEN CONTINUE; END IF;
  INSERT INTO public.inventory_balances(organization_id,warehouse_id,product_id,quantity) VALUES(v_org,v_warehouse,v_product,v_new) ON CONFLICT(warehouse_id,product_id) DO UPDATE SET quantity=excluded.quantity,updated_at=now();
  INSERT INTO public.inventory_movements(organization_id,warehouse_id,product_id,delta,source_type,source_id,actor_id) VALUES(v_org,v_warehouse,v_product,v_delta,'inventory_reconciliation',p_reconciliation_id,auth.uid()); v_count:=v_count+1;
 END LOOP;
 INSERT INTO public.intelligence_evidence(organization_id,source_type,source_id,transformation,metric_key,metric_value,recommendation,decision,confidence,provenance,created_by) VALUES(v_org,'onyx_reconciliation',p_reconciliation_id,'Onyx dataset compared to live inventory; approved preview applied transactionally','inventory_reconciliation.changed_items',jsonb_build_object('count',v_count),jsonb_build_object('action','apply'),jsonb_build_object('reconciliation_id',p_reconciliation_id),1,jsonb_build_object('reconciliation_id',p_reconciliation_id),auth.uid());
 INSERT INTO public.audit_events(organization_id,actor_id,action,target_type,target_id,result,metadata) VALUES(v_org,auth.uid(),'inventory_reconciliation_applied','inventory_reconciliation',p_reconciliation_id,'success',jsonb_build_object('changed_items',v_count));
 RETURN jsonb_build_object('reconciliation_id',p_reconciliation_id,'changed_items',v_count,'status','applied');
EXCEPTION WHEN others THEN
 IF v_org IS NOT NULL THEN
  UPDATE public.inventory_reconciliations SET status='failed' WHERE id=p_reconciliation_id AND organization_id=v_org AND status='ready';
  INSERT INTO public.audit_events(organization_id,actor_id,action,target_type,target_id,result,metadata) VALUES(v_org,auth.uid(),'inventory_reconciliation_apply','inventory_reconciliation',p_reconciliation_id,'failure',jsonb_build_object('error',sqlerrm));
 END IF;
 RAISE;
END; $$;

CREATE OR REPLACE FUNCTION public.rollback_inventory_reconciliation(p_reconciliation_id uuid)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path=public AS $$
DECLARE v_org uuid; v_role text; v_status text; v_warehouse uuid; v_preview jsonb; e jsonb; v_product uuid; v_old int; v_current int; v_delta int; v_count int:=0;
BEGIN
 SELECT organization_id,status,warehouse_id,preview INTO v_org,v_status,v_warehouse,v_preview FROM public.inventory_reconciliations WHERE id=p_reconciliation_id FOR UPDATE;
 IF NOT FOUND THEN RAISE EXCEPTION 'RECONCILIATION_NOT_FOUND'; END IF;
 SELECT role::text INTO v_role FROM public.profiles WHERE id=auth.uid() AND organization_id=v_org;
 IF v_role NOT IN ('owner','admin') THEN RAISE EXCEPTION 'FORBIDDEN'; END IF;
 IF v_status<>'applied' THEN RAISE EXCEPTION 'ONLY_APPLIED_RECONCILIATIONS_CAN_ROLL_BACK'; END IF;
 FOR e IN SELECT value FROM jsonb_array_elements(v_preview) LOOP
  v_product:=(e->>'product_id')::uuid; v_old:=(e->>'current_quantity')::int;
  SELECT quantity INTO v_current FROM public.inventory_balances WHERE organization_id=v_org AND warehouse_id=v_warehouse AND product_id=v_product FOR UPDATE;
  v_delta:=v_old-coalesce(v_current,0);
  INSERT INTO public.inventory_balances(organization_id,warehouse_id,product_id,quantity) VALUES(v_org,v_warehouse,v_product,v_old) ON CONFLICT(warehouse_id,product_id) DO UPDATE SET quantity=excluded.quantity,updated_at=now();
  IF v_delta<>0 THEN INSERT INTO public.inventory_movements(organization_id,warehouse_id,product_id,delta,source_type,source_id,actor_id) VALUES(v_org,v_warehouse,v_product,v_delta,'inventory_reconciliation_rollback',p_reconciliation_id,auth.uid()); END IF;
  v_count:=v_count+1;
 END LOOP;
 UPDATE public.inventory_reconciliations SET status='rolled_back',rolled_back_at=now() WHERE id=p_reconciliation_id AND organization_id=v_org;
 INSERT INTO public.audit_events(organization_id,actor_id,action,target_type,target_id,result,metadata) VALUES(v_org,auth.uid(),'inventory_reconciliation_rolled_back','inventory_reconciliation',p_reconciliation_id,'success',jsonb_build_object('restored_items',v_count));
 RETURN jsonb_build_object('reconciliation_id',p_reconciliation_id,'restored_items',v_count,'status','rolled_back');
END; $$;
