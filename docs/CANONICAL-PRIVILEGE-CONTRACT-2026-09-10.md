# Canonical Privilege Contract — 2026-09-10

Status: RECONSTRUCTION / EVIDENCE ONLY

## Live grant evidence
For the high-risk business tables, live `authenticated` privileges are:

| Table | authenticated privileges | Contract interpretation |
|---|---|---|
| orders | SELECT | Read path; mutation via RPC |
| order_items | SELECT | Read path; mutation via RPC |
| sales_invoices | SELECT, REFERENCES, TRIGGER | No direct INSERT/UPDATE/DELETE observed |
| payments | SELECT, REFERENCES, TRIGGER | No direct INSERT/UPDATE/DELETE observed |
| cash_accounts | SELECT | Mutation via controlled finance RPC |
| inventory_balances | SELECT, INSERT, UPDATE, DELETE, REFERENCES, TRIGGER | Broad live surface; high-priority hardening candidate |
| inventory_movements | SELECT, INSERT, UPDATE, DELETE, REFERENCES, TRIGGER | Broad live surface; high-priority hardening candidate |
| customers | SELECT, INSERT, UPDATE, DELETE, REFERENCES, TRIGGER | Admin/import/customer flows require consumer tracing |
| products | SELECT, INSERT, UPDATE, DELETE, REFERENCES, TRIGGER | Admin/import flows require consumer tracing |

All nine tables above have RLS enabled in the live database.

## RPC execution evidence
The following business RPCs have `EXECUTE` for `authenticated` in the live database:
- `create_order`
- `transition_order`
- `create_invoice_from_order`
- `record_payment`
- `record_sales_payment`
- `accept_customer_invitation`
- `create_customer_invitation`

## Canonical decision
1. `orders`, `order_items`, `sales_invoices`, `payments`, and `cash_accounts` do not show authenticated direct business writes in the inspected grant surface; their mutation contract is RPC-centered.
2. `inventory_balances` and `inventory_movements` retain broad authenticated direct-write grants in Live Truth. They are **not** silently revoked during baseline reconstruction. They are high-priority post-baseline hardening candidates because authoritative stock mutation is implemented through transactional order RPCs.
3. `customers` and `products` retain observed Live Truth until frontend/import consumer tracing proves which direct writes are intentional. Their privileges must not be narrowed merely from architectural preference.
4. RLS is part of the security contract; RLS enabled does not by itself prove that a privilege is minimal, and a grant alone does not prove a cross-tenant vulnerability.

## Important correction
The earlier generic statement that the high-risk tables all had broad authenticated write grants is too broad. The live grant query shows that direct writes are concentrated in inventory, customer, and product tables; orders/order_items/invoices/payments are read-oriented for `authenticated`.

## Baseline rule
Reconstruct observed Live Truth first. Privilege minimization is a separate hardening phase unless a dependency or verified security defect requires otherwise.

## Gate
Privilege Contract: **CLOSED FOR BASELINE RECONSTRUCTION**, with explicit hardening candidates recorded. This closes the contract-review gate without declaring production security certification.

Next: assemble and review the canonical object creation sequence, then generate the executable baseline only from verified live definitions.
