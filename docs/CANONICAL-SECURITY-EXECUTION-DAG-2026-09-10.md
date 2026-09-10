# Canonical Security & Execution DAG — 2026-09-10

## Status
RECONSTRUCTION / EVIDENCE RECORD ONLY

This document records read-only forensic findings from the live Supabase project `fnqbvfuwbdpwvhcgzksl`. It is not executable SQL and does not authorize changes to `main` or Production.

## Proven live surface
- 100 public tables.
- 98 public functions.
- 16 public non-internal triggers.
- 179 public RLS policies.
- 340 public indexes.
- 1 public sequence.
- 4 non-plpgsql extensions.

## Security layers
The live tenant boundary is implemented as a combined surface:
1. SQL grants to database roles.
2. RLS policies for row isolation.
3. RPC authorization and parameter validation.
4. Composite tenant-aware foreign keys where applicable.
5. SECURITY DEFINER functions with controlled search_path where applicable.

No single layer is treated as sufficient by itself for reconstruction or certification.

## Customer naming remnant
A targeted policy/function scan found the only RLS policy containing `organization` terminology in its expression:
- `client_ui_settings.ui_settings_customer_select`
- command: SELECT
- role: authenticated
- predicate: `organization_id = current_customer_company_id()`

The live `current_customer_company_id()` function reads `profiles.organization_id`. This is classified as a naming/contract remnant because the value is a company UUID and no live function reference to the `organizations` table was found.

`accept_customer_invitation()` also writes the current invitation's `company_id` into `profiles.organization_id`.

These contracts must be represented faithfully in the baseline before any later naming cleanup migration is attempted.

## Function security inventory
The live public routine surface contains both SECURITY DEFINER and SECURITY INVOKER routines. SECURITY DEFINER is used for privileged command paths and protected runtime operations; INVOKER is used for many read/query functions and trigger functions.

The reconstruction must preserve:
- security mode;
- function signature and return type;
- search_path behavior;
- grants/execution privileges;
- tenant/customer/staff authorization checks;
- side effects and trigger interactions.

## Finance contract requiring provenance review
Both `record_payment()` and `record_sales_payment()` exist as SECURITY DEFINER JSON-returning functions. Neither is removed or merged during baseline reconstruction. Their callers, grants, side effects, and semantic differences must be traced before any cleanup migration.

## Privilege surface finding
`authenticated` has direct table privileges on many public tables, including SELECT and, for selected tables, INSERT/UPDATE/DELETE. This is not by itself a vulnerability because effective row access is also constrained by RLS and command paths may be protected by RPC authorization. The baseline must nevertheless preserve the exact GRANT + RLS + RPC combination and replay it as a single security contract.

## Provenance conclusions
- `organizations`: no live public function references found.
- `current_organization_id()`: no live public function references found.
- `operational_invoices`: no live public function references found.
- `organization_id`: two live public function references identified: `accept_customer_invitation()` and `current_customer_company_id()`, plus the customer UI settings policy contract above.

## Reconstruction rule
Do not normalize or rename `organization_id` during Foundation reconstruction. First reproduce Live Truth exactly enough to pass clean replay. Then perform a separately evidenced contract-cleanup migration with runtime and RLS verification.

## Gate
Foundation Commit remains BLOCKED until the complete executable baseline is assembled, including tables/columns, constraints, indexes, RLS, grants, functions, triggers, sequence(s), extensions, and relevant project-owned schemas/objects.

Main and Production remain untouched.
