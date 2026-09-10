# Canonical Foundation Draft — 2026-09-10

## Status

DRAFT / RECONSTRUCTION ONLY. This branch is isolated from `main` and Production.

## Objective

Establish one reproducible company-based foundation that can be replayed on an empty PostgreSQL/Supabase database before any business-domain migration is allowed to depend on it.

## Canonical tenant contract

- `companies` is the tenant root.
- `company_memberships` binds authenticated users to companies and roles.
- `current_company_id()` is the runtime tenant authority.
- Domain tables use `company_id` for tenant ownership.
- Legacy `organizations` is not recreated.
- Legacy `operational_invoices` is not recreated.
- No compatibility bridge is introduced merely to satisfy historical migrations.

## Required dependency layers

1. Extensions, enums, and shared scalar types.
2. `companies`.
3. `company_memberships`, authentication/profile identity, and tenant-authority helpers.
4. `branches`, `warehouses`.
5. `customers` and customer identity/supporting tables.
6. `categories`, `products`, media, price lists, prices, tiers.
7. Inventory balances and movements.
8. Carts, cart items, orders, order items, order history, outbox, audit.
9. Canonical finance: `sales_invoices`, `payments`, `cash_accounts` and their supporting finance objects.
10. RLS, policies, grants, security-definer helper functions.
11. RPCs, triggers, intelligence, governance, reporting, and control-plane layers.

## Historical migration treatment

The numbered legacy migrations are evidence of an earlier architecture, not automatically authoritative for the reconstructed baseline. Any migration whose SQL directly requires `organizations`, `current_organization_id()`, or organization-scoped columns must either be superseded/re-sequenced or explicitly classified as legacy before replay.

`0013_finance_b2b_pipeline.sql` cannot run until canonical `sales_invoices` exists. A superficial table creation immediately before `0013` is rejected because it would preserve unresolved dependency divergence.

`0032_finance_invoices_cash_expenses.sql` contains the obsolete `operational_invoices` model and therefore cannot be promoted into the canonical foundation.

## Foundation acceptance criteria

The foundation is not complete until:

- every object it creates has a deterministic dependency predecessor;
- every canonical tenant FK resolves to `companies` or the appropriate canonical tenant-owned parent;
- runtime tenant authority resolves through `current_company_id()`;
- `sales_invoices` exists before any migration/RPC that alters or references it;
- no canonical object requires `organizations`;
- no canonical finance path requires `operational_invoices`;
- RLS/security-definer functions can be created only after their referenced tables/helpers exist;
- the resulting migration chain can be applied to an empty database without relying on the current production database state.

## Replay rule

Do not label this draft PASS. Empty DB Replay #2 starts only after the foundation and its dependent migration ordering are committed. Every replay failure becomes evidence for the next DAG correction.
