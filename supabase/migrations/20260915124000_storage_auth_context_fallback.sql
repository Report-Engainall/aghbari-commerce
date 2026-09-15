-- Final storage authorization context repair.
-- Prefer the canonical JWT subject GUC used by the pgTAP harness, but fall back
-- to auth.uid() so the same policies remain correct when Supabase Storage/Auth
-- exposes the subject through the auth helper rather than the request GUC.

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
  WHERE p.id = COALESCE(
    nullif(current_setting('request.jwt.claim.sub', true), '')::uuid,
    auth.uid()
  );
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
  WHERE p.id = COALESCE(
    nullif(current_setting('request.jwt.claim.sub', true), '')::uuid,
    auth.uid()
  );
$$;

REVOKE EXECUTE ON FUNCTION public.storage_current_organization_id() FROM PUBLIC, anon;
REVOKE EXECUTE ON FUNCTION public.storage_is_staff() FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.storage_current_organization_id() TO authenticated;
GRANT EXECUTE ON FUNCTION public.storage_is_staff() TO authenticated;
