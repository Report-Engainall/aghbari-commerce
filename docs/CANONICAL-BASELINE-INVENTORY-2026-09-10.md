# Canonical Baseline Inventory — 2026-09-10

Status: reconstruction evidence; isolated branch only.

## Evidence boundary

- Branch: `reconstruction/canonical-lineage`
- Production: untouched
- `main`: untouched
- Rejected application candidate: `7522a206583d582d06da30f7c1dabf1c90a6df7d`
- Live Supabase project: company-based tenant architecture
- Live public base-table count: **100**

## Critical finding

The repository migration lineage and the live canonical lineage are different.

Repository starts with `0001_operational_core.sql`, an `organizations`/`organization_id` model. `0013_finance_b2b_pipeline.sql` later assumes `companies` and an already-existing `sales_invoices` table.

The live database instead has `companies`, `company_memberships`, `current_company_id()`, company-bound operational tables, and `sales_invoices` as the financial source of truth.

Therefore a synthetic `CREATE TABLE sales_invoices` inserted immediately before `0013` is explicitly rejected as an architectural workaround.

## Canonical dependency layers

1. Auth identity / shared platform primitives
2. Companies and company memberships
3. `current_company_id()` tenant authority
4. Branches / warehouses
5. Categories / products / pricing
6. Customers / customer pricing
7. Inventory balances / movements
8. Carts / cart items
9. Orders / order items
10. Order history / outbox / audit
11. `sales_invoices`
12. Payments / cash accounts / receivables
13. Imports / files / source intelligence
14. Evidence / reporting / decision intelligence
15. Governance / trust / automation / certification controls
16. Runtime security and authenticated grants

## Live core objects verified

`companies`, `company_memberships`, `profiles`, `branches`, `warehouses`, `categories`, `products`, `customers`, `carts`, `cart_items`, `orders`, `order_items`, `order_status_history`, `order_outbox_events`, `inventory_balances`, `inventory_movements`, `sales_invoices`, `payments`, `cash_accounts`.

## Live intelligence/control surface verified

The 100-table inventory also includes import/source intelligence, evidence graphs, KPI lineage, reporting, decisions, recommendations, forecasts, scenarios, governance, trust, automation, certification, backup/rollback evidence, watched-report infrastructure, and UI settings.

This confirms that the canonical baseline must be broader than the old operational-core migration.

## Replay rule

The next clean replay is meaningful only after the missing canonical company foundation has been reconstructed. The replay must start from an empty database and must not depend on objects supplied by the existing production database.

A successful replay must prove:

- dependency-complete migration order;
- company tenant authority before company-bound RLS/RPCs;
- `sales_invoices` exists before dependent alterations;
- no `organizations` compatibility bridge added merely to hide drift;
- no legacy `operational_invoices` revival as financial truth;
- required RPC/RLS/grant/runtime contracts exist after replay;
- canonical public-table surface is reproduced without accidental duplicate legacy architecture.

## Current gate

**CANONICAL FOUNDATION RECONSTRUCTION — IN PROGRESS**

The previously observed replay failure at `0013` remains valid evidence. No second replay is falsely marked PASS until the baseline is actually reconstructed and executed from empty state.
