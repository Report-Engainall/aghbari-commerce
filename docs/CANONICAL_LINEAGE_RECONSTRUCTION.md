# Canonical Migration Lineage Reconstruction

Status: ACTIVE — reconstruction branch only

## Release safety

- Production database is evidence-only. No production DDL/DML is performed by this reconstruction.
- SHA `7522a206583d582d06da30f7c1dabf1c90a6df7d` remains rejected for clean migration replay.
- This branch is not a release candidate until clean replay, CI, authenticated E2E, and production runtime evidence pass.

## Confirmed divergence

The repository migration chain begins with `0001_operational_core.sql`, which creates an organization-based model (`organizations`, `organization_id`). The same file creates the early branches/customers/products/orders around that model.

The live Supabase project uses a company-based canonical model (`companies`, `company_memberships`, `company_id`) and `current_company_id()` as tenant authority. The live schema contains `sales_invoices`, `payments`, `cash_accounts`, and the current B2B operational tables using company boundaries.

`0013_finance_b2b_pipeline.sql` assumes `public.sales_invoices` already exists and uses the company-based model. A clean replay therefore fails before later migrations can run.

## Canonical dependency DAG

1. PostgreSQL extensions/types
2. Core company/branch/warehouse foundations
3. Auth profile and company membership / tenant authority
4. Catalog and customer domain
5. Cart and B2B order domain
6. Inventory balances and movements
7. Sales and invoice domain (`sales_invoices` is the current finance truth)
8. Payments and cash accounts
9. Import/file-intelligence domain
10. RLS, grants, tenant relational guards
11. Server-authoritative RPCs and lifecycle workflows
12. Realtime/outbox/event surfaces
13. Regression and certification evidence

## Rules

- Do not resurrect `operational_invoices` as the finance source of truth.
- Do not add organization-to-company compatibility hacks merely to make old migrations execute.
- Do not create `sales_invoices` ad hoc immediately before `0013`; its full canonical dependencies must be established first.
- Preserve the business behavior already proven in the live environment while reconstructing a replayable Git lineage.
- Every repaired capability must satisfy Requirement → Implementation → Persistence/Schema → Execution → Workflow/Entry Point → Runtime → Evidence → Production.

## Current evidence anchors

- Rejected candidate: `7522a206583d582d06da30f7c1dabf1c90a6df7d`
- TypeScript fix on rejected candidate: PASS
- Clean migration replay on rejected candidate: FAIL at `0013_finance_b2b_pipeline.sql` because `public.sales_invoices` does not exist in the replayed schema.
- Live tenant authority: `current_company_id()` reads active default `company_memberships` for `auth.uid()`.
- Live finance truth: `sales_invoices` + `payments` + `cash_accounts`.

## Next gates

### Gate A — Foundation extraction

Reconstruct the earliest canonical company-based schema and its exact dependency order from live evidence plus repository artifacts.

### Gate B — Replayable lineage

Refactor/replace the obsolete migration chain on the reconstruction branch so a fresh database can build the canonical schema without relying on an already-existing live database.

### Gate C — Clean replay

Run the repository migration proof from an empty database. No PASS is accepted from partial execution.

### Gate D — Security/performance hardening

Resolve or explicitly classify remaining advisor findings, with special attention to tenant boundaries, SECURITY DEFINER authorization, password protection, RLS init-plan performance, and required foreign-key indexes.

### Gate E — Runtime certification

Only after the database replay and CI gates pass: authenticated customer/staff E2E, tenant isolation, order/inventory lifecycle, finance lifecycle, realtime behavior, rollback, and production runtime evidence.
