#!/usr/bin/env bash
set -euo pipefail

# Read-only export from the LIVE canonical PostgreSQL catalog.
# Required: DATABASE_URL (or SUPABASE_DB_URL) with schema-read access.
# Never point this at a mutable target. The source is read-only; output is a local artifact.

DB_URL="${DATABASE_URL:-${SUPABASE_DB_URL:-}}"
if [[ -z "$DB_URL" ]]; then
  echo "ERROR: set DATABASE_URL or SUPABASE_DB_URL" >&2
  exit 2
fi

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
OUT="${1:-$ROOT/supabase/canonical_baseline.sql}"
EMITTER="$ROOT/supabase/tools/emit_canonical_baseline.sql"
RUNTIME="$ROOT/supabase/tools/emit_canonical_runtime.sql"
TMP="$(mktemp)"
RUNTIME_TMP="$(mktemp)"
trap 'rm -f "$TMP" "$RUNTIME_TMP"' EXIT

# PostgreSQL emits dependency-aware DDL for the complete public schema:
# tables, columns/defaults/generated/identity, types, constraints, indexes,
# functions, triggers and RLS policies. No owner/privilege statements are emitted here.
pg_dump "$DB_URL" \
  --schema-only \
  --schema=public \
  --no-owner \
  --no-privileges \
  --file="$TMP"

# Supabase runtime metadata not guaranteed by pg_dump is emitted separately:
# Realtime publication membership, RLS enablement, and explicit ACL grants.
psql "$DB_URL" -v ON_ERROR_STOP=1 -f "$RUNTIME" > "$RUNTIME_TMP"

{
  printf '%s\n' '-- CANONICAL BASELINE: canonical live PostgreSQL public schema';
  printf '%s\n' '-- Generated from a read-only source connection; no source DDL is executed.';
  cat "$TMP";
  printf '%s\n' '' '-- CANONICAL SUPABASE RUNTIME OVERLAY';
  cat "$RUNTIME_TMP";
  printf '%s\n' '' '-- END CANONICAL BASELINE';
} > "$OUT"

printf 'Canonical baseline written to: %s\n' "$OUT"
printf 'Source parity emitter remains available at: %s\n' "$EMITTER"
