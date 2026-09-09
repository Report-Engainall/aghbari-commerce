-- Complete the unified import pipeline with resumable server-side chunking.
-- The legacy stage_product_import RPC remains available for compatibility; new clients use
-- begin -> chunk -> finalize -> commit so large files never cross the RPC payload as one request.

CREATE OR REPLACE FUNCTION public.begin_product_import(
  p_source_name text,
  p_source_fingerprint text,
  p_total_rows integer
)
RETURNS uuid
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $$
DECLARE
  v_org uuid := public.current_organization_id();
  v_role public.user_role := public.current_role();
  v_job uuid;
BEGIN
  IF v_org IS NULL OR v_role NOT IN ('owner','admin','sales') THEN
    RAISE EXCEPTION USING errcode='42501', message='staff import access required';
  END IF;
  IF nullif(trim(p_source_name),'') IS NULL OR length(trim(p_source_name)) > 180 THEN
    RAISE EXCEPTION USING errcode='22023', message='invalid source name';
  END IF;
  IF nullif(trim(p_source_fingerprint),'') IS NULL OR length(trim(p_source_fingerprint)) <> 64 OR trim(p_source_fingerprint) !~ '^[0-9a-fA-F]{64}$' THEN
    RAISE EXCEPTION USING errcode='22023', message='invalid source fingerprint';
  END IF;
  IF p_total_rows IS NULL OR p_total_rows < 1 OR p_total_rows > 100000 THEN
    RAISE EXCEPTION USING errcode='22023', message='import row count must be between 1 and 100000';
  END IF;

  INSERT INTO public.import_jobs(organization_id,source_name,source_fingerprint,status,total_rows,created_by)
  VALUES(v_org,trim(p_source_name),lower(trim(p_source_fingerprint)),'validating',p_total_rows,auth.uid())
  ON CONFLICT(organization_id,source_fingerprint) DO NOTHING
  RETURNING id INTO v_job;

  IF v_job IS NULL THEN
    SELECT id INTO v_job FROM public.import_jobs
    WHERE organization_id=v_org AND source_fingerprint=lower(trim(p_source_fingerprint));
    IF EXISTS (SELECT 1 FROM public.import_jobs WHERE id=v_job AND status IN ('completed','committing')) THEN
      RAISE EXCEPTION USING errcode='23505', message='duplicate import fingerprint';
    END IF;
    RAISE EXCEPTION USING errcode='23505', message='import fingerprint is already being processed';
  END IF;

  RETURN v_job;
END;
$$;
REVOKE ALL ON FUNCTION public.begin_product_import(text,text,integer) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.begin_product_import(text,text,integer) TO authenticated;

CREATE OR REPLACE FUNCTION public.stage_product_import_chunk(
  p_import_job_id uuid,
  p_start_row integer,
  p_rows jsonb
)
RETURNS integer
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $$
DECLARE
  v_org uuid := public.current_organization_id();
  v_role public.user_role := public.current_role();
  v_job public.import_jobs%rowtype;
  v_row jsonb;
  v_number integer;
  v_end integer;
  v_sku text;
  v_name text;
  v_unit text;
  v_category text;
  v_quantity numeric;
  v_retail numeric;
  v_wholesale numeric;
  v_distributor numeric;
  v_diagnostics jsonb;
  v_status text;
  v_existing jsonb;
  v_inserted integer := 0;
BEGIN
  IF v_org IS NULL OR v_role NOT IN ('owner','admin','sales') THEN
    RAISE EXCEPTION USING errcode='42501', message='staff import access required';
  END IF;
  IF p_import_job_id IS NULL OR p_start_row IS NULL OR p_start_row < 1 THEN
    RAISE EXCEPTION USING errcode='22023', message='invalid import chunk position';
  END IF;
  IF p_rows IS NULL OR jsonb_typeof(p_rows) <> 'array' OR jsonb_array_length(p_rows) < 1 OR jsonb_array_length(p_rows) > 5000 THEN
    RAISE EXCEPTION USING errcode='22023', message='chunk must contain between 1 and 5000 rows';
  END IF;

  SELECT * INTO v_job FROM public.import_jobs
  WHERE id=p_import_job_id AND organization_id=v_org FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION USING errcode='P0002', message='import job not found'; END IF;
  IF v_job.status NOT IN ('validating','preview') THEN
    RAISE EXCEPTION USING errcode='P0001', message='import job is not accepting chunks';
  END IF;

  v_end := p_start_row + jsonb_array_length(p_rows) - 1;
  IF v_end > v_job.total_rows THEN
    RAISE EXCEPTION USING errcode='22023', message='chunk exceeds declared row count';
  END IF;

  FOR v_row IN SELECT value FROM jsonb_array_elements(p_rows) LOOP
    v_number := p_start_row + v_inserted;
    v_sku := upper(trim(coalesce(v_row->>'sku','')));
    v_name := trim(coalesce(v_row->>'name',''));
    v_unit := trim(coalesce(v_row->>'unit',''));
    v_category := trim(coalesce(v_row->>'category',''));
    v_quantity := nullif(trim(v_row->>'quantity'),'')::numeric;
    v_retail := nullif(trim(v_row #>> '{prices,retail}'),'')::numeric;
    v_wholesale := nullif(trim(v_row #>> '{prices,wholesale}'),'')::numeric;
    v_distributor := nullif(trim(v_row #>> '{prices,distributor}'),'')::numeric;
    v_diagnostics := '[]'::jsonb;

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
    IF EXISTS (SELECT 1 FROM public.import_rows ir WHERE ir.import_job_id=v_job.id AND ir.organization_id=v_org AND ir.row_number<>v_number AND ir.normalized_data->>'sku'=v_sku AND v_sku<>'') THEN
      v_diagnostics:=v_diagnostics||jsonb_build_array(jsonb_build_object('field','sku','message','Duplicate SKU in file'));
    END IF;

    v_status:=CASE WHEN jsonb_array_length(v_diagnostics)=0 THEN 'valid' ELSE 'invalid' END;
    v_existing := NULL;
    SELECT raw_data INTO v_existing FROM public.import_rows WHERE import_job_id=v_job.id AND row_number=v_number;
    IF v_existing IS NOT NULL THEN
      IF v_existing <> v_row THEN RAISE EXCEPTION USING errcode='40001', message='chunk retry conflicts with an existing row'; END IF;
    ELSE
      INSERT INTO public.import_rows(organization_id,import_job_id,row_number,raw_data,normalized_data,status,diagnostics)
      VALUES(v_org,v_job.id,v_number,v_row,jsonb_build_object('sku',v_sku,'name',v_name,'unit',v_unit,'category',v_category,'quantity',v_quantity,'prices',jsonb_build_object('retail',v_retail,'wholesale',v_wholesale,'distributor',v_distributor)),v_status,v_diagnostics);
    END IF;
    v_inserted:=v_inserted+1;
  END LOOP;

  RETURN v_inserted;
END;
$$;
REVOKE ALL ON FUNCTION public.stage_product_import_chunk(uuid,integer,jsonb) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.stage_product_import_chunk(uuid,integer,jsonb) TO authenticated;

CREATE OR REPLACE FUNCTION public.finalize_product_import(p_import_job_id uuid)
RETURNS public.import_jobs
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $$
DECLARE
  v_org uuid := public.current_organization_id();
  v_role public.user_role := public.current_role();
  v_job public.import_jobs%rowtype;
BEGIN
  IF v_org IS NULL OR v_role NOT IN ('owner','admin','sales') THEN
    RAISE EXCEPTION USING errcode='42501', message='staff import access required';
  END IF;
  SELECT * INTO v_job FROM public.import_jobs WHERE id=p_import_job_id AND organization_id=v_org FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION USING errcode='P0002', message='import job not found'; END IF;
  IF v_job.status NOT IN ('validating','preview') THEN RAISE EXCEPTION USING errcode='P0001', message='import job is not finalizable'; END IF;
  IF (SELECT count(*) FROM public.import_rows WHERE import_job_id=v_job.id AND organization_id=v_org) <> v_job.total_rows THEN
    RAISE EXCEPTION USING errcode='P0001', message='import is incomplete; not all chunks were received';
  END IF;

  UPDATE public.import_jobs j SET
    status='preview',
    valid_rows=(SELECT count(*) FROM public.import_rows WHERE import_job_id=v_job.id AND organization_id=v_org AND status='valid'),
    invalid_rows=(SELECT count(*) FROM public.import_rows WHERE import_job_id=v_job.id AND organization_id=v_org AND status='invalid'),
    error_summary=coalesce((SELECT jsonb_agg(diagnostics) FROM public.import_rows WHERE import_job_id=v_job.id AND organization_id=v_org AND status='invalid'),'[]'::jsonb)
  WHERE j.id=v_job.id AND j.organization_id=v_org
  RETURNING * INTO v_job;

  INSERT INTO public.audit_events(organization_id,actor_id,action,target_type,target_id,result,metadata)
  VALUES(v_org,auth.uid(),'import.finalize','import_job',v_job.id,'success',jsonb_build_object('rows',v_job.total_rows,'valid',v_job.valid_rows,'invalid',v_job.invalid_rows));
  RETURN v_job;
END;
$$;
REVOKE ALL ON FUNCTION public.finalize_product_import(uuid) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.finalize_product_import(uuid) TO authenticated;
