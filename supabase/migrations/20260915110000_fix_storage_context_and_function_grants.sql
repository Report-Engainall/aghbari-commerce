-- Exact clean-DB replay repairs from target SHA 296cfb9.
-- 1) Storage authorization helpers must resolve the JWT subject reliably inside
--    SECURITY DEFINER execution used by storage.objects RLS.
-- 2) record_expense was recreated after the global function grant lockdown and
--    therefore inherited the default PUBLIC/anon EXECUTE privilege.

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

REVOKE EXECUTE ON FUNCTION public.record_expense(uuid,uuid,text,numeric,text,text,date) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.record_expense(uuid,uuid,text,numeric,text,text,date) TO authenticated;
