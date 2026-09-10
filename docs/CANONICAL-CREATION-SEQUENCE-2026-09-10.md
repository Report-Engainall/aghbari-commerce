# Canonical Object Creation Sequence — 2026-09-10

Status: RECONSTRUCTION / EVIDENCE-BOUND DESIGN
Branch: `reconstruction/canonical-lineage`

## Purpose
Define the executable ordering required to reconstruct the live canonical schema without replaying the legacy organization-based migration chain.

## Canonical sequence

### 0. Preflight
- Empty target database only.
- Required PostgreSQL/Supabase extensions verified.
- No application migrations executed against production.
- Baseline must be generated from the live canonical object inventory, not from legacy `0001–0053` as the source of truth.

### 1. Extensions
Create only extensions proven present in the live canonical inventory and required by object definitions.

### 2. Types / Domains
Create live custom ENUM/domain types if any are proven. Current public type audit found no custom public ENUM or DOMAIN types; table rowtypes are not custom types and must not be emitted as CREATE TYPE statements.

### 3. Sequences
Create the proven public sequence `orders_order_number_seq` before any default expression that references it.

### 4. Base Tables
Create tables in dependency layers, with primary keys, NOT NULL, identity/generated definitions, defaults, and table-local CHECK/UNIQUE constraints where they do not require later cross-table objects.

Core dependency layers:
1. companies
2. company_memberships / tenant authority prerequisites
3. branches / warehouses
4. profiles / customer identity
5. categories / products / pricing/reference data
6. inventory
7. carts / cart_items
8. orders / order_items / order_status_history / order_outbox_events
9. customers and customer B2B controls where dependency permits
10. sales_invoices / payments / cash_accounts
11. import/file intelligence
12. decision / governance / evidence / reporting / autonomy objects

Where two tables form a cycle, create both without the cross-table FK, then add the FK in the constraint phase.

### 5. Indexes required before/with relational guards
Create primary/unique indexes and other proven live indexes needed by constraints, lookup paths, and later foreign-key enforcement. Do not infer new indexes during baseline reconstruction.

### 6. Foreign Keys and Composite Tenant Guards
Add cross-table FKs after all referenced tables exist. Preserve proven composite tenant guards, including:
- inventory_balances(company_id, product_id) → products(company_id, id)
- inventory_balances(company_id, warehouse_id) → warehouses(company_id, id)
- sales_invoices(company_id, customer_id) → customers(company_id, id)
- sales_invoices(company_id, branch_id) → branches(company_id, id)

### 7. Base Security / Tenant Authority Functions
Create functions required by RLS and other function bodies before policies are created, including the proven canonical `current_company_id()` contract and customer identity helpers. Preserve the live `organization_id` column/function references only where they are proven terminology remnants carrying company UUID semantics; do not recreate the legacy organizations architecture.

### 8. Function Body Dependency Layers
Create the 98 proven public functions in topological tiers based on actual body references rather than `pg_depend` alone.

Tier A — primitive/security helpers
Tier B — tenant/customer authorization and reusable validators
Tier C — CRUD/read helpers and import primitives
Tier D — transactional business commands
Tier E — finance/order completion and derived operations
Tier F — governance/intelligence/reporting functions
Tier G — certification/autonomy/control-plane functions

Functions referenced by trigger definitions must exist before their triggers. Functions used only by RLS must exist before policies.

### 9. RLS Enablement
Enable RLS on every proven RLS-enabled table before installing its policies.

### 10. RLS Policies
Create the 179 proven policies only after their referenced functions/tables exist. Preserve tenant-bound predicates, parent-tenant checks, customer identity boundaries, and role conditions exactly as reconstructed. Public-role policies are retained as Live Truth unless a separate hardening change is approved.

### 11. Trigger Functions
Ensure every trigger function and every function it invokes exists before trigger creation. Trigger functions remain part of the function dependency graph even when their execution occurs only after DML.

### 12. Triggers
Create the 16 proven public non-internal triggers after base tables, referenced functions, constraints, and required security objects exist. Preserve trigger timing/event/order semantics from the live definitions.

### 13. Grants
Apply the proven role grants last, after tables, functions, RLS, and triggers exist. Preserve Live Truth rather than silently minimizing privileges. In particular, the current direct authenticated writes on inventory/customer/product surfaces are retained for baseline fidelity and separately classified as hardening candidates where appropriate.

### 14. Post-build integrity checks
Run deterministic checks for:
- object counts
- table/column/type/default identity parity
- PK/UNIQUE/CHECK/FK parity
- index parity
- function signature/body parity
- RLS enablement/policy parity
- trigger parity
- grant parity
- zero forbidden legacy architectural objects/references
- canonical tenant authority
- composite tenant guard coverage
- critical RPC existence and EXECUTE grants

### 15. Empty DB Replay Gate
Only after the generated baseline is committed may the clean empty-database replay be executed. A replay PASS must be tied to the exact baseline SHA and run/artifact evidence.

## Circular-dependency rule
No dependency is resolved by weakening a live contract. If a cycle exists, split object creation from cross-object constraints/policies/triggers, create the minimum legal predecessor objects, then add the deferred edge after its prerequisites exist.

## Forbidden reconstruction shortcuts
- Do not rewrite legacy `0001`/`0002` and assume the chain becomes canonical.
- Do not revive `organizations`.
- Do not revive `operational_invoices`.
- Do not invent missing migration history.
- Do not declare a baseline executable merely because documentation is complete.
- Do not mutate Main or Production as part of reconstruction.

## Gate
This document establishes the canonical ordering. It does **not** declare the Executable Baseline complete. The next artifact is the generated SQL assembled from the individually reconstructed live definitions, followed by deterministic empty-database replay.
