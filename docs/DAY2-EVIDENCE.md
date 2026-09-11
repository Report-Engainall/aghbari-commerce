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

### Verification status
- The branch remains unmerged and Production remains untouched.
- The Vercel provider status for the branch commits remains a deployment-rate-limit failure; this is not treated as an application build result.
- No automated PASS is asserted until a real TypeScript/test/lint/build runner completes.

## Next execution front
Admin business-flow gap scan → remaining real mutations/exports/search/filter/pagination gaps → adversarial tests → Clean Replay/Test 021 → authenticated browser E2E.
