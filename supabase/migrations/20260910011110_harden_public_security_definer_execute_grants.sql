-- Migration-lineage reconciliation for the security-definer execution boundary.
-- The remote staging database has this migration version applied; keep the source
-- history reproducible for clean replay without widening RPC execution privileges.
DO $$
DECLARE
  r record;
BEGIN
  FOR r IN
    SELECT p.oid::regprocedure AS signature,
           (p.oid = 'public.notify_order_status_change()'::regprocedure) AS trigger_only
    FROM pg_proc p
    JOIN pg_namespace n ON n.oid = p.pronamespace
    WHERE n.nspname = 'public'
      AND p.prosecdef
  LOOP
    EXECUTE format('REVOKE ALL ON FUNCTION %s FROM public, anon;', r.signature);
    IF NOT r.trigger_only THEN
      EXECUTE format('GRANT EXECUTE ON FUNCTION %s TO authenticated;', r.signature);
    END IF;
  END LOOP;
END $$;
