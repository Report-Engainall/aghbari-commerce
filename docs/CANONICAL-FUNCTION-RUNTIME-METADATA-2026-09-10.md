# Canonical Function Runtime Metadata — 2026-09-10

Branch: `reconstruction/canonical-lineage`
Source: live canonical Supabase project `fnqbvfuwbdpwvhcgzksl`

## Exact catalog counts

- Public ordinary functions: **98**
- `SECURITY DEFINER`: **53**
- `SECURITY INVOKER`: **45**
- Set-returning functions: **13**

## Important correction to earlier triage wording

The earlier Security Advisor triage count of **38** refers to the subset surfaced as relevant to the Advisor/authenticated execution review. It must **not** be treated as the total number of `SECURITY DEFINER` functions.

The live PostgreSQL catalog currently proves **53 SECURITY DEFINER functions out of 98 public functions**.

This distinction is material for the executable baseline: all 53 function definitions, security mode, volatility, parallel-safety, strictness, return shape, default-argument count, exact identity arguments, ownership and grants must be serialized and restored. The 38-function Advisor subset remains a security-review classification, not an inventory count.

## Critical RPC examples confirmed live

The live catalog includes the B2B mutation boundary functions:

- `create_order(text,uuid,jsonb)` — SECURITY DEFINER
- `transition_order(uuid,text)` — SECURITY DEFINER
- `create_invoice_from_order(uuid)` — SECURITY DEFINER
- `record_payment(uuid,numeric,text,uuid,text)` — SECURITY DEFINER
- `record_sales_payment(uuid,numeric,text,text,date)` — SECURITY DEFINER
- `create_customer_invitation(uuid,text,integer)` — SECURITY DEFINER
- `revoke_customer_invitation(uuid)` — SECURITY DEFINER
- `accept_customer_invitation(text)` — SECURITY DEFINER
- `get_cart()` / `set_cart_item(uuid,integer)` / `remove_cart_item(uuid)` / `clear_cart()` — SECURITY DEFINER

The live catalog also confirms the broader intelligence, import, report-execution, governance and certification function surface.

## Baseline rule

No function is to be reconstructed from its name or inferred behavior. The executable baseline must use exact `pg_get_functiondef()` output plus the catalog metadata required to preserve execution semantics and privileges.

## Safety boundary

This proof used read-only catalog queries only. No live DDL/DML was executed. `main` and Production remain untouched.
