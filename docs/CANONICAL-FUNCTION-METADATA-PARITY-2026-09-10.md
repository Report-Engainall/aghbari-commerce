# Canonical Function Metadata Parity — 2026-09-10

Branch: `reconstruction/canonical-lineage`
Source: live canonical Supabase project `fnqbvfuwbdpwvhcgzksl`

## Catalog truth

Direct PostgreSQL catalog verification:

- public ordinary functions: **98**
- SECURITY DEFINER: **53**
- SECURITY INVOKER: **45**
- distinct `md5(pg_get_functiondef(oid))`: **98**
- therefore: no two live public functions currently share an identical full function-definition hash.

## Important correction

`current_company_id()` is **SECURITY DEFINER + STABLE** in the live catalog. It must not be modeled as SECURITY INVOKER in the canonical baseline.

`current_customer_id()` and `current_customer_company_id()` are also SECURITY DEFINER + STABLE.

## Extraction contract

For every function, the executable baseline must preserve at minimum:

- exact identity argument signature
- exact return definition
- SECURITY DEFINER/INVOKER mode
- volatility
- parallel safety
- set-returning flag
- strictness
- default argument count/expressions
- exact `pg_get_functiondef()` body
- owner and EXECUTE ACL contract

## Safety boundary

This verification was read-only. No DDL/DML was executed against the live project. `main` and Production remain untouched.
