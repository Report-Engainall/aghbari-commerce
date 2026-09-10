# High-Risk Grant Canonical Decisions — 2026-09-10

## Scope

This document records the live-production read-only verification used to resolve the high-risk grant matrix before executable Canonical Baseline assembly. No production DDL was executed.

## End-to-end consumer proof

Financial frontend path:

`FinancePanel.tsx → services/finance.ts → record_payment() → sales_invoices / payments / cash_accounts`

Order path:

`Order UI → services/orders.ts → create_order() / transition_order() → orders / order_items / inventory_balances / inventory_movements`

The repository service layer directly calls the authoritative RPC boundary for order creation and transitions. Finance payment recording likewise calls `record_payment()`. `sales_invoices` is the invoice source used by the finance service; `operational_invoices` is not part of this path.

## Legacy extinction result

The live executable reference scan found:

- `organizations`: 0 function-body references, 0 trigger-definition references, 0 policy references.
- `current_organization_id`: 0 function-body references, 0 trigger-definition references, 0 policy references.
- `operational_invoices`: 0 function-body references, 0 trigger-definition references, 0 policy references.

The only remaining live `organization_id` references are the previously classified terminology remnants in `accept_customer_invitation()` and `current_customer_company_id()`. They are not evidence of a live `organizations` relation.

Therefore `organizations` and `operational_invoices` are excluded from the reconstructed Canonical Baseline.

## Verified authenticated grants on high-risk tables

| Table | Authenticated direct privileges verified | Canonical decision |
|---|---|---|
| `inventory_balances` | SELECT, INSERT, UPDATE, DELETE | Preserve live truth; hardening candidate. Authoritative business mutation remains RPC-controlled in the current application path; direct-write privilege must not be silently removed during baseline reconstruction. |
| `inventory_movements` | SELECT, INSERT, UPDATE, DELETE | Preserve live truth; hardening candidate. Movement creation is part of authoritative order lifecycle RPCs. |
| `orders` | SELECT only | RPC-centered strict contract for writes. |
| `order_items` | SELECT only | RPC-centered strict contract for writes. |
| `sales_invoices` | SELECT only | RPC-centered strict contract for writes. |
| `payments` | SELECT, INSERT, UPDATE, DELETE | Preserve live grant in baseline; hardening candidate because current frontend payment creation is RPC-centered. Do not revoke during reconstruction without a separate tested hardening migration. |
| `customers` | SELECT, INSERT, UPDATE, DELETE | Preserve live direct CRUD path. RLS and role predicates remain part of the security contract. |
| `products` | SELECT, INSERT, UPDATE, DELETE | Preserve live direct CRUD path. RLS and role predicates remain part of the security contract. |

## RLS verification

The inspected high-risk tables have RLS policies enforcing company/customer scope. In particular:

- `inventory_balances` and `inventory_movements` use `company_id = current_company_id()` for tenant isolation.
- `orders` customer policies bind rows to `current_customer_id()` and `current_customer_company_id()`.
- `order_items` customer reads require the related order to belong to the current customer and company.
- `sales_invoices` and `payments` use company-scoped policies.
- `customers` and `products` combine company scope with membership-role checks for direct mutation.

Thus direct grants and RLS are separate contracts: a grant does not by itself prove cross-tenant access. The live baseline must preserve both until hardening is separately verified.

## RPC execution boundary

The following authoritative RPCs were verified as `SECURITY DEFINER` and executable by `authenticated`:

- `create_order(p_idempotency_key, p_warehouse_id, p_lines)`
- `transition_order(p_order_id, p_to_status)`
- `create_invoice_from_order(p_order_id)`
- `record_payment(p_invoice_id, p_amount, p_method, p_cash_account_id, p_reference)`
- `create_cash_account(p_branch_id, p_name, p_currency, p_opening_balance)`
- `get_cash_account_balances()`
- `record_sales_payment(...)` also exists and is retained as an overlapping/legacy-compatible contract pending complete consumer tracing.

`record_expense` was not included in this specific function-privilege result and must be resolved separately before it is treated as a canonical executable component.

## Important correction to earlier matrix

The live grant query proves that `payments` has direct authenticated INSERT/UPDATE/DELETE privileges. Therefore any earlier matrix marking `payments` as having no direct write grant is corrected here. The correct baseline decision is **preserve live truth + hardening candidate**, not revoke during reconstruction.

Likewise `inventory_balances` and `inventory_movements` have all four direct authenticated privileges, not merely SELECT/UPDATE.

## Gate decision

**Consumer-to-Grant Review: CLOSED for the high-risk set listed above.**

This closure does **not** mean the grants are ideal security posture. It means the reconstruction has enough evidence to preserve the exact live contract without accidentally deleting capabilities. Security hardening is a separate post-baseline change set.

## Next gate

Proceed to deterministic executable Canonical Baseline assembly:

1. exact table columns/defaults/identity/generated expressions;
2. PK/unique/check/FK constraints;
3. indexes;
4. RLS enablement and all policies;
5. functions and function definitions;
6. trigger functions and triggers;
7. grants;
8. extensions/sequences;
9. static legacy-token scan;
10. object-count and definition-parity verification;
11. only then Foundation Commit and Empty DB Replay #2.

`main` and Production remain untouched.