# Canonical Remnants Provenance — 2026-09-10

## Scope

This document records the forensic classification of legacy-named columns discovered in the live canonical schema during reconstruction of a clean, replayable Supabase migration lineage.

**Protected surfaces:** `main` and Production are not modified by this reconstruction work.

## Evidence

### 1. Current repository foundation is legacy organization-based

The repository migration `0001_operational_core.sql` creates `public.organizations` and establishes `organization_id` foreign keys on core operational tables including `branches`, `warehouses`, `customers`, `profiles`, `categories`, `products`, inventory, carts, orders, order items, status history, outbox, and audit structures. It also creates `current_organization_id()` and organization-based RLS policies.

This is direct source evidence from the migration at the reconstruction branch.

### 2. Current B2B finance migration assumes a different canonical foundation

`0013_finance_b2b_pipeline.sql` immediately alters `public.sales_invoices`, creates `cash_accounts` with `company_id`, calls `current_company_id()`, reads `company_memberships`, and operates on the company-based `orders` and `sales_invoices` model.

Therefore `0013` is not a self-contained foundation migration. It is a dependent migration whose prerequisites are absent from the repository's current clean lineage.

### 3. Legacy terminology remains in selected live objects

The live schema contains selected columns named `organization_id` whose foreign-key target is `companies.id` rather than a live `organizations` table. These are classified as **legacy terminology remnants**, not evidence that `organizations` remains a canonical tenant entity.

Classification rule:

- `organization_id → companies.id`: **Legacy Remnant / Compatibility Terminology**.
- `organization_id → organizations.id`: **Legacy Architecture Dependency** and must not be introduced into the canonical baseline.
- `company_id → companies.id`: **Canonical Tenant Relation**.
- `current_company_id()`: **Canonical Runtime Tenant Authority**.

### 4. Canonical tenant authority

The live `current_company_id()` function derives the active company from `company_memberships` for the authenticated user, restricted to active/default membership. This function is therefore a runtime dependency of canonical RLS and staff/customer authorization.

## Canonical foundation dependency order

The reconstructed foundation must establish, in dependency-safe order:

1. Required PostgreSQL extensions/types.
2. `companies`.
3. `company_memberships` and tenant authority helpers.
4. `branches` and `warehouses`.
5. Core tenant-bound profiles/customer identity structures.
6. Categories/products/pricing structures required by catalog and order paths.
7. Inventory balances/movements.
8. Carts/orders/order items/history/outbox/audit structures.
9. `sales_invoices`, `payments`, and `cash_accounts`.
10. RLS, policies, grants, and security-definer helpers after their referenced objects exist.
11. Dependent RPCs/triggers and later intelligence/governance layers.

The exact ordering remains subject to dependency extraction and clean replay verification; this list is the target architecture, not a claim that replay has passed.

## Explicit exclusions

The canonical reconstruction MUST NOT:

- recreate `public.organizations` as the tenant root;
- introduce an `organizations → companies` compatibility bridge merely to satisfy old migrations;
- resurrect `operational_invoices` as the financial source of truth;
- copy legacy-named columns blindly into the new canonical model;
- declare replay success before an empty database has executed the migration chain successfully.

## Required remediation strategy

The correct remediation is a **canonical foundation replacement/re-sequencing**, not an isolated `sales_invoices` patch.

Before creating the new SHA, the branch must contain a reproducible foundation that makes the subsequent migrations' assumptions true from an empty database.

The foundation must be verified against the live canonical contract for at least:

- object existence;
- column names/types/defaults;
- PK/unique/FK constraints;
- dependency order;
- RLS enablement;
- policies;
- grants;
- required functions;
- triggers;
- RPC signatures used by the application;
- legacy-remnant classification.

## Gate state

**Canonical Foundation Reconstruction: IN PROGRESS**

**Empty DB Replay #2: NOT STARTED**

Replay #2 remains blocked until the foundation is an actual reproducible artifact. Re-running the known `sales_invoices does not exist` failure would provide no new evidence.

## Source anchors

- `supabase/migrations/0001_operational_core.sql` — legacy organization-based repository foundation.
- `supabase/migrations/0013_finance_b2b_pipeline.sql` — company-based finance dependency and current `sales_invoices` contract.
- `docs/CANONICAL-BASELINE-INVENTORY-2026-09-10.md` — reconstruction inventory and protected boundary.
