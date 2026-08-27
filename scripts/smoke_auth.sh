#!/usr/bin/env bash
# Smoke-test the auth → onboarding → household_id-claim path against a Supabase
# instance (local or cloud). Complements supabase/tests/onboarding.sql (which
# tests the DB function directly) by exercising the full HTTP path, including the
# GoTrue custom-access-token hook that injects household_id — the load-bearing
# bit that must be enabled in config.toml (local) or the dashboard (cloud).
#
# Usage:
#   SUPABASE_URL=... SUPABASE_ANON_KEY=... scripts/smoke_auth.sh
# Defaults to the local stack when the env vars are unset.
set -euo pipefail

URL="${SUPABASE_URL:-http://127.0.0.1:54321}"
ANON="${SUPABASE_ANON_KEY:-eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZS1kZW1vIiwicm9sZSI6ImFub24iLCJleHAiOjE5ODM4MTI5OTZ9.CRXP1A7WOeoJeXxjNni43kdQwgnWNReilDMblYTn_I0}"
# example.com is on Supabase cloud's invalid-email blocklist; use a plausible
# real-TLD domain instead. Override with SMOKE_EMAIL if you like.
EMAIL="${SMOKE_EMAIL:-smoke$(date +%s)@mise.app}"
PASS="smoke-password-123"

echo "→ target: $URL"
echo "→ 1/4 sign up a throwaway user ($EMAIL)"
T1=$(curl -fsS -X POST "$URL/auth/v1/signup" -H "apikey: $ANON" \
  -H "Content-Type: application/json" \
  -d "{\"email\":\"$EMAIL\",\"password\":\"$PASS\"}" \
  | python3 -c "import sys,json;print(json.load(sys.stdin).get('access_token',''))")
[ -n "$T1" ] || { echo "✗ signup returned no access token (email confirmations on?)"; exit 1; }

echo "→ 2/4 call ensure_onboarded() over PostgREST"
HH=$(curl -fsS -X POST "$URL/rest/v1/rpc/ensure_onboarded" -H "apikey: $ANON" \
  -H "Authorization: Bearer $T1" -H "Content-Type: application/json" -d '{}' \
  | tr -d '"')
echo "   onboarded household: $HH"
[ -n "$HH" ] || { echo "✗ ensure_onboarded returned nothing"; exit 1; }

echo "→ 3/4 reissue a token and decode its claims"
CLAIM=$(curl -fsS -X POST "$URL/auth/v1/token?grant_type=password" -H "apikey: $ANON" \
  -H "Content-Type: application/json" \
  -d "{\"email\":\"$EMAIL\",\"password\":\"$PASS\"}" \
  | python3 -c "
import sys,json,base64
t=json.load(sys.stdin)['access_token']
p=t.split('.')[1]; p+='='*(-len(p)%4)
print(json.loads(base64.urlsafe_b64decode(p)).get('household_id',''))")

echo "→ 4/4 assert the JWT carries household_id"
if [ "$CLAIM" = "$HH" ]; then
  echo "✓ PASS — JWT household_id ($CLAIM) matches the onboarded household."
else
  echo "✗ FAIL — JWT household_id='$CLAIM' but onboarded='$HH'."
  echo "  The custom-access-token hook (add_household_claim) is likely not enabled"
  echo "  (config.toml locally — needs 'supabase stop && start'; dashboard on cloud)."
  exit 1
fi
