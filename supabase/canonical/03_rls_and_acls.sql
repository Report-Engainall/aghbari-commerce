-- CANONICAL BASELINE CHUNK 03
-- Live canonical RLS policies and ACL/grant surface.
-- Source of truth: pg_catalog on the live canonical database.

\echo 'CHUNK 03: RLS policies and ACLs'

-- RLS policies are emitted by pg_dump in dependency-safe form.
-- Explicit table, sequence and function grants are emitted by
-- supabase/tools/emit_canonical_runtime.sql using aclexplode().
