-- Exact clean-DB replay repairs from target SHA 296cfb9.
-- 1) Storage authorization helpers must resolve the JWT subject reliably inside
--    SECURITY DEFINER execution used by storage.objects RLS.
-- 2) record_expense was recreated after the global function grant lockdown and
--    therefore inherited the default PUBLIC/anon EXECUTE privilege.
-- 3) register_product_media must classify a structurally valid foreign-org path
--    as authorization failure before payload validation can mask the boundary.

CREATE OR REPLACE FUNCTION public.storage_current_organization_id()
RETURNS uuid
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public, pg_temp
SET row_security = off
AS $$
  SELECT p.organization_id
  FROM public.profiles AS p
  WHERE p.id = nullif((current_setting('request.jwt.claims', true)::jsonb ->> 'sub'), '')::uuid;
$$;

CREATE OR REPLACE FUNCTION public.storage_is_staff()
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public, pg_temp
SET row_security = off
AS $$
  SELECT COALESCE(p.role IN ('owner','admin','sales','warehouse'), false)
  FROM public.profiles AS p
  WHERE p.id = nullif((current_setting('request.jwt.claims', true)::jsonb ->> 'sub'), '')::uuid;
$$;

REVOKE EXECUTE ON FUNCTION public.storage_current_organization_id() FROM PUBLIC, anon;
REVOKE EXECUTE ON FUNCTION public.storage_is_staff() FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.storage_current_organization_id() TO authenticated;
GRANT EXECUTE ON FUNCTION public.storage_is_staff() TO authenticated;

CREATE OR REPLACE FUNCTION public.register_product_media(
  p_product_id uuid,
  p_storage_path text,
  p_mime_type text,
  p_width integer,
  p_height integer,
  p_byte_size bigint
)
RETURNS uuid
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, storage, pg_temp
AS $$
DECLARE
  v_org uuid := public.storage_current_organization_id();
  v_role public.user_role := public.current_role();
  v_media_id uuid;
  v_object storage.objects%rowtype;
  v_object_mime text;
  v_object_size bigint;
  v_actor uuid := nullif((current_setting('request.jwt.claims', true)::jsonb ->> 'sub'), '')::uuid;
BEGIN
  IF v_org IS NULL OR v_role NOT IN ('owner','admin','sales') THEN
    RAISE EXCEPTION USING errcode='42501', message='product media registration access required';
  END IF;

  IF p_storage_path IS NOT NULL
     AND split_part(p_storage_path,'/',1) ~* '^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$'
     AND split_part(p_storage_path,'/',1)::uuid <> v_org THEN
    RAISE EXCEPTION USING errcode='42501', message='product media tenant binding failed';
  END IF;

  IF p_product_id IS NULL OR p_storage_path IS NULL
     OR p_storage_path !~* '^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}/[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}/[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}[.]webp$' THEN
    RAISE EXCEPTION USING errcode='22023', message='invalid product media path';
  END IF;

  IF split_part(p_storage_path,'/',2)::uuid <> p_product_id THEN
    RAISE EXCEPTION USING errcode='42501', message='product media tenant binding failed';
  END IF;

  IF NOT EXISTS (SELECT 1 FROM public.products p WHERE p.id=p_product_id AND p.organization_id=v_org) THEN
    RAISE EXCEPTION USING errcode='P0002', message='product not found';
  END IF;

  IF lower(coalesce(p_mime_type,'')) <> 'image/webp' THEN
    RAISE EXCEPTION USING errcode='22023', message='product images must be WebP';
  END IF;

  IF p_width IS NULL OR p_height IS NULL OR p_width < 1 OR p_height < 1 OR p_width > 4096 OR p_height > 4096 THEN
    RAISE EXCEPTION USING errcode='22023', message='invalid product image dimensions';
  END IF;

  IF p_byte_size IS NULL OR p_byte_size < 1 OR p_byte_size > 5 * 1024 * 1024 THEN
    RAISE EXCEPTION USING errcode='22023', message='product image size must be between 1 byte and 5 MB';
  END IF;

  SELECT * INTO v_object FROM storage.objects WHERE bucket_id='product-media' AND name=p_storage_path;
  IF NOT FOUND THEN
    RAISE EXCEPTION USING errcode='P0002', message='uploaded product media not found';
  END IF;

  v_object_mime := lower(coalesce(v_object.metadata->>'mimetype',''));
  v_object_size := nullif(v_object.metadata->>'size','')::bigint;
  IF v_object_mime <> 'image/webp' OR v_object_size IS NULL OR v_object_size <> p_byte_size THEN
    RAISE EXCEPTION USING errcode='22023', message='uploaded product media metadata mismatch';
  END IF;

  IF v_object.owner_id IS NOT NULL AND v_object.owner_id <> v_actor::text THEN
    RAISE EXCEPTION USING errcode='42501', message='product media owner mismatch';
  END IF;

  INSERT INTO public.product_media(organization_id,product_id,storage_path,mime_type,width,height,byte_size,sort_order)
  VALUES(v_org,p_product_id,p_storage_path,'image/webp',p_width,p_height,p_byte_size,
         COALESCE((SELECT max(sort_order)+1 FROM public.product_media WHERE organization_id=v_org AND product_id=p_product_id),0))
  RETURNING id INTO v_media_id;

  INSERT INTO public.audit_events(organization_id,actor_id,action,target_type,target_id,result,metadata)
  VALUES(v_org,v_actor,'product-media.register','product_media',v_media_id,'success',jsonb_build_object('product_id',p_product_id,'mime_type','image/webp','bytes',p_byte_size));

  RETURN v_media_id;
END;
$$;

GRANT EXECUTE ON FUNCTION public.register_product_media(uuid,text,text,integer,integer,bigint) TO authenticated;
REVOKE EXECUTE ON FUNCTION public.register_product_media(uuid,text,text,integer,integer,bigint) FROM PUBLIC, anon;
REVOKE EXECUTE ON FUNCTION public.record_expense(uuid,uuid,text,numeric,text,text,date) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.record_expense(uuid,uuid,text,numeric,text,text,date) TO authenticated;
