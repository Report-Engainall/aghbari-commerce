# Canonical Lineage Reconstruction — Aghbari Commerce

Status: forensic reconstruction / isolated branch only.

## Boundary

- Production and `main` are not modified by this investigation.
- Rejected candidate remains `7522a206583d582d06da30f7c1dabf1c90a6df7d`.
- `sales_invoices` remains the financial source of truth.
- `operational_invoices` is legacy lineage and is not a repair target.
- No production certification is implied by this document.

## 1. B2B vs Shared Classification

### Shared/platform foundation

These capabilities are cross-cutting infrastructure and must not be allowed to define tenant ownership by themselves:

- authentication identity (`auth.users`)
- profiles / identity metadata
- audit/event infrastructure
- storage and file/intelligence infrastructure
- generic RPC execution/security controls
- decision/report/evidence/governance infrastructure
- Realtime/event delivery mechanisms

### B2B tenant/domain foundation

The current live operational model is company-based. The authoritative tenant boundary is:

`companies -> company_memberships -> current_company_id()`

Business entities then hang from the company boundary:

`companies -> branches -> warehouses`

`companies -> customers`

`companies -> categories -> products`

`companies -> inventory_balances / inventory_movements`

`companies -> carts -> cart_items`

`companies -> orders -> order_items / order_status_history / order_outbox_events`

`companies -> sales_invoices -> payments`

`companies -> cash_accounts`

This classification is based on direct live-schema inspection and the current company-based runtime contracts.

## 2. First Divergence

The repository migration chain begins with `0001_operational_core.sql`, which creates an `organizations`-based operational model. Its branches, warehouses, customers, profiles, products, inventory, carts and orders use `organization_id`.

The later repository migration `0013_finance_b2b_pipeline.sql` assumes a different, company-based model and references `public.sales_invoices` before establishing that table in the repository chain.

The clean replay failure at `0013` therefore is a lineage/dependency failure, not merely a missing-column defect.

The live database predates the repository migration chain and contains a separate canonical company-based lineage beginning with migrations such as:

- `20260817182847_01_core_schema`
- `20260817185322_02_file_intelligence_schema`
- `20260822200000_canonical_tenant_membership`
- `20260822212000_canonical_tenant_membership`

followed by the current company/security/runtime/finance evolution.

The available Git repository history does not currently provide evidence that those live canonical migration files are present under equivalent names in the repository. Therefore the canonical baseline cannot safely be inferred by inserting a synthetic `CREATE TABLE sales_invoices` immediately before `0013`.

## 3. Dependency DAG — Operational Core

```text
AUTH IDENTITY
    |
    v
companies
    |
    +--> company_memberships --> current_company_id()
    |
    +--> branches --> warehouses
    |
    +--> categories --> products
    |                    |
    |                    +--> product pricing / customer pricing
    |
    +--> customers
    |       |
    |       +--> carts --> cart_items --> products
    |       |
    |       +--> orders --> order_items --> products
    |                    |
    |                    +--> inventory reservation/deduction
    |                    +--> order_status_history
    |                    +--> order_outbox_events
    |                    +--> completion --> sales_invoices
    |
    +--> inventory_balances <--> inventory_movements
    |
    +--> sales_invoices --> payments
    |          |
    |          +--> receivables / dashboard truth
    |
    +--> cash_accounts --> payment cash settlement
    |
    +--> audit_logs / audit_events
```

## 4. Required Canonical Baseline Ordering

The reconstruction baseline must establish dependencies in this order (exact migration filenames may differ):

1. Extensions and PostgreSQL/Auth integration primitives.
2. `companies` and canonical tenant membership.
3. `current_company_id()` and tenant authorization primitives.
4. Branches and warehouses with company-consistent foreign keys.
5. Categories and products.
6. Customers and customer pricing identity.
7. Inventory balances and movement ledger.
8. Carts and cart items.
9. Orders and order items.
10. Order lifecycle/history/outbox/audit infrastructure.
11. `sales_invoices` and its company/customer/order relationships.
12. Payments and cash accounts.
13. Finance/receivables RPCs.
14. B2B runtime hardening and authenticated grants.
15. Higher-level intelligence, evidence, decision and reporting layers.

## 5. Replay Gate

A clean replay is considered structurally passing only when:

- the database can be created from an empty state;
- every migration executes in dependency order without relying on pre-existing live objects;
- `sales_invoices` exists before any migration alters or references it;
- no legacy `organizations` compatibility bridge is introduced merely to hide lineage drift;
- company tenant authority is established before company-bound RLS/RPCs;
- later runtime migrations can execute without objects silently supplied by the production database;
- schema/RPC/RLS/grant contracts required by the application exist in the replayed database.

## 6. Current Decision

**Do not patch `0013` with a synthetic invoice table.**

The next engineering action is reconstruction of the missing canonical company foundation, followed by a clean empty-database replay. Only failures revealed by that replay may drive the next migration corrections.

After replay passes, the sequence remains:

`security/performance hardening -> exact-SHA CI -> authenticated E2E -> production runtime evidence -> final production certification`.
