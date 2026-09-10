# Canonical Live Source Truth — 2026-09-10

## Source

Supabase project `aghbari-commerce` (`mrcyqezbhpncuvaehwgf`), read through the connected PostgreSQL catalog.

## Observed public-schema inventory

| Object | Live count |
|---|---:|
| Tables | 50 |
| Functions | 48 |
| Indexes | 211 |
| RLS policies | 55 |
| Non-internal triggers | 1 |

## Critical discrepancy

The live source currently does **not** match the previously asserted canonical inventory of 100 tables / 98 functions / 179 policies / 16 triggers / 340 indexes.

The live source also currently contains the legacy tables:

- `public.organizations`
- `public.operational_invoices`

and contains `public.current_organization_id()`.

Several live RPC bodies also reference `operational_invoices` and `current_organization_id`.

## Engineering decision

This branch must not manufacture a 100/98/179/16/340 executable baseline from the smaller live source, and it must not rewrite or delete the live legacy objects merely to make a parity gate green.

The canonical baseline remains **NOT CERTIFIED** until the intended canonical source is unambiguously identified and its complete catalog is materialized. Main and Production remain untouched.

## Evidence rule

Any future Foundation Commit must be based on actual catalog extraction and a clean replay. Count-only claims are insufficient; function bodies, constraints, generated/identity metadata, indexes, policies, triggers, publication membership and ACLs must be materialized and replay-verified.
