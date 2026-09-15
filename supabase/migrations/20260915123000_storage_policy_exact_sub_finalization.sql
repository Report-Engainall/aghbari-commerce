-- Finalize product-media Storage RLS against the canonical JWT subject setting.
-- Earlier storage hardening migrations intentionally evolve the helper functions,
-- but this migration also rebinds the policies themselves so no later migration
-- can leave storage.objects authorization dependent on auth.uid() implementation
-- details in the pgTAP harness.

DROP POLICY IF EXISTS product_media_insert ON storage.objects;
DROP POLICY IF EXISTS product_media_select ON storage.objects;
DROP POLICY IF EXISTS product_media_delete ON storage.objects;
DROP POLICY IF EXISTS product_media_update ON storage.objects;

CREATE POLICY product_media_select ON storage.objects
FOR SELECT TO authenticated
USING (
  bucket_id = 'product-media'
  AND array_length(string_to_array(name, '/'), 1) = 3
  AND split_part(name, '/', 1) = public.storage_current_organization_id()::text
  AND split_part(name, '/', 2) ~* '^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$'
  AND EXISTS (
    SELECT 1
    FROM public.products AS p
    WHERE p.id::text = split_part(name, '/', 2)
      AND p.organization_id = public.storage_current_organization_id()
      AND p.status = 'active'
  )
  AND split_part(name, '/', 3) ~* '^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}[.]webp$'
);

CREATE POLICY product_media_insert ON storage.objects
FOR INSERT TO authenticated
WITH CHECK (
  bucket_id = 'product-media'
  AND public.storage_is_staff()
  AND owner_id = nullif(current_setting('request.jwt.claim.sub', true), '')
  AND array_length(string_to_array(name, '/'), 1) = 3
  AND split_part(name, '/', 1) = public.storage_current_organization_id()::text
  AND split_part(name, '/', 2) ~* '^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$'
  AND EXISTS (
    SELECT 1
    FROM public.products AS p
    WHERE p.id::text = split_part(name, '/', 2)
      AND p.organization_id = public.storage_current_organization_id()
  )
  AND split_part(name, '/', 3) ~* '^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}[.]webp$'
);

CREATE POLICY product_media_delete ON storage.objects
FOR DELETE TO authenticated
USING (
  bucket_id = 'product-media'
  AND public.storage_is_staff()
  AND owner_id = nullif(current_setting('request.jwt.claim.sub', true), '')
  AND array_length(string_to_array(name, '/'), 1) = 3
  AND split_part(name, '/', 1) = public.storage_current_organization_id()::text
  AND split_part(name, '/', 2) ~* '^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$'
  AND EXISTS (
    SELECT 1
    FROM public.products AS p
    WHERE p.id::text = split_part(name, '/', 2)
      AND p.organization_id = public.storage_current_organization_id()
  )
  AND split_part(name, '/', 3) ~* '^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}[.]webp$'
);
