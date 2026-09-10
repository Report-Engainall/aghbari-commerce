# Canonical Consumer and Grant Review — 2026-09-10

## Scope
Read-only review of the live Supabase canonical schema and the reconstruction branch. No production DDL or data mutation was performed.

## Frontend finance consumer proof
`src/FinancePanel.tsx` imports `recordPayment` from `src/services/finance.ts` and invokes it for customer collections. `src/services/finance.ts` calls the canonical RPC `record_payment` and reads invoices from `sales_invoices`.

Therefore the current frontend collection path is:

`FinancePanel → services/finance.ts → RPC record_payment → sales_invoices/payments/cash_accounts`

The service type is still named `OperationalInvoice`, but its implementation reads `sales_invoices`; this is a naming remnant, not evidence that `operational_invoices` is used.

`record_sales_payment` was not found in the reconstruction-branch frontend through the available GitHub code search. This is not treated as proof of global repository absence because connector code search is branch/default-index constrained; live function existence remains a database contract to preserve until broader consumer tracing is complete.

## Frontend order consumer proof
`src/services/orders.ts` uses server-authoritative RPCs only for order mutation:

- `createOrder` → `create_order`
- `transitionOrder` → `transition_order`

No direct client-side inventory mutation is present in this service. The transaction therefore remains owned by the database RPC contract.

## Live legacy-token scan
Exact live executable-body/policy/trigger scan produced:

| Token | Function refs | Trigger refs | Policy refs |
|---|---:|---:|---:|
| `organizations` | 0 | 0 | 0 |
| `organization_id` | 2 | 0 | 1 |
| `operational_invoices` | 0 | 0 | 0 |
| `current_organization_id` | 0 | 0 | 0 |

The two live function references to `organization_id` are the previously identified compatibility/terminology remnants in `accept_customer_invitation()` and `current_customer_company_id()`. The one policy reference is `client_ui_settings.ui_settings_customer_select`, which compares `organization_id` to `current_customer_company_id()`.

No executable reference to the old `organizations` table, `current_organization_id()`, or `operational_invoices` was found in the scanned live functions, triggers, and policies.

## Grant surface finding
The live database grants `authenticated` direct INSERT/UPDATE/DELETE privileges on a broad set of tenant tables, including high-value transactional tables such as `inventory_balances`, `inventory_movements`, `orders`-adjacent data, `customers`, `products`, import tables, and finance-adjacent objects.

This is classified as **Grant Contract Review — OPEN**, not as an immediate vulnerability. RLS and RPC authorization may intentionally constrain these grants, but direct write privileges must be reconciled table-by-table against the server-authoritative command model.

Required matrix before baseline freeze:

`table → authenticated direct write privilege → RLS policy → RPC/server-authoritative writer → frontend direct consumer → canonical decision`

Priority tables:

1. `inventory_balances`
2. `inventory_movements`
3. `orders`
4. `order_items`
5. `sales_invoices`
6. `payments`
7. `customers`
8. `products`
9. `import_jobs`
10. `import_job_rows`
11. `imports`
12. decision/governance/evidence tables with direct writes

## Gate decision
- Legacy organization executable references: **CLEAN except two classified compatibility remnants**.
- `operational_invoices` executable references: **CLEAN**.
- Finance frontend canonical path: **PROVEN for `record_payment` and `sales_invoices`**.
- Order mutation path: **PROVEN server-authoritative**.
- Grant contract: **OPEN — requires deterministic table-by-table reconciliation**.
- Executable canonical baseline: **NOT YET FROZEN**.
- `main`: untouched.
- Production: untouched.
