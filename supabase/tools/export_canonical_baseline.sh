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

pg_dump "$DB_URL" \
  --schema-only \
  --schema=public \
  --no-owner \
  --no-privileges \
  --file="$TMP"

if [[ -f "$ROOT/supabase/tools/emit_canonical_runtime.sql" ]]; then
  psql "$DB_URL" -v ON_ERROR_STOP=1 -f "$ROOT/supabase/tools/emit_canonical_runtime.sql" > "$RUNTIME_TMP"
fi

# Split complete pg_dump object blocks into deterministic executable chunks.
python3 - "$TMP" "$CANONICAL" <<'PY'
import pathlib
import re
import sys

src = pathlib.Path(sys.argv[1])
out = pathlib.Path(sys.argv[2])
text = src.read_text(encoding="utf-8")
starts = [m.start() for m in re.finditer(r"(?m)^-- Name: .+?; Type: .+?; Schema: public;", text)]
blocks = []
if starts:
    if starts[0] > 0:
        blocks.append(("preamble", text[:starts[0]]))
    for i, pos in enumerate(starts):
        blocks.append(("object", text[pos: starts[i + 1] if i + 1 < len(starts) else len(text)]))
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
    if obj_type in {"FUNCTION", "PROCEDURE", "TRIGGER"}:
        target = "02_functions_and_triggers.sql"
    elif obj_type == "POLICY":
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

if [[ -s "$RUNTIME_TMP" ]]; then
  python3 - "$RUNTIME_TMP" "$CANONICAL" <<'PY'
import pathlib
import sys
text = pathlib.Path(sys.argv[1]).read_text(encoding="utf-8")
out = pathlib.Path(sys.argv[2])
start1, end1 = "-- RUNTIME_RLS_ACL_BEGIN", "-- RUNTIME_RLS_ACL_END"
start2, end2 = "-- RUNTIME_REALTIME_BEGIN", "-- RUNTIME_REALTIME_END"

def section(a, b):
    if a not in text or b not in text:
        return ""
    return text.split(a, 1)[1].split(b, 1)[0].strip()

rls = section(start1, end1)
realtime = section(start2, end2)
if rls:
    with (out / "03_rls_and_acls.sql").open("a", encoding="utf-8") as f:
        f.write("\n\n-- LIVE RUNTIME SECURITY OVERLAY\n" + rls + "\n")
if realtime:
    with (out / "04_indexes_and_realtime.sql").open("a", encoding="utf-8") as f:
        f.write("\n\n-- LIVE SUPABASE REALTIME OVERLAY\n" + realtime + "\n")
PY
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
