-- Reconstructed from the deployed Supabase migration 20260909004115.
-- Purpose: keep repository migration history aligned with the already-applied
-- resumable product-import pipeline. Existing import_jobs/import_rows tables
-- and supporting constraints/indexes are created by earlier migrations.

CREATE OR REPLACE FUNCTION public.begin_product_import(p_source_name text, p_source_fingerprint text, p_total_rows integer)
RETURNS uuid LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public' AS $function$
DECLARE
  v_org uuid := public.current_organization_id();
  v_role public.user_role := public.current_role();
  v_job uuid;
BEGIN
  IF v_org IS NULL OR v_role NOT IN ('owner','admin','sales') THEN RAISE EXCEPTION USING errcode='42501',message='staff import access required'; END IF;
  IF nullif(trim(p_source_name),'') IS NULL OR length(trim(p_source_name))>180 THEN RAISE EXCEPTION USING errcode='22023',message='invalid source name'; END IF;
  IF nullif(trim(p_source_fingerprint),'') IS NULL OR length(trim(p_source_fingerprint))<>64 OR trim(p_source_fingerprint) !~ '^[0-9a-fA-F]{64}$' THEN RAISE EXCEPTION USING errcode='22023',message='invalid source fingerprint'; END IF;
  IF p_total_rows IS NULL OR p_total_rows<1 OR p_total_rows>100000 THEN RAISE EXCEPTION USING errcode='22023',message='import row count must be between 1 and 100000'; END IF;
  INSERT INTO public.import_jobs(organization_id,source_name,source_fingerprint,status,total_rows,created_by)
  VALUES(v_org,trim(p_source_name),lower(trim(p_source_fingerprint)),'validating',p_total_rows,auth.uid())
  ON CONFLICT(organization_id,source_fingerprint) DO NOTHING RETURNING id INTO v_job;
  IF v_job IS NULL THEN RAISE EXCEPTION USING errcode='23505',message='duplicate or active import fingerprint'; END IF;
  RETURN v_job;
END; $function$;

CREATE OR REPLACE FUNCTION public.stage_product_import_chunk(p_import_job_id uuid, p_start_row integer, p_rows jsonb)
RETURNS integer LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public' AS $function$
DECLARE
  v_org uuid:=public.current_organization_id(); v_role public.user_role:=public.current_role();
  v_job public.import_jobs%rowtype; v_row jsonb; v_number integer; v_end integer;
  v_sku text; v_name text; v_unit text; v_category text; v_quantity numeric;
  v_retail numeric; v_wholesale numeric; v_distributor numeric; v_diagnostics jsonb;
  v_status text; v_existing jsonb; v_inserted integer:=0;
BEGIN
  IF v_org IS NULL OR v_role NOT IN ('owner','admin','sales') THEN RAISE EXCEPTION USING errcode='42501',message='staff import access required'; END IF;
  IF p_import_job_id IS NULL OR p_start_row IS NULL OR p_start_row<1 THEN RAISE EXCEPTION USING errcode='22023',message='invalid import chunk position'; END IF;
  IF p_rows IS NULL OR jsonb_typeof(p_rows)<>'array' OR jsonb_array_length(p_rows)<1 OR jsonb_array_length(p_rows)>5000 THEN RAISE EXCEPTION USING errcode='22023',message='chunk must contain between 1 and 5000 rows'; END IF;
  SELECT * INTO v_job FROM public.import_jobs WHERE id=p_import_job_id AND organization_id=v_org FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION USING errcode='P0002',message='import job not found'; END IF;
  IF v_job.status NOT IN ('validating','preview') THEN RAISE EXCEPTION USING errcode='P0001',message='import job is not accepting chunks'; END IF;
  v_end:=p_start_row+jsonb_array_length(p_rows)-1;
  IF v_end>v_job.total_rows THEN RAISE EXCEPTION USING errcode='22023',message='chunk exceeds declared row count'; END IF;
  FOR v_row IN SELECT value FROM jsonb_array_elements(p_rows) LOOP
    v_number:=p_start_row+v_inserted; v_sku:=upper(trim(coalesce(v_row->>'sku',''))); v_name:=trim(coalesce(v_row->>'name','')); v_unit:=trim(coalesce(v_row->>'unit','')); v_category:=trim(coalesce(v_row->>'category',''));
    v_quantity:=nullif(trim(v_row->>'quantity'),'')::numeric; v_retail:=nullif(trim(v_row #>> '{prices,retail}'),'')::numeric; v_wholesale:=nullif(trim(v_row #>> '{prices,wholesale}'),'')::numeric; v_distributor:=nullif(trim(v_row #>> '{prices,distributor}'),'')::numeric;
    v_diagnostics:='[]'::jsonb;
    IF v_sku='' THEN v_diagnostics:=v_diagnostics||jsonb_build_array(jsonb_build_object('field','sku','message','SKU is required')); END IF;
    IF v_name='' THEN v_diagnostics:=v_diagnostics||jsonb_build_array(jsonb_build_object('field','name','message','Name is required')); END IF;
    IF v_unit='' THEN v_diagnostics:=v_diagnostics||jsonb_build_array(jsonb_build_object('field','unit','message','Unit is required')); END IF;
    IF v_category='' THEN v_diagnostics:=v_diagnostics||jsonb_build_array(jsonb_build_object('field','category','message','Category is required')); END IF;
    IF length(v_sku)>80 THEN v_diagnostics:=v_diagnostics||jsonb_build_array(jsonb_build_object('field','sku','message','SKU is too long')); END IF;
    IF length(v_name)>240 THEN v_diagnostics:=v_diagnostics||jsonb_build_array(jsonb_build_object('field','name','message','Name is too long')); END IF;
    IF length(v_unit)>80 THEN v_diagnostics:=v_diagnostics||jsonb_build_array(jsonb_build_object('field','unit','message','Unit is too long')); END IF;
    IF length(v_category)>120 THEN v_diagnostics:=v_diagnostics||jsonb_build_array(jsonb_build_object('field','category','message','Category is too long')); END IF;
    IF v_quantity IS NULL OR v_quantity<0 OR mod(v_quantity,1)<>0 OR v_quantity>10000 THEN v_diagnostics:=v_diagnostics||jsonb_build_array(jsonb_build_object('field','quantity','message','Quantity is outside the allowed range')); END IF;
    IF v_retail IS NULL OR v_retail<0 THEN v_diagnostics:=v_diagnostics||jsonb_build_array(jsonb_build_object('field','price.retail','message','Price must be non-negative')); END IF;
    IF v_wholesale IS NULL OR v_wholesale<0 THEN v_diagnostics:=v_diagnostics||jsonb_build_array(jsonb_build_object('field','price.wholesale','message','Price must be non-negative')); END IF;
    IF v_distributor IS NULL OR v_distributor<0 THEN v_diagnostics:=v_diagnostics||jsonb_build_array(jsonb_build_object('field','price.distributor','message','Price must be non-negative')); END IF;
    IF EXISTS(SELECT 1 FROM public.import_rows ir WHERE ir.import_job_id=v_job.id AND ir.organization_id=v_org AND ir.row_number<>v_number AND ir.normalized_data->>'sku'=v_sku AND v_sku<>'') THEN v_diagnostics:=v_diagnostics||jsonb_build_array(jsonb_build_object('field','sku','message','Duplicate SKU in file')); END IF;
    v_status:=CASE WHEN jsonb_array_length(v_diagnostics)=0 THEN 'valid' ELSE 'invalid' END;
    v_existing:=NULL; SELECT raw_data INTO v_existing FROM public.import_rows WHERE import_job_id=v_job.id AND row_number=v_number;
    IF v_existing IS NOT NULL THEN
      IF v_existing<>v_row THEN RAISE EXCEPTION USING errcode='40001',message='chunk retry conflicts with an existing row'; END IF;
    ELSE
      INSERT INTO public.import_rows(organization_id,import_job_id,row_number,raw_data,normalized_data,status,diagnostics)
      VALUES(v_org,v_job.id,v_number,v_row,jsonb_build_object('sku',v_sku,'name',v_name,'unit',v_unit,'category',v_category,'quantity',v_quantity,'prices',jsonb_build_object('retail',v_retail,'wholesale',v_wholesale,'distributor',v_distributor)),v_status,v_diagnostics);
    END IF;
    v_inserted:=v_inserted+1;
  END LOOP;
  RETURN v_inserted;
END; $function$;

CREATE OR REPLACE FUNCTION public.finalize_product_import(p_import_job_id uuid)
RETURNS public.import_jobs LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public' AS $function$
DECLARE v_org uuid:=public.current_organization_id(); v_role public.user_role:=public.current_role(); v_job public.import_jobs%rowtype;
BEGIN
  IF v_org IS NULL OR v_role NOT IN ('owner','admin','sales') THEN RAISE EXCEPTION USING errcode='42501',message='staff import access required'; END IF;
  SELECT * INTO v_job FROM public.import_jobs WHERE id=p_import_job_id AND organization_id=v_org FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION USING errcode='P0002',message='import job not found'; END IF;
  IF v_job.status NOT IN ('validating','preview') THEN RAISE EXCEPTION USING errcode='P0001',message='import job is not finalizable'; END IF;
  IF (SELECT count(*) FROM public.import_rows WHERE import_job_id=v_job.id AND organization_id=v_org)<>v_job.total_rows THEN RAISE EXCEPTION USING errcode='P0001',message='import is incomplete; not all chunks were received'; END IF;
  UPDATE public.import_jobs j SET status='preview',valid_rows=(SELECT count(*) FROM public.import_rows WHERE import_job_id=v_job.id AND organization_id=v_org AND status='valid'),invalid_rows=(SELECT count(*) FROM public.import_rows WHERE import_job_id=v_job.id AND organization_id=v_org AND status='invalid'),error_summary=coalesce((SELECT jsonb_agg(diagnostics) FROM public.import_rows WHERE import_job_id=v_job.id AND organization_id=v_org AND status='invalid'),'[]'::jsonb) WHERE j.id=v_job.id AND j.organization_id=v_org RETURNING * INTO v_job;
  INSERT INTO public.audit_events(organization_id,actor_id,action,target_type,target_id,result,metadata) VALUES(v_org,auth.uid(),'import.finalize','import_job',v_job.id,'success',jsonb_build_object('rows',v_job.total_rows,'valid',v_job.valid_rows,'invalid',v_job.invalid_rows));
  RETURN v_job;
END; $function$;

CREATE OR REPLACE FUNCTION public.commit_product_import(p_import_job_id uuid, p_warehouse_id uuid)
RETURNS TABLE(imported_rows integer, products_created integer, products_updated integer, inventory_changed integer)
LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public' AS $function$
DECLARE
  v_org uuid := public.current_organization_id(); v_role public.user_role := public.current_role(); v_job public.import_jobs%rowtype; v_row record; v_product public.products%rowtype; v_category_id uuid; v_price_list_id uuid; v_old_qty integer := 0; v_new_qty integer; v_delta integer; v_created integer := 0; v_updated integer := 0; v_inventory_changed integer := 0; v_count integer := 0; v_slug text; v_effective_at timestamptz;
BEGIN
  IF v_org IS NULL OR v_role NOT IN ('owner','admin','sales') THEN RAISE EXCEPTION USING errcode='42501', message='staff import access required'; END IF;
  SELECT * INTO v_job FROM public.import_jobs WHERE id=p_import_job_id AND organization_id=v_org FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION USING errcode='P0002', message='import job not found'; END IF;
  IF v_job.status <> 'preview' OR v_job.invalid_rows <> 0 THEN RAISE EXCEPTION USING errcode='P0001', message='import is not ready for atomic commit'; END IF;
  IF NOT EXISTS (SELECT 1 FROM public.warehouses WHERE id=p_warehouse_id AND organization_id=v_org AND is_active) THEN RAISE EXCEPTION USING errcode='42501', message='warehouse not available'; END IF;
  INSERT INTO public.price_lists(organization_id,tier,name,currency) VALUES (v_org,'retail','تجزئة','YER'),(v_org,'wholesale','جملة','YER'),(v_org,'distributor','موزع','YER') ON CONFLICT (organization_id,tier) DO NOTHING;
  UPDATE public.import_jobs SET status='committing' WHERE id=v_job.id;
  FOR v_row IN SELECT * FROM public.import_rows WHERE import_job_id=v_job.id AND organization_id=v_org AND status='valid' ORDER BY row_number FOR UPDATE LOOP
    SELECT id INTO v_category_id FROM public.categories WHERE organization_id=v_org AND name=v_row.normalized_data->>'category' AND is_active ORDER BY created_at LIMIT 1;
    IF v_category_id IS NULL THEN v_slug := 'import-' || substr(md5(lower(trim(v_row.normalized_data->>'category'))),1,16); INSERT INTO public.categories(organization_id,name,slug) VALUES(v_org,trim(v_row.normalized_data->>'category'),v_slug) ON CONFLICT (organization_id,slug) DO UPDATE SET name=excluded.name RETURNING id INTO v_category_id; END IF;
    SELECT * INTO v_product FROM public.products WHERE organization_id=v_org AND sku=v_row.normalized_data->>'sku' FOR UPDATE;
    IF FOUND THEN UPDATE public.products SET name=v_row.normalized_data->>'name',unit=v_row.normalized_data->>'unit',category_id=v_category_id,updated_at=now(),status='active' WHERE id=v_product.id RETURNING * INTO v_product; v_updated := v_updated + 1; ELSE INSERT INTO public.products(organization_id,category_id,sku,name,unit,status) VALUES(v_org,v_category_id,v_row.normalized_data->>'sku',v_row.normalized_data->>'name',v_row.normalized_data->>'unit','active') RETURNING * INTO v_product; v_created := v_created + 1; END IF;
    v_effective_at := clock_timestamp();
    FOR v_price_list_id IN SELECT id FROM public.price_lists WHERE organization_id=v_org AND tier IN ('retail','wholesale','distributor') ORDER BY tier LOOP
      UPDATE public.product_prices SET valid_to=v_effective_at WHERE organization_id=v_org AND price_list_id=v_price_list_id AND product_id=v_product.id AND valid_from < v_effective_at AND (valid_to IS NULL OR valid_to > v_effective_at);
      INSERT INTO public.product_prices(organization_id,price_list_id,product_id,amount,valid_from) VALUES(v_org,v_price_list_id,v_product.id,CASE (SELECT tier FROM public.price_lists WHERE id=v_price_list_id) WHEN 'retail' THEN (v_row.normalized_data #>> '{prices,retail}')::numeric WHEN 'wholesale' THEN (v_row.normalized_data #>> '{prices,wholesale}')::numeric WHEN 'distributor' THEN (v_row.normalized_data #>> '{prices,distributor}')::numeric END,v_effective_at);
    END LOOP;
    v_new_qty := (v_row.normalized_data->>'quantity')::integer; SELECT quantity INTO v_old_qty FROM public.inventory_balances WHERE organization_id=v_org AND warehouse_id=p_warehouse_id AND product_id=v_product.id FOR UPDATE; v_old_qty := coalesce(v_old_qty,0);
    INSERT INTO public.inventory_balances(organization_id,warehouse_id,product_id,quantity) VALUES(v_org,p_warehouse_id,v_product.id,v_new_qty) ON CONFLICT (warehouse_id,product_id) DO UPDATE SET quantity=excluded.quantity,updated_at=now();
    v_delta := v_new_qty - v_old_qty; IF v_delta <> 0 THEN INSERT INTO public.inventory_movements(organization_id,warehouse_id,product_id,delta,source_type,source_id,actor_id) VALUES(v_org,p_warehouse_id,v_product.id,v_delta,'import',v_job.id,auth.uid()); v_inventory_changed := v_inventory_changed + 1; END IF;
    UPDATE public.import_rows SET status='committed' WHERE id=v_row.id; v_count := v_count + 1;
  END LOOP;
  UPDATE public.import_jobs SET status='completed',completed_at=clock_timestamp() WHERE id=v_job.id;
  INSERT INTO public.audit_events(organization_id,actor_id,action,target_type,target_id,result,metadata) VALUES(v_org,auth.uid(),'import.commit','import_job',v_job.id,'success',jsonb_build_object('rows',v_count,'created',v_created,'updated',v_updated,'inventory_changed',v_inventory_changed));
  RETURN QUERY SELECT v_count,v_created,v_updated,v_inventory_changed;
END; $function$;

REVOKE ALL ON FUNCTION public.begin_product_import(text,text,integer) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.stage_product_import_chunk(uuid,integer,jsonb) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.finalize_product_import(uuid) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.commit_product_import(uuid,uuid) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.begin_product_import(text,text,integer) TO authenticated;
GRANT EXECUTE ON FUNCTION public.stage_product_import_chunk(uuid,integer,jsonb) TO authenticated;
GRANT EXECUTE ON FUNCTION public.finalize_product_import(uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.commit_product_import(uuid,uuid) TO authenticated;
