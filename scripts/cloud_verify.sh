#!/usr/bin/env bash
# Read-only cloud health check for the Mise cloud stack (Supabase Cloud +
# PowerSync Cloud). STRICTLY NON-MUTATING: every check is a GET against a
# public endpoint — this script must never be the thing that pollutes the
# target (see exec plan 0009's decision log). It cannot see dashboard-only
# toggles that lack public surfaces (the auth hook, PowerSync JWT audience);
# those come from the SQL block it prints (human-run, read-only) plus the
# checklist in docs/cloud-setup.md. Record each run in that file's ledger.
#
# Usage:  ./scripts/cloud_verify.sh          (reads cloud.env at the repo root)
set -euo pipefail
cd "$(dirname "$0")/.."

# shellcheck disable=SC1091
source ./cloud.env
: "${CLOUD_SUPABASE_URL:?cloud.env is missing CLOUD_SUPABASE_URL}"
for v in CLOUD_SUPABASE_PUBLISHABLE_KEY CLOUD_POWERSYNC_URL; do
  [ "${!v}" = "FILL_ME" ] && { echo "✗ fill $v in cloud.env first"; exit 1; }
done

pass=0; warn=0; fail=0
ok()   { echo "  ✓ $1"; pass=$((pass+1)); }
bad()  { echo "  ✗ $1"; fail=$((fail+1)); }
note() { echo "  ! $1"; warn=$((warn+1)); }

echo "→ target: $CLOUD_SUPABASE_URL · $CLOUD_POWERSYNC_URL"

echo "• auth signing (JWKS)"
jwks=$(curl -fsS -m 15 "$CLOUD_SUPABASE_URL/auth/v1/.well-known/jwks.json" || true)
if [ -z "$jwks" ]; then bad "JWKS endpoint unreachable"; else
  if echo "$jwks" | python3 -c "
import sys, json
keys = json.load(sys.stdin).get('keys', [])
assert any(k.get('alg') == 'ES256' for k in keys), 'no ES256 key'
" 2>/dev/null; then ok "JWKS serves an ES256 key (matches PowerSync client_auth)"
  else bad "JWKS has no ES256 key — PowerSync token verification will fail"; fi
fi

echo "• auth service health"
if curl -fsS -m 15 -H "apikey: $CLOUD_SUPABASE_PUBLISHABLE_KEY" \
     "$CLOUD_SUPABASE_URL/auth/v1/health" >/dev/null; then
  ok "GoTrue healthy"
else bad "auth health endpoint failed"; fi

echo "• auth settings (providers, confirmations)"
settings=$(curl -fsS -m 15 -H "apikey: $CLOUD_SUPABASE_PUBLISHABLE_KEY" \
  "$CLOUD_SUPABASE_URL/auth/v1/settings" || true)
verdict=$(echo "$settings" | python3 -c "
import sys, json
s = json.load(sys.stdin)
ext = s.get('external', {})
print(int(bool(ext.get('google'))), int(bool(ext.get('email'))),
      int(bool(s.get('mailer_autoconfirm'))))
" 2>/dev/null || true)
if [ -z "$verdict" ]; then bad "settings endpoint unreachable/unparsable"; else
  read -r g e ac <<<"$verdict"
  if [ "$g" = 1 ]; then ok "Google provider enabled"
  else bad "Google provider DISABLED (runbook §1.5)"; fi
  if [ "$e" = 1 ]; then ok "email/password enabled"
  else bad "email/password disabled"; fi
  if [ "$ac" = 1 ]; then
    note "email confirmations OFF (dev convenience — turn ON before anything real)"
  else ok "email confirmations ON"; fi
fi

echo "• PostgREST reachability (anon, RLS-gated)"
code=$(curl -s -m 15 -o /dev/null -w '%{http_code}' \
  -H "apikey: $CLOUD_SUPABASE_PUBLISHABLE_KEY" \
  "$CLOUD_SUPABASE_URL/rest/v1/ingredient?select=id&limit=1" || true)
code=${code:-000}
if [ "$code" = "200" ]; then
  ok "PostgREST up (anon sees an empty, RLS-filtered result)"
elif [ "$code" = "401" ] || [ "$code" = "403" ]; then
  ok "PostgREST up (anon denied by RLS/grants — also fine)"
else bad "PostgREST returned HTTP $code"; fi

echo "• PowerSync instance"
pscode=$(curl -s -m 15 -o /dev/null -w '%{http_code}' \
  "$CLOUD_POWERSYNC_URL/probes/liveness" || true)
pscode=${pscode:-000}
if [ "$pscode" = "200" ]; then ok "liveness probe OK"; else
  # Older images route probes differently; any HTTP response at all still
  # proves the instance resolves and serves.
  root=$(curl -s -m 15 -o /dev/null -w '%{http_code}' "$CLOUD_POWERSYNC_URL" || true)
  root=${root:-000}
  if [ "$root" != "000" ]; then note "liveness probe HTTP $pscode; root answers HTTP $root (instance up)"
  else bad "PowerSync instance unreachable"; fi
fi

echo "• sync-rule boundary (repo copies)"
if ./scripts/check_stream_drift.sh; then pass=$((pass+1)); else fail=$((fail+1)); fi

cat <<'SQL'

── human-run, read-only (agents are permission-gated from --linked on purpose) ──
Run:  supabase db query --linked "<paste each>"
  -- migrations applied (compare with: ls supabase/migrations | wc -l)
  select count(*) from supabase_migrations.schema_migrations;
  -- the load-bearing hook function exists
  select exists(select 1 from pg_proc p join pg_namespace n on n.oid = p.pronamespace
                where p.proname = 'add_household_claim' and n.nspname = 'public');
  -- RLS enabled everywhere it should be (expect 14: 13 domain tables + usda_food)
  select count(*) from pg_class c join pg_namespace n on n.oid = c.relnamespace
  where n.nspname = 'public' and c.relkind = 'r' and c.relrowsecurity;
  -- WAL bounded (runbook §1.3; an idle slot must not fill the disk)
  select name, setting from pg_settings where name in ('max_wal_size','max_slot_wal_keep_size');
  -- vocab carries macros (expect ~248 complete rows in the template household)
  select count(*) filter (where macros is not null), count(*) from ingredient i
  join household h on h.id = i.household_id where h.is_template;
  -- junk-household census (smoke users accumulate; see smoke_auth teardown)
  select h.id, h.is_template, h.created_at, count(m.id) as members
  from household h left join household_member m
    on m.household_id = h.id and m.deleted_at is null
  where h.deleted_at is null group by 1,2,3 order by h.created_at;
──────────────────────────────────────────────────────────────────────────────
SQL

echo
echo "cloud_verify: $pass ok · $warn warn · $fail fail"
[ "$fail" -eq 0 ] || exit 1
