# Canonical Baseline Assembly Forensics — 2026-09-10

Status: RECONSTRUCTION / EVIDENCE ONLY

## Live extraction checkpoints
- public tables: 100
- public functions: 98
- public non-internal triggers: 16
- public RLS policies: 179
- public indexes: 340
- non-plpgsql extensions observed: pg_stat_statements 1.11, pgcrypto 1.3, uuid-ossp 1.1, supabase_vault 0.3.1 (plus built-in plpgsql 1.0).
- public sequence: `orders_order_number_seq` (bigint).

## Critical definition fidelity findings
1. `orders.order_number` is an identity column (`attidentity = 'a'`). It must not be reconstructed as an ordinary default column.
2. `cash_accounts.current_balance` is a stored generated column (`attgenerated = 's'`) with expression `(opening_balance + received) - spent`.
3. `customer_credit_accounts.available_credit` is a stored generated column with expression `GREATEST(credit_limit - outstanding_balance, 0)`.
4. Default expressions must be reconstructed from `pg_get_expr`, not guessed from application migrations.
5. `profiles.organization_id` and `client_ui_settings.organization_id` still exist in the live schema. Current evidence shows no foreign-key constraint from these columns to `organizations`; they are therefore terminology/schema remnants requiring explicit preservation during baseline reconstruction and separate hardening/migration analysis.
6. No public FK definition referencing `organizations` was found in the targeted live constraint scan.

## Assembly rule
The baseline generator must preserve column identity/generated semantics, exact default expressions, nullability, constraints, indexes, RLS, policies, trigger definitions, function definitions, and grants. A column-only reconstruction is not an executable parity baseline.

## Current gate
The evidence is sufficient to continue assembly, but the Executable Canonical Baseline is NOT declared complete. The connector extraction surface returns large catalog payloads in bounded responses; definitions therefore must be assembled in deterministic batches and checked for completeness before committing the executable baseline.

## Safety boundary
No live DDL was executed. Main and Production remain untouched. This artifact does not authorize privilege hardening or schema mutation in the live project.

## Next execution gate
Deterministic batched extraction of exact table constraints/indexes/policies, then exact function/trigger definitions, followed by static legacy-token scan and completeness counts before Foundation Commit.