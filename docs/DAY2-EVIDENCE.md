# DAY 2 — Evidence Log

## 2026-09-11 — Customer Portal execution

### Implemented
- Database-backed Order Templates: create, list, delete, reload persistence, and apply-to-cart through the server RPC.
- Customer invoice list/details backed by `operational_invoices` and `operational_invoice_items`.
- Customer payment history backed by `get_customer_payments`.
- Customer credit and ledger views backed by `customer_credit_accounts` and `customer_ledger_entries`.
- Customer/company account information from authenticated `profiles`, `customers`, and `organizations` reads.
- Customer order detail view with line items and status history.
- Excel Quick Order: XLSX upload, parsing, header validation, SKU/name matching through the authorized catalog, quantity/duplicate/availability diagnostics, review UI, and atomic `set_cart_items` persistence.
- Added cart batch service wrapper around the existing server-authoritative `set_cart_items` RPC.

### Security / persistence verification performed
- Confirmed the live database contains the required portal/order/finance tables.
- Confirmed customer RLS exists for `order_templates`, `operational_invoices`, `operational_invoice_items`, `payments`, `customer_credit_accounts`, `customer_ledger_entries`, `orders`, `order_items`, and `order_status_history`.
- Confirmed customer order history and invoice/item policies are scoped to the authenticated organization/customer context.
- Confirmed `set_cart_items` is server-authoritative, validates 1–200 items, validates quantities, rejects duplicate products, requires the authenticated customer context, and checks active products in the caller organization.
- Confirmed `get_catalog` scopes products to the authenticated organization/customer and supports SKU/barcode/name search.

### Verification status
- Source implementation committed on branch `day2/complete-product`.
- Automated TypeScript/test/lint/build evidence is **NOT claimed here** until an actual runner completes it.
- Vercel deployment evidence is **NOT claimed**; the provider status currently reports deployment rate limiting.
- Production was not modified by these DAY 2 commits.

## 2026-09-11 — Dashboard/detail follow-through

- Added a customer dashboard summary driven by the authenticated `getCustomerOrders(20)` read model; it does not use placeholder order data.
- Added authenticated order detail retrieval from `orders`, `order_items`, and `order_status_history`; access remains subject to the existing customer/organization RLS policies.
- Added input-contract tests for cart batch updates and order-detail identifiers.

## 2026-09-11 — Admin customer-flow follow-through

- Added real customer editing through the existing server RPC `update_customer`; no client-only mutation is used.
- Added customer search across name/phone/email, active/inactive filtering, and deterministic pagination.
- Added service-level tests covering valid normalization, blank-name rejection, oversized-phone rejection, and invalid-tier rejection.

## 2026-09-11 — Admin catalog / inventory / purchasing hardening

- Admin product lifecycle now exposes real DB-backed product records with edit, activate/deactivate, search, status filter, pagination, category selection, and tier pricing through existing server-authoritative RPCs.
- Admin order operations now expose search/filter/pagination while retaining server-authoritative state transitions.
- Corrected an AdminPanel product query from obsolete `is_active` to the current schema field `status`.
- Inventory service contracts now reject fractional, unsafe, negative, or oversized quantities before RPC execution; inventory threshold and transfer validation remain server-authoritative after client validation.
- Added adversarial unit coverage for inventory transfer/threshold inputs and purchasing order/receiving inputs.
- Purchasing remains wired to real supplier, purchase-order, approval, and receiving RPCs; no mock persistence was introduced.
- Existing order concurrency hardening remains present through deterministic locking and idempotency at the database command layer.

### Exact implementation lineage
- Prior DAY 2 implementation head: `1526ecca26450c2a08a09e13095cc19759c12bd2`.
- Inventory hardening commit: `f68707a8f3e2931bdee1faf77783872149b631a8`.
- Inventory adversarial tests commit: `40dfeaf9348652d456dd8c552b7d5f74381a21a0`.
- Purchasing adversarial tests commit: `ea4a3a7a89941720472a00fd49839c6b7eac7f21`.
- Latest evidence-log update follows those implementation commits.

### Verification status
- CI is monitored by exact SHA; no PASS is claimed until the runner completes successfully for the exact target SHA.
- No Production modification or promotion was performed.
- Vercel capacity/rate limiting remains an external deployment blocker and is not treated as a code/build PASS.

## Next execution front
Admin finance/inventory/purchasing edge-flow audit → refund/cancellation/payment consistency → adversarial authorization and concurrency proof → Clean Replay/Test 021 → authenticated browser E2E across Chrome/Edge/Firefox/mobile → regression/gap rescan → final evidence pack.
