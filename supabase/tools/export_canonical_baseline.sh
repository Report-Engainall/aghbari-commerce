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
TMP="$(mktemp)"
trap 'rm -f "$TMP"' EXIT

# pg_dump is preferred because PostgreSQL itself emits dependency-aware DDL.
# The catalog emitter is retained as the parity/audit companion and catches
# Supabase-specific publication/RLS/ACL/runtime metadata.
pg_dump "$DB_URL" \
  --schema-only \
  --schema=public \
  --no-owner \
  --no-privileges \
  --file="$TMP"

{
  printf '%s\n' '-- CANONICAL BASELINE: pg_dump public schema, no owner/no privileges';
  printf '%s\n' '-- Source is the canonical live database; generated locally from a read-only connection.';
  cat "$TMP";
  printf '%s\n' '' '-- END PG_DUMP CORE';
} > "$OUT"

printf 'Canonical baseline written to: %s\n' "$OUT"
printf 'Run the committed emitter separately for Supabase-specific parity metadata:\n'
printf '  psql "$DB_URL" -v ON_ERROR_STOP=1 -f "%s" > "%s.emitter.sql"\n' "$EMITTER" "$OUT"
