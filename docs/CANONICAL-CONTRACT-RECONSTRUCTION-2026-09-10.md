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

## Function dependency ordering

Function creation order must account for body-level references that may not be fully represented by `pg_depend`.

Observed dependency chains include:

- `can_enter_phase_l_autonomy()` → `can_certify_autonomous_domain()` → `is_continuous_trust_healthy()` → `is_trust_certificate_valid()`
- `autonomy_runtime_gate()` → `can_enter_phase_l_autonomy()` / `compute_control_plane_health()` / `is_continuous_trust_healthy()`
- `convert_operational_task_proposal()` → `create_decision_work_item()`
- `import_commit_batch_governed()` → `import_commit_batch_with_lineage()` → `import_commit_batch()` → `import_upsert_*()`
- Customer cart/order contracts depend on `current_customer_company_id()` and `current_customer_id()`.

Therefore executable baseline ordering cannot be generated solely from catalog dependency metadata.

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

Only after that gate may Empty DB Replay #2 begin.

`main` and Production remain untouched by this reconstruction work.
