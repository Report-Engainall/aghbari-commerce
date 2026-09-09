-- Resume an interrupted import by returning the existing in-flight job for the
-- same tenant + SHA-256 fingerprint. Completed/cancelled imports remain duplicates.
CREATE OR REPLACE FUNCTION public.begin_product_import(p_source_name text, p_source_fingerprint text, p_total_rows integer)
RETURNS uuid LANGUAGE plpgsql SECURITY DEFINER SET search_path=public AS $$
DECLARE v_org uuid:=public.current_organization_id(); v_role public.user_role:=public.current_role(); v_job public.import_jobs%rowtype;
BEGIN
 IF v_org IS NULL OR v_role NOT IN ('owner','admin','sales') THEN RAISE EXCEPTION USING errcode='42501',message='staff import access required'; END IF;
 IF nullif(trim(p_source_name),'') IS NULL OR length(trim(p_source_name))>180 THEN RAISE EXCEPTION USING errcode='22023',message='invalid source name'; END IF;
 IF nullif(trim(p_source_fingerprint),'') IS NULL OR length(trim(p_source_fingerprint))<>64 OR trim(p_source_fingerprint) !~ '^[0-9a-fA-F]{64}$' THEN RAISE EXCEPTION USING errcode='22023',message='invalid source fingerprint'; END IF;
 IF p_total_rows IS NULL OR p_total_rows<1 OR p_total_rows>100000 THEN RAISE EXCEPTION USING errcode='22023',message='import row count must be between 1 and 100000'; END IF;
 SELECT * INTO v_job FROM public.import_jobs WHERE organization_id=v_org AND source_fingerprint=lower(trim(p_source_fingerprint)) FOR UPDATE;
 IF FOUND THEN
   IF v_job.total_rows<>p_total_rows THEN RAISE EXCEPTION USING errcode='22023',message='existing import fingerprint has a different row count'; END IF;
   IF v_job.status IN ('completed','cancelled') THEN RAISE EXCEPTION USING errcode='23505',message='duplicate completed import fingerprint'; END IF;
   RETURN v_job.id;
 END IF;
 INSERT INTO public.import_jobs(organization_id,source_name,source_fingerprint,status,total_rows,created_by) VALUES(v_org,trim(p_source_name),lower(trim(p_source_fingerprint)),'validating',p_total_rows,auth.uid()) RETURNING id INTO v_job.id;
 RETURN v_job.id;
END; $$;
REVOKE ALL ON FUNCTION public.begin_product_import(text,text,integer) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.begin_product_import(text,text,integer) TO authenticated;
REVOKE EXECUTE ON FUNCTION public.begin_product_import(text,text,integer) FROM anon;
