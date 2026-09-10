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
CANONICAL="$ROOT/supabase/canonical"
TMP="$(mktemp)"
RUNTIME_TMP="$(mktemp)"
trap 'rm -f "$TMP" "$RUNTIME_TMP"' EXIT

mkdir -p "$CANONICAL"

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
if [[ -f "$ROOT/supabase/tools/emit_canonical_runtime.sql" ]]; then
  psql "$DB_URL" -v ON_ERROR_STOP=1 -f "$ROOT/supabase/tools/emit_canonical_runtime.sql" > "$RUNTIME_TMP"
fi

# Split pg_dump into deterministic executable atomic chunks. Each pg_dump object
# remains byte-for-byte intact; only complete object blocks are classified.
python3 - "$TMP" "$CANONICAL" <<'PY'
import pathlib
import re
import sys

src = pathlib.Path(sys.argv[1])
out = pathlib.Path(sys.argv[2])
text = src.read_text(encoding="utf-8")

# pg_dump emits object blocks beginning with a stable '-- Name:' catalog header.
# Preserve preamble in the first chunk. Unknown public-schema object kinds stay in
# chunk 01 so they are not silently discarded.
starts = [m.start() for m in re.finditer(r"(?m)^-- Name: .+?; Type: .+?; Schema: public;", text)]
blocks = []
if starts:
    if starts[0] > 0:
        blocks.append(("preamble", text[:starts[0]]))
    for i, pos in enumerate(starts):
        end = starts[i + 1] if i + 1 < len(starts) else len(text)
        blocks.append(("object", text[pos:end]))
else:
    blocks = [("preamble", text)]

chunks = {"01_tables_and_constraints.sql": [],
          "02_functions_and_triggers.sql": [],
          "03_rls_and_acls.sql": [],
          "04_indexes_and_realtime.sql": []}

for kind, block in blocks:
    if kind == "preamble":
        chunks["01_tables_and_constraints.sql"].append(block)
        continue
    m = re.search(r"^-- Name: .*?; Type: ([^;]+); Schema: public;", block, re.M)
    obj_type = (m.group(1).strip().upper() if m else "UNKNOWN")
    if obj_type in {"FUNCTION", "PROCEDURE"}:
        target = "02_functions_and_triggers.sql"
    elif obj_type in {"TRIGGER"}:
        target = "02_functions_and_triggers.sql"
    elif obj_type in {"POLICY"}:
        target = "03_rls_and_acls.sql"
    elif obj_type in {"INDEX", "INDEX ATTACHED TO"}:
        target = "04_indexes_and_realtime.sql"
    else:
        target = "01_tables_and_constraints.sql"
    chunks[target].append(block)

headers = {
    "01_tables_and_constraints.sql": "-- CANONICAL LIVE CHUNK 01: tables, sequences, types, constraints and remaining pre-data objects\n",
    "02_functions_and_triggers.sql": "-- CANONICAL LIVE CHUNK 02: functions, procedures and triggers\n",
    "03_rls_and_acls.sql": "-- CANONICAL LIVE CHUNK 03: RLS policies and runtime security overlay\n",
    "04_indexes_and_realtime.sql": "-- CANONICAL LIVE CHUNK 04: indexes and Supabase Realtime overlay\n",
}
for name, parts in chunks.items():
    (out / name).write_text(headers[name] + "\n".join(parts), encoding="utf-8")
PY

# Runtime overlay is intentionally appended to the relevant chunks and the master
# aggregator. This keeps Realtime/RLS/ACL evidence executable and reviewable.
if [[ -s "$RUNTIME_TMP" ]]; then
  cat "$RUNTIME_TMP" >> "$CANONICAL/03_rls_and_acls.sql"
  cat "$RUNTIME_TMP" >> "$CANONICAL/04_indexes_and_realtime.sql"
fi

{
  printf '%s\n' '-- CANONICAL BASELINE: canonical live PostgreSQL public schema';
  printf '%s\n' '-- Generated from a read-only source connection; no source DDL is executed.';
  cat "$CANONICAL/01_tables_and_constraints.sql";
  cat "$CANONICAL/02_functions_and_triggers.sql";
  cat "$CANONICAL/03_rls_and_acls.sql";
  cat "$CANONICAL/04_indexes_and_realtime.sql";
  printf '%s\n' '-- END CANONICAL BASELINE';
} > "$OUT"

printf 'Canonical baseline written to: %s\n' "$OUT"
printf 'Atomic chunks written under: %s\n' "$CANONICAL"
