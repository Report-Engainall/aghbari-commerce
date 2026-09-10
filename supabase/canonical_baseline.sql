-- CANONICAL BASELINE AGGREGATOR
-- This file is intentionally an include-only manifest. The four canonical chunks are
-- materialized from the live database by supabase/tools/export_canonical_baseline.sh.
-- Do not execute this manifest against production; use the generated artifact after
-- provenance and replay verification.

\ir canonical/01_tables_and_constraints.sql
\ir canonical/02_functions_and_triggers.sql
\ir canonical/03_rls_and_acls.sql
\ir canonical/04_indexes_and_realtime.sql
