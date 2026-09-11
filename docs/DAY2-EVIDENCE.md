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

- Admin product lifecycle exposes real DB-backed product records with edit, activate/deactivate, search, status filter, pagination, category selection, and tier pricing through existing server-authoritative RPCs.
- Admin order operations expose search/filter/pagination while retaining server-authoritative state transitions.
- Corrected an AdminPanel product query from obsolete `is_active` to the current schema field `status`.
- Inventory service contracts reject fractional, unsafe, negative, or oversized quantities before RPC execution; inventory threshold and transfer validation remain server-authoritative after client validation.
- Purchasing remains wired to real supplier, purchase-order, approval, and receiving RPCs; no mock persistence was introduced.
- Existing order concurrency hardening remains present through deterministic locking and idempotency at the database command layer.

## 2026-09-11 — Finance + adversarial contract execution

- Added finance service-level adversarial coverage for payment, cash-account, and expense input contracts.
- Added cross-domain adversarial coverage for inventory transfer/threshold validation, purchase-order/receiving batches, and malformed staff-order responses.
- The new tests explicitly exercise malformed UUIDs, zero/negative/non-finite amounts, unsupported payment methods/currencies, duplicate lines, fractional quantities, invalid threshold relationships, short idempotency keys, and malformed order response shapes.
- Finance operations remain backed by the existing server RPCs (`create_cash_account`, `create_invoice_from_order`, `record_payment`, `record_expense`); no client-only financial mutation was introduced.
- The live Supabase schema currently contains the operational finance tables (`operational_invoices`, `operational_invoice_items`, `payments`, `cash_transactions`, `expenses`, `customer_credit_accounts`, `customer_ledger_entries`) with RLS enabled.

### Exact implementation lineage
- Starting DAY 2 reference supplied by owner: `d1cf83a170a08b65a1f83c7e9fea62e7782bc01b`.
- Current executable branch: `day2/complete-product`.
- Current branch head after this round: `44ccc7f83aa76bb5a6683496f07f22e80d989ca8`.
- Finance adversarial tests: `8cfc388335ece4bb45cf6b7ba3db26bb0fa25ea1`.
- Evidence update: current file commit follows the finance/adversarial implementation.

### Verification status
- The GitHub status observed on the prior exact SHA contained only Vercel deployment rate-limit failures; these are external provider statuses and are not treated as application build/test failures.
- No automated PASS is claimed for the new test commit until an actual runner reports success on that exact SHA.
- Supabase security advisor currently reports 47 authenticated-callable `SECURITY DEFINER` functions and one leaked-password-protection warning. These are recorded as security evidence/blockers, not silently converted to PASS.
- Production was not modified or promoted by this DAY 2 work.

## Next execution front
Finance mutation consistency → cancellation/refund capability audit against the actual DB contract → concurrency/idempotency adversarial proof → Clean Replay/Test 021 → authenticated browser E2E across Chrome/Edge/Firefox/mobile → regression/gap rescan → final evidence pack and certification gates.
