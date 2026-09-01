#!/usr/bin/env bash
# Smoke-test the auth → onboarding → household_id-claim path against a Supabase
# instance (local or cloud). Complements supabase/tests/onboarding.sql (which
# tests the DB function directly) by exercising the full HTTP path, including the
# GoTrue custom-access-token hook that injects household_id — the load-bearing
# bit that must be enabled in config.toml (local) or the dashboard (cloud).
#
# Reports along the way:
#   - the SIGNUP token's claims (the app's real first-run credential — the
#     step-7 empty-first-sync bug lived exactly there): expected to carry NO
#     household_id before onboarding, which is why the app must refresh its
#     session after ensure_onboarded.
#   - whether the user JOINED an existing open-seat household or CREATED a
#     fresh one (the canary for the open-seat model: on a shared instance a
#     smoke user silently taking a real household's second seat is pollution —
#     see the teardown block at the bottom).
#
# Usage:
#   SUPABASE_URL=... SUPABASE_ANON_KEY=... scripts/smoke_auth.sh
# Defaults to the local stack when the env vars are unset. NOTE: every run
# creates a throwaway auth user + membership on the target — fine locally
# (data is ephemeral); on cloud, run the teardown afterwards.
set -euo pipefail

URL="${SUPABASE_URL:-http://127.0.0.1:54321}"
ANON="${SUPABASE_ANON_KEY:-eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZS1kZW1vIiwicm9sZSI6ImFub24iLCJleHAiOjE5ODM4MTI5OTZ9.CRXP1A7WOeoJeXxjNni43kdQwgnWNReilDMblYTn_I0}"
# example.com is on Supabase cloud's invalid-email blocklist; use a plausible
# real-TLD domain instead. Override with SMOKE_EMAIL if you like.
EMAIL="${SMOKE_EMAIL:-smoke$(date +%s)@ansi.app}"
PASS="smoke-password-123"

# Decode one claim from a JWT payload (no verification — inspection only).
claim() { # $1=token $2=claim
  python3 -c "
import sys, json, base64
p = sys.argv[1].split('.')[1]; p += '=' * (-len(p) % 4)
print(json.loads(base64.urlsafe_b64decode(p)).get(sys.argv[2], ''))" "$1" "$2"
}

echo "→ target: $URL"
echo "→ 1/5 sign up a throwaway user ($EMAIL)"
SIGNUP_EPOCH=$(date -u +%s)
T1=$(curl -fsS -X POST "$URL/auth/v1/signup" -H "apikey: $ANON" \
  -H "Content-Type: application/json" \
  -d "{\"email\":\"$EMAIL\",\"password\":\"$PASS\"}" \
  | python3 -c "import sys,json;print(json.load(sys.stdin).get('access_token',''))")
[ -n "$T1" ] || { echo "✗ signup returned no access token (email confirmations on?)"; exit 1; }

echo "→ 2/5 decode the SIGNUP token (the app's first-run credential)"
SIGNUP_HH=$(claim "$T1" household_id)
if [ -z "$SIGNUP_HH" ]; then
  echo "   ✓ signup token carries NO household_id (expected pre-onboarding —"
  echo "     this is why the app must refresh its session after ensure_onboarded)"
else
  echo "   ! signup token already carries household_id=$SIGNUP_HH — unexpected"
  echo "     for a fresh user; the hook found an existing membership?"
fi

echo "→ 3/5 call ensure_onboarded() over PostgREST"
HH=$(curl -fsS -X POST "$URL/rest/v1/rpc/ensure_onboarded" -H "apikey: $ANON" \
  -H "Authorization: Bearer $T1" -H "Content-Type: application/json" -d '{}' \
  | tr -d '"')
echo "   onboarded household: $HH"
[ -n "$HH" ] || { echo "✗ ensure_onboarded returned nothing"; exit 1; }

# Joined-vs-created canary: RLS resolves membership via auth.uid(), so the
# pre-claim signup token can already read the household + its members. Joining
# an open seat leaves 2 live members (create leaves 1 — me); a household
# created clearly before this run's signup is the same signal from the other
# side. On a shared target, JOINED means this smoke run took a real
# household's second seat — clean it up (teardown notes below).
HH_INFO=$(curl -fsS \
  "$URL/rest/v1/household?id=eq.$HH&select=created_at,household_member(id,deleted_at)" \
  -H "apikey: $ANON" -H "Authorization: Bearer $T1" \
  | python3 -c "
import sys, json
rows = json.load(sys.stdin)
if rows:
    members = [m for m in rows[0]['household_member'] if not m['deleted_at']]
    print(rows[0]['created_at'], len(members))")
if [ -n "$HH_INFO" ]; then
  read -r HH_CREATED HH_MEMBERS <<<"$HH_INFO"
  python3 -c "
import sys
from datetime import datetime, timezone
raw, members, signup = sys.argv[1], int(sys.argv[2]), int(sys.argv[3])
created = datetime.fromisoformat(raw.replace('Z', '+00:00'))
if created.tzinfo is None:
    created = created.replace(tzinfo=timezone.utc)
age = signup - int(created.timestamp())
if members > 1 or age > 120:
    print(f'   ! JOINED an existing household ({members} live members,')
    print(f'     created {raw}, {age}s before signup) — this run took an')
    print( '     open seat; see the teardown notes below.')
else:
    print(f'   ✓ CREATED a fresh household (created {raw}, sole member)')" \
    "$HH_CREATED" "$HH_MEMBERS" "$SIGNUP_EPOCH"
else
  echo "   ! could not read the household row back (RLS/grants?)"
fi

echo "→ 4/5 reissue a token and decode its claims"
T2=$(curl -fsS -X POST "$URL/auth/v1/token?grant_type=password" -H "apikey: $ANON" \
  -H "Content-Type: application/json" \
  -d "{\"email\":\"$EMAIL\",\"password\":\"$PASS\"}" \
  | python3 -c "import sys,json;print(json.load(sys.stdin).get('access_token',''))")
[ -n "$T2" ] || { echo "✗ password grant returned no access token"; exit 1; }
CLAIM=$(claim "$T2" household_id)

echo "→ 5/5 assert the reissued JWT carries household_id"
if [ "$CLAIM" = "$HH" ]; then
  echo "✓ PASS — JWT household_id ($CLAIM) matches the onboarded household."
else
  echo "✗ FAIL — JWT household_id='$CLAIM' but onboarded='$HH'."
  echo "  The custom-access-token hook (add_household_claim) is likely not enabled"
  echo "  (config.toml locally — needs 'supabase stop && start'; dashboard on cloud)."
  exit 1
fi

# ─── Teardown (HUMAN-RUN ONLY — this script never deletes anything) ──────────
#
# Each run leaves a throwaway auth user + household_member row (+ possibly a
# household) on the target. Locally that's fine (`supabase db reset` wipes it);
# on CLOUD, clean up after yourself with service-role janitor SQL, following
# the repo's soft-delete rule (docs/SECURITY.md — no hard deletes of domain
# rows). Run via the SQL editor or `supabase db query --linked`, substituting
# the smoke email:
#
#   -- 1. soft-delete the smoke user's membership
#   update household_member m set deleted_at = now()
#   from auth.users u
#   where u.id = m.auth_user_id
#     and u.email like 'smoke%@ansi.app'
#     and m.deleted_at is null;
#
#   -- 2. soft-delete any household that is now empty (never a template)
#   update household h set deleted_at = now()
#   where h.deleted_at is null and not h.is_template
#     and not exists (select 1 from household_member m
#                     where m.household_id = h.id and m.deleted_at is null);
#
#   -- 3. the auth.users row itself: hard-delete is DASHBOARD-ONLY
#   --    (Authentication → Users → delete). The harness intentionally blocks
#   --    destructive SQL against cloud, and auth schema rows have no
#   --    deleted_at — do not script this.
# ─────────────────────────────────────────────────────────────────────────────
