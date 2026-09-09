# Aghbari Reference → Implementation → Evidence Matrix

This matrix is intentionally implementation-facing. A requirement is not considered complete merely because a route/table/function exists; closure requires implementation plus verification evidence.

| Reference capability | Existing implementation anchor | Current evidence state | Closure target |
|---|---|---|---|
| Operational DB as live SSOT | `supabase/migrations/0001_operational_core.sql` + command RPCs | Implemented foundation | Runtime proof across customer/staff flows |
| Unified product import | `src/services/importExcel.ts`, `src/domain/import.ts`, `src/domain/importProfiles.ts` | XLSX path implemented | Generalized profile-driven pipeline + runtime evidence |
| Import limits / DQS | `src/domain/import.ts` | Unit-level implementation | Contract + adversarial coverage |
| Versioned import profiles | `src/domain/importProfiles.ts` + Supabase registry migration | Registry foundation | UI/runtime selection and immutable-history proof |
| Canonical business identities | `canonicalBusinessIdentity`, `normalizeSku` | Implemented | Leading-zero + whitespace + deterministic matching tests |
| Server idempotency | `operation_idempotency` + begin/complete RPCs | DB foundation | Integrate into every sensitive mutation and concurrency proof |
| Evidence-bound intelligence | `intelligence_evidence` | DB foundation | Metric → insight → recommendation provenance runtime |
| Onyx isolated sandbox | `onyx_*` tables | DB foundation | Full upload→analysis workspace + write-boundary proof |
| Inventory reconciliation | reconciliation tables/RPC foundation | DB foundation | Preview/apply/rollback runtime flow |
| Product image pipeline | `src/services/imagePipeline.ts` | Production-oriented client pipeline | Storage lifecycle + dedupe/invalidation proof |
| Admin command center | `src/AdminPanel.tsx` | Integrated operational UI | Expand evidence-backed command surfaces |
| Security / tenant isolation | RLS + SECURITY DEFINER command layer | Partially proven | Adversarial cross-tenant/role/storage tests |
| CI quality gates | `.github/workflows/quality.yml` | Gate exists | Same-HEAD all-green evidence |
| Runtime production proof | Vercel deployment | Environment constrained | Authenticated real-browser proof |

## Non-negotiable evidence chain

`User Action → Runtime → DB/Service → Result → UI → Audit → Test`

## Architectural constraints

1. Do not create duplicate engines when a valid existing implementation can be extended.
2. Operational live data remains authoritative for live commerce.
3. Onyx datasets are analytical sandbox data and must not silently mutate operational commerce data.
4. Imported files must pass the unified pipeline and profile/version contract.
5. AI/decision outputs must be traceable to deterministic source data and transformation evidence.
6. PASS is only valid when the relevant verification layer is actually executed on the candidate HEAD.
