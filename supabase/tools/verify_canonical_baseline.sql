-- Canonical Baseline Static/Live Verification Gate
-- Run against the LIVE source before Foundation Commit and against an EMPTY replay target after assembly.
-- Read-only. No DDL/DML.
\pset tuples_only on
\pset format aligned
\pset pager off

WITH counts AS (
  SELECT
    (SELECT count(*) FROM pg_class c JOIN pg_namespace n ON n.oid=c.relnamespace WHERE n.nspname='public' AND c.relkind='r') AS tables,
    (SELECT count(*) FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace WHERE n.nspname='public' AND p.prokind='f') AS functions,
    (SELECT count(*) FROM pg_policy pol JOIN pg_class c ON c.oid=pol.polrelid JOIN pg_namespace n ON n.oid=c.relnamespace WHERE n.nspname='public') AS policies,
    (SELECT count(*) FROM pg_trigger t JOIN pg_class c ON c.oid=t.tgrelid JOIN pg_namespace n ON n.oid=c.relnamespace WHERE n.nspname='public' AND NOT t.tgisinternal) AS triggers,
    (SELECT count(*) FROM pg_index i JOIN pg_class tc ON tc.oid=i.indrelid JOIN pg_namespace n ON n.oid=tc.relnamespace WHERE n.nspname='public') AS indexes
)
SELECT *,
  CASE WHEN tables=100 AND functions=98 AND policies=179 AND triggers=16 AND indexes=340 THEN 'PASS' ELSE 'FAIL' END AS parity_gate
FROM counts;

SELECT 'forbidden_object_scan' AS gate,
       CASE WHEN count(*)=0 THEN 'PASS' ELSE 'FAIL' END AS result,
       coalesce(string_agg(format('%s.%s', n.nspname, c.relname), ', '), 'none') AS findings
FROM pg_class c
JOIN pg_namespace n ON n.oid=c.relnamespace
WHERE n.nspname='public' AND c.relname IN ('organizations','operational_invoices');

SELECT 'forbidden_function_scan' AS gate,
       CASE WHEN count(*)=0 THEN 'PASS' ELSE 'FAIL' END AS result,
       coalesce(string_agg(p.proname, ', ' ORDER BY p.proname), 'none') AS findings
FROM pg_proc p
JOIN pg_namespace n ON n.oid=p.pronamespace
WHERE n.nspname='public' AND p.proname='current_organization_id';

SELECT 'forbidden_legacy_reference_scan' AS gate,
       CASE WHEN count(*)=0 THEN 'PASS' ELSE 'FAIL' END AS result,
       coalesce(string_agg(p.proname || '(' || pg_get_function_identity_arguments(p.oid) || ')', ', ' ORDER BY p.proname), 'none') AS findings
FROM pg_proc p
JOIN pg_namespace n ON n.oid=p.pronamespace
WHERE n.nspname='public'
  AND pg_get_functiondef(p.oid) ~* '(organizations|operational_invoices|current_organization_id)';

SELECT 'organization_id_remnant_scan' AS gate,
       count(*) AS live_function_references,
       coalesce(string_agg(p.proname || '(' || pg_get_function_identity_arguments(p.oid) || ')', ', ' ORDER BY p.proname), 'none') AS findings
FROM pg_proc p
JOIN pg_namespace n ON n.oid=p.pronamespace
WHERE n.nspname='public'
  AND pg_get_functiondef(p.oid) ~* '\morganization_id\M';

SELECT 'rls_enabled_tables' AS gate,
       count(*) FILTER (WHERE c.relrowsecurity) AS enabled,
       count(*) AS public_tables,
       CASE WHEN count(*) FILTER (WHERE c.relrowsecurity) > 0 THEN 'INFO' ELSE 'CHECK' END AS result
FROM pg_class c
JOIN pg_namespace n ON n.oid=c.relnamespace
WHERE n.nspname='public' AND c.relkind='r';

SELECT 'identity_generated_columns' AS gate,
       count(*) FILTER (WHERE a.attidentity <> '') AS identity_columns,
       count(*) FILTER (WHERE a.attgenerated <> '') AS generated_columns
FROM pg_attribute a
JOIN pg_class c ON c.oid=a.attrelid
JOIN pg_namespace n ON n.oid=c.relnamespace
WHERE n.nspname='public' AND c.relkind='r' AND a.attnum > 0 AND NOT a.attisdropped;

SELECT 'known_critical_identity/generated' AS gate,
       count(*) FILTER (WHERE c.relname='orders' AND a.attname='order_number' AND a.attidentity='a') AS orders_identity_ok,
       count(*) FILTER (WHERE c.relname='cash_accounts' AND a.attname='current_balance' AND a.attgenerated='s') AS cash_generated_ok,
       count(*) FILTER (WHERE c.relname='customer_credit_accounts' AND a.attname='available_credit' AND a.attgenerated='s') AS credit_generated_ok
FROM pg_attribute a
JOIN pg_class c ON c.oid=a.attrelid
JOIN pg_namespace n ON n.oid=c.relnamespace
WHERE n.nspname='public' AND c.relkind='r' AND a.attnum > 0 AND NOT a.attisdropped;

SELECT 'critical_tenant_guards' AS gate,
       count(*) AS composite_fk_count,
       CASE WHEN count(*) >= 4 THEN 'PASS' ELSE 'FAIL' END AS result
FROM pg_constraint con
JOIN pg_class c ON c.oid=con.conrelid
JOIN pg_namespace n ON n.oid=c.relnamespace
WHERE n.nspname='public' AND con.contype='f' AND cardinality(con.conkey) > 1;

SELECT 'critical_rpc_presence' AS gate,
       count(*) FILTER (WHERE p.proname='create_order') AS create_order,
       count(*) FILTER (WHERE p.proname='transition_order') AS transition_order,
       count(*) FILTER (WHERE p.proname='record_payment') AS record_payment,
       count(*) FILTER (WHERE p.proname='create_invoice_from_order') AS create_invoice_from_order
FROM pg_proc p
JOIN pg_namespace n ON n.oid=p.pronamespace
WHERE n.nspname='public';
