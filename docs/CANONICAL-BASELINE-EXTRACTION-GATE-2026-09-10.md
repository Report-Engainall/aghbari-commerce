# Canonical Baseline Extraction Gate — 2026-09-10

Status: RECONSTRUCTION GATE — NOT A CERTIFICATION

## Purpose

Establish the evidence boundary for reconstructing a reproducible Empty DB baseline from the live canonical Supabase schema without mutating `main` or Production.

## Confirmed live architecture

- Tenant root: `public.companies`
- Tenant membership: `public.company_memberships`
- Runtime tenant authority: `public.current_company_id()`
- Commerce/finance canonical relations use `company_id`.
- Canonical finance source: `public.sales_invoices`, `public.payments`, `public.cash_accounts`.
- `public.operational_invoices` is not part of the canonical live model.
- `organizations` is not a live public base table.

## Legacy terminology remnants — explicitly NOT legacy tenant authority

The live database currently contains only two public columns whose names retain `organization_id`:

- `public.profiles.organization_id`
- `public.client_ui_settings.organization_id`

Live foreign-key inspection confirms both point to `public.companies(id)`:

- `profiles_organization_id_fkey` → `companies(id)`
- `client_ui_settings_organization_id_fkey` → `companies(id)`

Therefore these are classified as **Legacy Terminology Remnants**, not evidence that `organizations` must be recreated.

They MUST NOT be blindly renamed during baseline reconstruction unless an explicit compatibility/API contract proves the rename is safe.

## Repository divergence

The repository migration directory on `reconstruction/canonical-lineage` begins with the historical `0001_operational_core.sql` / `0002_server_authoritative_commands.sql` lineage. Those files encode the obsolete `organizations` architecture and `current_organization_id()` authority.

The live Supabase migration history instead begins with the timestamped canonical foundation (`20260817182847_01_core_schema`, followed by the canonical file/intelligence and tenant migrations) and contains the subsequent production lineage.

This is the root cause of the clean-replay divergence: the repository's migration lineage is not the same lineage that produced the current canonical live database.

## Extraction rule

A valid baseline must reproduce the canonical live schema from an empty database and preserve:

1. extensions/types required by the schema;
2. tables and columns;
3. primary/unique/check/foreign-key constraints;
4. indexes;
5. functions and triggers;
6. RLS enablement and policies;
7. grants/revocations;
8. storage/realtime-related schema configuration where applicable;
9. canonical tenant authority and security-definer boundaries.

A partial table-only snapshot is NOT accepted as a baseline.

## Current gate

The live schema metadata extraction has been verified for core tenant, commerce, inventory, finance, intelligence, and control-plane objects. A complete executable baseline artifact has NOT yet been committed because the available repository tooling does not provide a verified complete `pg_dump`/`db pull` artifact from the remote project, and manually synthesizing only the visible table metadata would create a false sense of reproducibility.

## Next executable gate

Produce the complete canonical schema artifact using a trusted Supabase schema extraction path, review it for unwanted production data/secrets and noncanonical objects, then replace the obsolete migration lineage on the reconstruction branch with the reviewed baseline plus ordered post-baseline migrations.

Only after that artifact exists:

`Foundation Commit → Empty DB Replay #2 → pgTAP/Security → exact-SHA CI → Auth E2E → Runtime Evidence`

## Protection boundary

- `main`: protected
- Production: protected
- Reconstruction branch: active
- Empty DB Replay #2: NOT started
- Final Production Certification: BLOCKED
