# Canonical Contract Reconstruction — 2026-09-10

## Status
RECONSTRUCTION / EVIDENCE ONLY

This artifact records live runtime contract findings before any executable baseline is created. It is not a production certification and does not authorize changes to `main` or Production.

## Proven contract facts

- `current_company_id()` is the canonical staff/tenant authority and resolves an active default `company_memberships.company_id` for `auth.uid()`.
- Customer runtime currently resolves company through `current_customer_company_id()`, which reads `profiles.organization_id`. The value is constrained/used as a company UUID; this is a naming remnant, not evidence of a live `organizations` architecture.
- `accept_customer_invitation()` writes `profiles.organization_id = customer_invitations.company_id` and therefore preserves the same semantic company identity.
- `create_order()` is company-scoped, validates customer/warehouse/product ownership, locks inventory, rejects oversell and mixed currencies, persists locked prices, inventory movements, status history, outbox, and audit evidence.
- `transition_order()` is staff-role gated and performs lifecycle transition, cancellation stock restoration, history/outbox/audit, and completion invoice creation.
- `create_invoice_from_order()` and `record_payment()` are company-scoped finance contracts.

## Contract conflict / overlap findings

### Currency default divergence
`get_cart()` falls back to `SAR` when company currency is unavailable, while `create_order()` falls back to `YER` when a customer price tier has no currency. This is a contract inconsistency to be resolved in a later controlled migration/refactor; it must not be silently normalized while reconstructing the baseline.

Canonical target chain:

`Company Currency → Price Authorization → Cart → Order → Invoice → Payment`

### Finance route overlap
`record_payment()` is the stronger canonical finance route: it resolves the current company first, enforces staff finance roles, locks the invoice, validates payment balance/currency, updates cash accounts for cash payments, writes the payment and audit record.

`record_sales_payment()` is an overlapping route with materially different behavior: it resolves the invoice before tenant context is established, performs its own membership check, and does not update `cash_accounts`. It must remain represented in the baseline until consumer/provenance analysis proves it can be deprecated. No merge or deletion by assumption.

## Body-level function dependency extraction

A live catalog query compared every public function body against the names of all other public functions. This produces a conservative body-reference graph and is intentionally broader than `pg_depend`; it can include textual references that are not executable calls, so final ordering still requires contract review.

Observed executable-looking dependency chains include:

- `can_enter_phase_l_autonomy()` → `can_certify_autonomous_domain()` and `compute_control_plane_health()`
- `can_certify_autonomous_domain()` → `is_continuous_trust_healthy()`
- `is_continuous_trust_healthy()` → `is_trust_certificate_valid()`
- `autonomy_runtime_gate()` → `can_enter_phase_l_autonomy()` / `compute_control_plane_health()` / `is_continuous_trust_healthy()`
- `convert_operational_task_proposal()` → `create_decision_work_item()`
- `import_commit_batch_governed()` → `import_commit_batch_with_lineage()` / `import_commit_batch()` / `normalize_import_key()`
- `import_commit_batch_with_lineage()` → `import_commit_batch()`
- `import_commit_batch()` → `import_upsert_customer()` / `import_upsert_product()` / `import_upsert_sales_invoice()`
- `import_upsert_customer()` / `import_upsert_product()` / `import_upsert_sales_invoice()` → `normalize_import_key()`
- Customer cart/order contracts → `current_customer_company_id()` and `current_customer_id()`.
- Most staff/report/finance/runtime functions → `current_company_id()`.

The dependency graph has a large common authority root at `current_company_id()` plus a separate customer authority root at `current_customer_company_id()` / `current_customer_id()`. This means helper functions must be created before their dependents, while mutually recursive or ambiguous textual references must be reviewed rather than blindly topologically sorted.

## RLS contract ordering findings

Live RLS extraction confirms the expected security dependency direction:

`companies / memberships → current_company_id() → tenant RLS policies → domain tables`

Customer-facing policies add a second authority chain:

`profiles → current_customer_id() / current_customer_company_id() → customer RLS policies → carts/orders/credit/pricing/templates`

Several child-table policies deliberately re-check parent tenant ownership through `EXISTS`, including cart items, order items, purchase items, sale items, import rows/job rows, decision work items/action receipts, and alternative-item group members. These parent checks are part of the canonical security contract and must not be simplified away in the baseline.

Two additional observations are recorded for baseline review:

1. `alternative_item_groups` and `alternative_item_group_members` currently have RLS policies addressed to the `public` role rather than only `authenticated`. Their predicates still require `current_company_id()`, so this is not by itself evidence of anonymous tenant access; however, it is an unnecessarily broad privilege/policy surface and must be preserved as Live Truth for replay, then reviewed as a controlled hardening candidate rather than silently changed during reconstruction.
2. `synonym_dictionary` has an authenticated SELECT policy with `USING (true)`. This appears intentionally global rather than tenant-scoped, but it must be explicitly classified as a global reference-data contract before the baseline is frozen.

## Proposed executable creation tiers

1. Extensions, schemas, base types and sequences.
2. Tenant base tables: `companies` and identity/membership foundations.
3. Structural tables and foreign keys that do not depend on runtime functions.
4. Canonical helper functions: tenant/customer authority and pure normalization helpers.
5. Domain RPCs in dependency order: import, commerce, finance, intelligence/governance.
6. Trigger functions and triggers, after their referenced functions/tables exist.
7. RLS enablement and policies, after authority helpers and referenced tables/functions exist.
8. Explicit grants/revokes, after functions/tables/policies exist.
9. Final indexes/constraints that require all referenced relations, followed by verification queries.

This is a construction plan, not yet the executable baseline itself.

## Legacy/remnant classification

- `organizations`: no live public function body references found.
- `current_organization_id()`: no live public function body references found.
- `operational_invoices`: no live public function body references found.
- `organization_id`: two live public function-body references are known: `accept_customer_invitation()` and `current_customer_company_id()`.

These facts do not authorize deletion of the remnant. The baseline must first reproduce Live Truth; a later contract-cleanup migration may rename the remnant after authenticated runtime verification.

## Security contract rule

The executable baseline must preserve the security surface as a single contract composed of:

1. SQL grants/privileges
2. RLS enablement and policies
3. RPC authorization and parameter validation
4. composite tenant foreign-key guards
5. `SECURITY DEFINER` / `search_path` behavior

Reproducing only table definitions or only RLS is insufficient.

## Gate decision

Foundation Commit remains BLOCKED until the complete executable baseline is assembled and reviewed against:

- tables/columns/defaults/identity/generated fields
- constraints and indexes
- extensions/sequences
- RLS enablement and policies
- grants
- functions and body dependencies
- triggers and trigger functions
- storage/project-owned schema where applicable
- explicit review of all contract conflicts/overlaps

Only after that gate may Empty DB Replay #2 begin.

`main` and Production remain untouched by this reconstruction work.
