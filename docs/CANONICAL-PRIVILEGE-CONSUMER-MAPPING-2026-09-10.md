# Canonical Privilege Consumer Mapping — 2026-09-10

Status: RECONSTRUCTION / EVIDENCE ONLY

## Scope
High-risk business tables were checked against live public RPC bodies and live RLS enablement before baseline assembly.

## Evidence
- `customers`, `products`, `orders`, `order_items`, `inventory_balances`, `inventory_movements`, `sales_invoices`, and `payments` all have RLS enabled in the live database.
- Live RPC body references establish the principal controlled mutation routes:
  - `create_order` → `orders`, `order_items`, `inventory_balances`, `inventory_movements`.
  - `transition_order` → `orders`, `order_items`, `inventory_balances`, `inventory_movements`, and completion/invoice path.
  - `create_invoice_from_order` → `sales_invoices`.
  - `record_payment` → `payments`, `sales_invoices`, `cash_accounts`.
  - `record_sales_payment` → `payments`, `sales_invoices`.
  - `accept_customer_invitation` / invitation RPCs → `customers` and customer identity/profile path.
- Direct authenticated write grants remain present on a broad set of tables. Their presence is preserved as Live Truth until consumer-level proof establishes whether each write is intentional.

## Security interpretation
RLS-enabled does not by itself prove that broad direct-write privileges are canonical. Conversely, a direct-write grant is not by itself a cross-tenant vulnerability. The baseline must reproduce the live security contract first; privilege hardening is a separate controlled migration unless evidence proves the live contract is defective and the change is required for reconstruction.

## High-risk classification
1. `inventory_balances`: mutation has financial/stock side effects; canonical business mutation is RPC-controlled.
2. `inventory_movements`: authoritative stock ledger; direct writes require explicit consumer proof.
3. `orders` / `order_items`: order creation and lifecycle are RPC-controlled and transactional.
4. `sales_invoices`: invoice lifecycle is RPC-controlled; one-order/one-invoice contract applies.
5. `payments`: financial mutation is RPC-controlled; `record_payment` is canonical candidate, `record_sales_payment` remains legacy-compatible/overlapping pending consumer tracing.
6. `customers` / `products`: direct access must remain governed by RLS and any intended import/admin flows.

## Baseline rule
Do not silently revoke live grants during baseline reconstruction. Preserve observed grants, explicitly document them, and defer privilege minimization to a post-baseline hardening migration unless an executable dependency requires a narrower contract.

## Next gate
Frontend consumer tracing + RPC grant matrix → final privilege contract → canonical object creation order → executable baseline assembly.
