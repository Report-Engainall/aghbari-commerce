#!/usr/bin/env bash
set -euo pipefail

PGURL="postgresql://postgres@127.0.0.1:54322/postgres"
PROBE="war-room/f31/f31-mutation-probe.test.sql"
OUT="${1:-/tmp/f31}"
mkdir -p "$OUT"

count_not_ok() { awk '/^[[:space:]]*not ok /{n++} END{print n+0}' "$1"; }
count_ok() { awk '/^[[:space:]]*ok [0-9]+ - /{n++} END{print n+0}' "$1"; }
run_probe() {
  local label="$1"
  psql "$PGURL" -v ON_ERROR_STOP=1 -f "$PROBE" | tee "$OUT/${label}.tap"
}
assert_green() {
  local f="$1"
  test "$(count_ok "$f")" -eq 8
  test "$(count_not_ok "$f")" -eq 0
}
assert_red() {
  local f="$1"
  test "$(count_not_ok "$f")" -ge 1
}
run_case() {
  local label="$1" mutation="$2"
  echo "===== F31 $label ====="
  supabase db reset --local --no-seed
  run_probe "${label}-baseline"
  assert_green "$OUT/${label}-baseline.tap"
  psql "$PGURL" -v ON_ERROR_STOP=1 -c "$mutation"
  run_probe "${label}-mutated"
  assert_red "$OUT/${label}-mutated.tap"
  supabase db reset --local --no-seed
  run_probe "${label}-restored"
  assert_green "$OUT/${label}-restored.tap"
}

supabase start
run_case inventory "alter table public.products disable row level security;"
run_case finance "alter table public.cash_accounts disable row level security;"
run_case orders "alter table public.orders disable row level security;"
run_case tenant "do \$\$ declare p text; begin select policyname into p from pg_policies where schemaname='public' and tablename='products' limit 1; if p is null then raise exception 'no product policy'; end if; execute format('drop policy %I on public.products', p); end \$\$;"
run_case storage "do \$\$ declare p text; begin select policyname into p from pg_policies where schemaname='storage' and tablename='objects' limit 1; if p is null then raise exception 'no storage policy'; end if; execute format('drop policy %I on storage.objects', p); end \$\$;"
run_case rbac "create function public.f31_forbidden_rpc() returns integer language sql as \$\$select 1\$\$; grant execute on function public.f31_forbidden_rpc() to anon;"
run_case idempotency "drop index if exists public.orders_idempotency_unique_idx;"
run_case outbox "drop function public.claim_outbox_events(integer);"

echo 'F31 mutation proof PASS: eight boundaries each detected deliberate mutation and returned green after clean reset.'
