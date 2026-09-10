# Canonical Baseline Assembly

This directory is the executable reconstruction target for the live canonical `public` schema.

## Required chunks

1. `01_tables_and_constraints.sql` — types, sequences, tables/columns, generated/identity properties, and constraints.
2. `02_functions_and_triggers.sql` — all 98 live public ordinary function definitions and all 16 non-internal public triggers.
3. `03_rls_and_acls.sql` — RLS enablement/policies and explicit table/sequence/function grants required by the live contract.
4. `04_indexes_and_realtime.sql` — all 340 indexes plus exact `supabase_realtime` publication membership.

## Master

`../canonical_baseline.sql` is a psql include-only master and must include chunks in dependency order.

## Gate

A chunk is not considered materialized merely because the generator exists. The gate requires the generated files to exist, object counts/hashes to match live canonical truth, and a clean replay to succeed before the reconstruction is considered executable.

Main and Production are not modified by this reconstruction.
