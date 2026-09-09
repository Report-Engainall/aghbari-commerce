-- Safety invariant: preview creation never grants mutation authority.
CREATE OR REPLACE FUNCTION public.create_inventory_reconciliation(p_dataset_id uuid, p_warehouse_id uuid)
RETURNS uuid LANGUAGE plpgsql SECURITY DEFINER SET search_path=public AS $$
DECLARE v_org uuid; v_role text; v_id uuid; v_source text; v_fp text; v_preview jsonb:='[]'::jsonb; v_conflicts jsonb:='[]'::jsonb; v_total int:=0; v_matched int:=0; v_missing int:=0; v_invalid int:=0; r record; v_sku text; v_qty numeric; v_product uuid; v_current int; v_entry jsonb;
BEGIN
 SELECT organization_id,role::text INTO v_org,v_role FROM public.profiles WHERE id=auth.uid();
 IF v_org IS NULL OR v_role NOT IN ('owner','admin','warehouse') THEN RAISE EXCEPTION 'FORBIDDEN'; END IF;
 IF NOT EXISTS(select 1 from public.onyx_datasets where id=p_dataset_id and organization_id=v_org) THEN RAISE EXCEPTION 'DATASET_NOT_FOUND'; END IF;
 IF NOT EXISTS(select 1 from public.warehouses where id=p_warehouse_id and organization_id=v_org and is_active) THEN RAISE EXCEPTION 'WAREHOUSE_NOT_FOUND'; END IF;
 SELECT source_name,source_fingerprint INTO v_source,v_fp FROM public.onyx_datasets WHERE id=p_dataset_id AND organization_id=v_org;
 FOR r IN SELECT row_number,normalized_data FROM public.onyx_dataset_rows WHERE dataset_id=p_dataset_id AND organization_id=v_org ORDER BY row_number LOOP
  v_total:=v_total+1; v_sku:=nullif(trim(coalesce(r.normalized_data->>'item_code',r.normalized_data->>'sku',r.normalized_data->>'SKU','')),'');
  BEGIN v_qty:=coalesce(nullif(r.normalized_data->>'quantity','')::numeric,nullif(r.normalized_data->>'Quantity','')::numeric,nullif(r.normalized_data->>'available_quantity','')::numeric); EXCEPTION WHEN others THEN v_qty:=NULL; END;
  IF v_sku IS NULL OR v_qty IS NULL OR v_qty<0 OR v_qty<>trunc(v_qty) THEN v_invalid:=v_invalid+1; v_conflicts:=v_conflicts||jsonb_build_array(jsonb_build_object('row_number',r.row_number,'reason','invalid_identity_or_quantity','item_code',v_sku,'quantity',v_qty)); CONTINUE; END IF;
  IF EXISTS(select 1 from public.onyx_dataset_rows prior where prior.dataset_id=p_dataset_id and prior.organization_id=v_org and prior.row_number<r.row_number and nullif(trim(coalesce(prior.normalized_data->>'item_code',prior.normalized_data->>'sku',prior.normalized_data->>'SKU','')),'')=v_sku) THEN v_invalid:=v_invalid+1; v_conflicts:=v_conflicts||jsonb_build_array(jsonb_build_object('row_number',r.row_number,'reason','duplicate_identity','item_code',v_sku)); CONTINUE; END IF;
  SELECT p.id,coalesce(ib.quantity,0) INTO v_product,v_current FROM public.products p LEFT JOIN public.inventory_balances ib ON ib.product_id=p.id AND ib.warehouse_id=p_warehouse_id AND ib.organization_id=v_org WHERE p.organization_id=v_org AND p.sku=v_sku LIMIT 1;
  IF v_product IS NULL THEN v_missing:=v_missing+1; v_conflicts:=v_conflicts||jsonb_build_array(jsonb_build_object('row_number',r.row_number,'reason','product_not_found','item_code',v_sku,'quantity',v_qty)); CONTINUE; END IF;
  v_matched:=v_matched+1; v_entry:=jsonb_build_object('row_number',r.row_number,'product_id',v_product,'item_code',v_sku,'current_quantity',v_current,'target_quantity',v_qty::int,'delta',(v_qty::int-v_current)); v_preview:=v_preview||jsonb_build_array(v_entry);
 END LOOP;
 INSERT INTO public.inventory_reconciliations(organization_id,dataset_id,warehouse_id,status,source_name,source_fingerprint,summary,conflicts,preview,created_by) VALUES(v_org,p_dataset_id,p_warehouse_id,'preview',v_source,v_fp,jsonb_build_object('total_rows',v_total,'matched',v_matched,'missing',v_missing,'invalid',v_invalid),v_conflicts,v_preview,auth.uid()) RETURNING id INTO v_id;
 INSERT INTO public.audit_events(organization_id,actor_id,action,target_type,target_id,result,metadata) VALUES(v_org,auth.uid(),'inventory_reconciliation_preview','inventory_reconciliation',v_id,'success',jsonb_build_object('dataset_id',p_dataset_id,'warehouse_id',p_warehouse_id));
 RETURN v_id;
END; $$;
