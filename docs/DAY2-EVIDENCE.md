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

## 2026-09-11 — Admin / operations follow-through

- Added real customer editing through `update_customer`, customer search, active/inactive filtering, and deterministic pagination.
- Admin catalog exposes real product/category/price operations through server-authoritative RPCs.
- Admin order operations retain server-authoritative workflow transitions with search/filter/pagination.
- Corrected the AdminPanel product query from obsolete `is_active` to the current `status` field.
- Inventory and purchasing input contracts reject unsafe quantities, malformed identifiers, duplicate lines, invalid thresholds, and invalid idempotency inputs before RPC execution.
- Existing database concurrency hardening remains in force for order creation and stock locking.

## 2026-09-11 — Finance + schema alignment

- Finance service-level adversarial coverage exists for payment, cash-account, and expense inputs.
- Finance operations use the operational finance RPCs: `create_cash_account`, `create_invoice_from_order`, `record_payment`, and `record_expense`.
- Corrected `getInvoices()` to read `operational_invoices` rather than the obsolete `sales_invoices` surface.
- `paid_amount` is now derived from RLS-protected `payments` rows, while the authoritative payment command still enforces invoice-balance and currency consistency on the server.
- No client-only financial mutation or mock persistence was introduced.

## 2026-09-11 — Adversarial / compiler closure

- Prior exact-SHA Quality runner failed at TypeScript before unit tests. Root cause was captured from the actual runner: a `getOrderTemplates` resolution failure in `CustomerCommerceHub.tsx` and an implicit-`any` invoice mapper parameter in `customerPortal.ts`.
- The customer portal mapper was hardened with an explicit `CustomerInvoiceRow` boundary so strict TypeScript does not depend on generated Supabase inference.
- The customer template E2E now explicitly covers create → DB persistence → reload → template remains → apply to real cart.
- Browser certification configuration was expanded from Chromium-only to Chrome, Edge, Firefox, and mobile Chrome (`Pixel 5`).
- Runtime E2E workflow now installs all required browsers and executes the complete Playwright project matrix.

### Exact implementation lineage
- Owner-supplied DAY 2 reference: `d1cf83a170a08b65a1f83c7e9fea62e7782bc01b`.
- Executable branch: `day2/complete-product`.
- Finance schema alignment: `58e27e3d5eeec27fb7b977685d27a2f92cc7a718`.
- Customer portal strict-typing repair: `2a3daa5db60db71381cbc30c2448626eb25d8925`.
- Browser matrix hardening: `eb2d08070e568a2d74cf4834824214ecc41021f6` and `4316b608d2a85b8c06590ecad9b2f8be047fed18`.
- Authenticated order-template E2E coverage: `7281a66e800c3100c34c91662755d7dd477b9fa6`.
- Current evidence-log update follows the latest implementation commits.

### Verification status
- Exact SHA checkout and HEAD verification passed on the earlier `58e27e3...` Quality run, proving the runner tested the intended SHA; TypeScript then failed before later gates. That failure is not being hidden or converted to PASS.
- A subsequent workflow run for `2a3daa5...` was observed in progress at the time of inspection; no PASS is claimed until its completed result is retrieved.
- Order Workflow Proof previously completed successfully on its exact tested SHA.
- Security audit previously completed successfully on its exact tested SHA; this is not transferred as certification for newer SHAs.
- Vercel/Production status is not treated as build or runtime evidence until the exact current SHA is deployed and externally verified.
- Production and `main` were not modified or promoted by these DAY 2 commits.

## Remaining execution gates
- Retrieve completed CI results for the newest exact SHA and repair any newly exposed root causes.
- Clean Replay + Test 021 on the final candidate SHA.
- Security adversarial runtime proof and concurrency proof.
- Authenticated browser E2E on Chrome, Edge, Firefox, and mobile Chrome against the exact deployed SHA.
- Regression and gap rescan.
- Production SHA lineage and runtime proof.
- Final evidence pack and Final Production Certification only after every required gate is actually proven.
