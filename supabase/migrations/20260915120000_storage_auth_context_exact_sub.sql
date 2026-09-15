-- Storage auth-context repair: use the canonical request.jwt.claim.sub setting
-- directly in SECURITY DEFINER helpers. This matches the pgTAP harness and
-- avoids relying on auth.uid() implementation details inside storage RLS.

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
  WHERE p.id = nullif(current_setting('request.jwt.claim.sub', true), '')::uuid;
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
  WHERE p.id = nullif(current_setting('request.jwt.claim.sub', true), '')::uuid;
$$;

REVOKE EXECUTE ON FUNCTION public.storage_current_organization_id() FROM PUBLIC, anon;
REVOKE EXECUTE ON FUNCTION public.storage_is_staff() FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.storage_current_organization_id() TO authenticated;
GRANT EXECUTE ON FUNCTION public.storage_is_staff() TO authenticated;
