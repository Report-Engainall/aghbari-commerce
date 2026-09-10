-- CANONICAL BASELINE CHUNK 02
-- 98 live public ordinary function definitions + public triggers.
-- Master dispatcher: generated atomic function chunks are included in deterministic order.
\echo 'CHUNK 02: functions and triggers'
\ir 02_functions/01-10.sql
\ir 02_functions/11-20.sql
-- Remaining function chunks are materialized by the canonical exporter from pg_get_functiondef().
-- They MUST NOT be hand-authored or inferred.
