# Canonical Definition-Level Extraction Findings — 2026-09-10

Status: IN PROGRESS — no Foundation Commit authorized
Branch: `reconstruction/canonical-lineage`
Source: live Supabase canonical project `fnqbvfuwbdpwvhcgzksl`

## Verified runtime/schema facts

- Public tables: 100
- Public functions: 98
- Public RLS policies: 179
- Public non-internal triggers: 16
- Public indexes: 340
- Public sequences: 1 (`orders_order_number_seq`)
- Public custom enum/domain types: none observed; composite row types are PostgreSQL-generated table row types and are not standalone CREATE TYPE inputs.
- `orders.order_number`: `GENERATED ALWAYS AS IDENTITY`
- `cash_accounts.current_balance`: stored generated expression `((opening_balance + received) - spent)`
- `customer_credit_accounts.available_credit`: stored generated expression `GREATEST((credit_limit - outstanding_balance), 0)`
- All public base tables currently report ordinary persistent table storage and default replica identity.

## Runtime configuration that must not be omitted

The live database has a `supabase_realtime` publication containing:

- `public.client_ui_settings`
- `public.customer_invitations`
- `public.inventory_balances`
- `public.orders`

The baseline emitter was therefore hardened to capture publication membership and replica identity in addition to DDL objects. These are required for runtime-equivalent replay and cannot be inferred safely from table/index counts alone.

## Emitter hardening

`supabase/tools/emit_canonical_baseline.sql` was updated in commit `081d6dcc1c2146de8ac48612d142394777b7d02b` to add:

1. exact sequence definition metadata;
2. sequence-to-column ownership, including identity dependencies;
3. replica-identity reconstruction;
4. Supabase Realtime publication membership;
5. table ACL extraction from `pg_class`/`aclexplode`, including PUBLIC grants rather than relying only on `information_schema.role_table_grants`;
6. existing exact function EXECUTE grant extraction remains signature-aware.

## Function extraction proof-of-work

Live function definitions are being extracted in deterministic batches using `pg_get_functiondef`, ordered by function name, identity arguments and OID. The first batches confirmed exact production definitions including the B2B command path (`create_order`, `transition_order`, `record_payment`, `create_invoice_from_order`) and the canonical tenant/security functions.

Important live terminology remnants remain exactly two known `organization_id` body references:

- `accept_customer_invitation(p_token text)`
- `current_customer_company_id()`

These are schema terminology remnants in the current canonical company model and are not evidence that the legacy `organizations` model should be restored.

## Security advisor finding — classification, not mutation

Supabase Security Advisor currently reports 38 `SECURITY DEFINER` functions callable by `authenticated`, plus one Auth warning for leaked-password protection being disabled.

This is **not** being auto-remediated during baseline reconstruction. These findings must be classified against the verified RPC consumer/privilege contract first. In particular, intentional authenticated RPC entry points must not be broken merely to silence a linter. Any privilege reduction requires a separate evidence-backed change and regression proof.

## Current gate

Definition-Level Parity remains **IN PROGRESS**.

The executable baseline is not yet declared complete because the connector returns large catalog payloads in bounded responses. Count parity is therefore insufficient evidence that every definition has been captured without truncation or omission.

Foundation Commit and Empty DB Replay #2 remain blocked until:

- all definitions are deterministically extracted;
- the assembled SQL is complete and syntactically executable;
- static legacy/contract scans pass;
- the verifier passes against the assembled baseline;
- clean empty-database replay succeeds and is tied to the Foundation Commit SHA.
