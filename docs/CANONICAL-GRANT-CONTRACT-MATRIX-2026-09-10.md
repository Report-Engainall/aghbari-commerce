# Canonical Grant Contract Matrix — 2026-09-10

Status: RECONSTRUCTION / EVIDENCE ONLY

## Scope

This artifact records the live privilege surface before any hardening mutation. It is not a migration and must not be treated as a production security certification.

## Live finding

For `public` tables, the live database currently grants `INSERT`, `UPDATE`, or `DELETE` to `authenticated` on 55 distinct tables. No `anon` direct-write rows were returned by the audited query.

Priority commerce/finance tables are not all equivalent contracts. Direct write capability must therefore be classified against actual frontend/RPC consumers before any revoke is proposed.

## Critical write-surface review

The following are mandatory contract-review targets:

- `inventory_balances`
- `inventory_movements`
- `orders`
- `order_items`
- `sales_invoices`
- `payments`
- `customers`
- `products`
- import tables
- decision/governance/evidence tables

## Security rule

A live GRANT is preserved as Live Truth for baseline reconstruction. It is not automatically declared canonical. The final contract must be derived from:

`Frontend consumer -> RPC/direct SQL -> RLS -> tenant authority -> side effects -> audit/evidence`

## Explicit non-decisions

- No production GRANT was changed.
- No RLS policy was changed.
- No privilege was revoked merely because it appeared broad.
- No Foundation Commit was declared.
- No Replay was started.

## Baseline requirement

The executable baseline must reproduce the verified live privilege surface first, unless a deliberate hardening migration is separately designed, tested, evidenced, and applied after baseline replay.

## Gate

Grant Contract Reconstruction remains OPEN until direct-write contracts are classified. Foundation SQL remains BLOCKED until this gate and all prerequisite dependency ordering are complete.
