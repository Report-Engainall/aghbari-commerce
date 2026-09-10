# Canonical Baseline Parity Gate — 2026-09-10

Status: LIVE VERIFICATION COMPLETE / EXECUTABLE BASELINE STILL BLOCKED
Branch: `reconstruction/canonical-lineage`

## Live catalog parity

The canonical live Supabase project was rechecked read-only after the emitter and verification gate were committed.

| Object class | Expected / observed | Result |
|---|---:|---|
| Public tables | 100 | PASS |
| Public functions | 98 | PASS |
| Public RLS policies | 179 | PASS |
| Public non-internal triggers | 16 | PASS |
| Public indexes | 340 | PASS |

The combined object-count gate returned `PASS`.

## Legacy extinction spot checks

Read-only catalog checks returned:

- `organizations` table: absent.
- `operational_invoices` table: absent.
- `current_organization_id()` function: absent.

Earlier body-reference extraction remains authoritative for the two live `organization_id` terminology remnants:
- `accept_customer_invitation(p_token text)`
- `current_customer_company_id()`

These do not justify reconstructing the legacy `organizations` architecture.

## Execution boundary

No live DDL/DML was executed by this gate. Main and Production remain untouched.

## Baseline gate decision

The catalog inventory is now independently revalidated at the exact target counts. This closes the **inventory-count parity** gate only.

It does **not** yet close executable baseline parity because exact function bodies, policies, indexes, constraints, triggers, grants, defaults, identity/generated expressions and their serialized SQL must still be assembled and compared without truncation.

## Next gate

Complete deterministic extraction/assembly, run `verify_canonical_baseline.sql` against the assembled target, perform clean empty-database replay, and bind the replay result to the Foundation Commit SHA and run evidence.
