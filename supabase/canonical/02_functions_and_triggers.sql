-- CANONICAL BASELINE CHUNK 02
-- 98 live public ordinary function definitions + public triggers.
-- Source of truth: pg_catalog / pg_get_functiondef() on the live canonical database.
-- Materialization is performed by the canonical exporter to avoid API truncation.

\echo 'CHUNK 02: functions and triggers'

-- Deterministic function extraction contract:
-- select pg_get_functiondef(p.oid)
-- from pg_proc p join pg_namespace n on n.oid=p.pronamespace
-- where n.nspname='public' and p.prokind='f'
-- order by n.nspname,p.proname,pg_get_function_identity_arguments(p.oid),p.oid;
