# Canonical Baseline Object Inventory — 2026-09-10

Status: RECONSTRUCTION / EVIDENCE ONLY
Branch: `reconstruction/canonical-lineage`
Production/Main: untouched

## Live public schema object counts

Read-only inspection of Supabase project `fnqbvfuwbdpwvhcgzksl` established:

- Public tables: **100**
- Public views/materialized views: **0**
- Public sequences: **1** (`orders_order_number_seq`)
- Public functions: **98**
- Public non-internal triggers: **16**
- Public RLS policies: **179**
- Public indexes: **340**
- Non-`plpgsql` extensions: **4**

These counts are baseline extraction targets. They are not a substitute for executable SQL.

## Tenant lineage evidence

The live database has no `organizations` tenant relation in the inspected public object surface. The canonical tenant root is `companies`, with `company_memberships` and `current_company_id()` providing runtime tenant authority.

Two remaining columns retain the historical identifier `organization_id`:

- `profiles.organization_id uuid` → FK to `companies(id)`
- `client_ui_settings.organization_id uuid` → FK to `companies(id)`

These are therefore classified as **Legacy Terminology Remnants**, not evidence that the legacy `organizations` architecture is still live.

## Core canonical dependency evidence

Observed live FK relationships establish the following dependency spine:

`companies`
→ `company_memberships`, `branches`, `warehouses`
→ `customers`, `categories`, `products`
→ `inventory_balances`, `inventory_movements`
→ `carts`, `orders`, `order_items`, `order_status_history`, `order_outbox_events`
→ `sales_invoices`, `payments`, `cash_accounts`

The same `companies` tenant key also anchors the intelligence, import, report, governance, certification, and evidence domains.

## Reconstruction rule

The object inventory is a forensic target list only. A Foundation Commit may be declared only when executable definitions for the required baseline surface have been reconstructed and can be replayed against an empty database.

Do not:

- rewrite only legacy migrations `0001`/`0002`;
- revive `organizations`;
- revive `operational_invoices`;
- introduce a compatibility bridge merely to make old migrations execute;
- declare migration parity from metadata inspection alone.

## Next gate

Reconstruct the executable canonical baseline in dependency order, then prove:

`Canonical Baseline SQL → clean empty DB → current incremental migrations → replay success`

Only after that proof may Empty DB Replay #2 be launched as a certification gate.
