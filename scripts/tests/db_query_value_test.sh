#!/usr/bin/env bash
# Fixtures for scripts/db_query_value.sh — the deploy's readback helper.
#
# Every case is a stand-in `supabase` printing a shape the real CLI has been
# seen to print, chatter on both streams and both sides of the document, so
# this never needs a project, a network or the local stack.
#
# Run: ./scripts/tests/db_query_value_test.sh   (also `make scripts-test`)
set -uo pipefail
cd "$(dirname "$0")/../.."

HELPER=$PWD/scripts/db_query_value.sh
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
pass=0
fail=0

# Writes a stand-in CLI that records its argv + the notifier env, then prints
# $2 on stdout, $3 on stderr, and exits $4.
stand_in() {
  local name=$1 out=$2 err=${3:-} rc=${4:-0}
  local bin=$tmp/$name
  {
    echo '#!/usr/bin/env bash'
    echo "printf '%s\\n' \"\$@\" > '$tmp/argv.$name'"
    echo "printf '%s' \"\${SUPABASE_NO_UPDATE_NOTIFIER:-}\" > '$tmp/notifier.$name'"
    echo "cat <<'STDOUT_EOF'"
    printf '%s\n' "$out"
    echo 'STDOUT_EOF'
    if [ -n "$err" ]; then
      echo "cat >&2 <<'STDERR_EOF'"
      printf '%s\n' "$err"
      echo 'STDERR_EOF'
    fi
    echo "exit $rc"
  } > "$bin"
  chmod +x "$bin"
  echo "$bin"
}

ok()  { pass=$((pass + 1)); echo "  ✓ $1"; }
bad() { fail=$((fail + 1)); echo "  ✗ $1"; }

# $1 case name, $2 expected value, $3.. stand_in args
expect_value() {
  local what=$1 want=$2
  shift 2
  local bin got rc
  bin=$(stand_in "$(echo "$what" | tr -cd '[:alnum:]')" "$@")
  got=$(SUPABASE_BIN=$bin "$HELPER" 'select count(*) from usda_food' 2>"$tmp/err")
  rc=$?
  if [ "$rc" != 0 ]; then
    bad "$what — exited $rc: $(head -1 "$tmp/err")"
  elif [ "$got" != "$want" ]; then
    bad "$what — read [$got], wanted [$want]"
  else
    ok "$what → $got"
  fi
}

# $1 case name, $2 substring the diagnosis must contain, $3.. stand_in args
expect_failure() {
  local what=$1 needle=$2
  shift 2
  local bin got rc
  bin=$(stand_in "$(echo "$what" | tr -cd '[:alnum:]')" "$@")
  got=$(SUPABASE_BIN=$bin "$HELPER" 'select count(*) from usda_food' 2>"$tmp/err")
  rc=$?
  if [ "$rc" = 0 ]; then
    bad "$what — exited 0 with [$got]; an unreadable value must never pass as one"
  elif ! grep -qF "$needle" "$tmp/err"; then
    bad "$what — failed, but says: $(head -2 "$tmp/err" | tr '\n' ' ')"
  else
    ok "$what → refused, naming it"
  fi
}

NAG='A new version of Supabase CLI is available: v2.117.0 (currently installed v2.115.0)
We recommend updating regularly for new features and bug fixes: https://supabase.com/docs/guides/cli/getting-started#updating-the-supabase-cli'

echo "• the document is read wherever the CLI chats"
expect_value "a bare document" 8204 '{"rows":[{"count":8204}]}'
expect_value "chatter before it" 8204 \
  "Initialising login role...
{\"rows\":[{\"count\":8204}]}"
expect_value "the nag AFTER it, on stdout" 8204 \
  "{\"rows\":[{\"count\":8204}]}
$NAG"
expect_value "the nag on stderr" 8204 '{"rows":[{"count":8204}]}' "$NAG"
expect_value "chatter both sides, both streams" 8204 \
  "Initialising login role...
{\"rows\":[{\"count\":8204}]}
$NAG" "Connecting to remote database..."
expect_value "pretty-printed across lines" 323 \
  '{
  "rows": [
    { "count": 323 }
  ]
}
'"$NAG"
# A `}` inside a string used to be the reason not to hand-roll a brace count.
expect_value "a value holding a brace, then prose" 'pack (500 g} odd' \
  '{"rows":[{"label":"pack (500 g} odd"}]}
'"$NAG"

echo "• an unreadable answer is never a value"
# The CLI's human default when JSON is not asked for by name.
expect_failure "the box-drawn table" "no JSON document" \
  '┌──────────┐
│  count   │
├──────────┤
│  8204    │
└──────────┘'
expect_failure "nothing at all" "no JSON document" ''
expect_failure "only the nag" "no JSON document" "$NAG"
expect_failure "a truncated document" "unparsable JSON document" '{"rows":[{"count":82'
expect_failure "a document with no rows array" "no \`rows\` array" '{"error":"permission denied"}'
expect_failure "two rows" "expected one row, got 2" \
  '{"rows":[{"count":1},{"count":2}]}'
expect_failure "two columns" "expected one column, got 2" \
  '{"rows":[{"count":1,"other":2}]}'
expect_failure "the CLI itself failing" "supabase db query failed" \
  '{"rows":[{"count":8204}]}' 'error: failed to connect' 1
expect_failure "the CLI's own reason is passed on" "error: failed to connect" \
  '' 'error: failed to connect' 1

echo "• the helper asks for the shape rather than hoping for it"
bin=$(stand_in "argv" '{"rows":[{"count":1}]}')
SUPABASE_BIN=$bin "$HELPER" 'select 1' >/dev/null 2>&1
argv=$(tr '\n' ' ' < "$tmp/argv.argv")
case "$argv" in
  *"--output json"*) ok "--output json is passed explicitly" ;;
  *) bad "--output json is missing from: $argv" ;;
esac
case "$argv" in
  *--linked*) ok "--linked is still how it reaches the project" ;;
  *) bad "--linked is missing from: $argv" ;;
esac
if [ "$(cat "$tmp/notifier.argv")" = "1" ]; then
  ok "SUPABASE_NO_UPDATE_NOTIFIER=1 reaches the CLI"
else
  bad "SUPABASE_NO_UPDATE_NOTIFIER was [$(cat "$tmp/notifier.argv")], wanted 1"
fi

echo
echo "db_query_value: $pass ok · $fail failed"
[ "$fail" = 0 ]
