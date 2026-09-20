#!/usr/bin/env bash
# Read ONE value back out of the linked Supabase project — and nothing else.
#
# `supabase db query` writes for a human by default: a box-drawn table, with
# the CLI's own chatter before it and, when a newer CLI exists, an update nag
# printed AFTER the document. The CLI only switches to JSON on its own when it
# thinks it is talking to a program (`--agent` detection), which is exactly why
# a readback written and proved in an agent's terminal read nothing in CI:
# deploy-supabase 35480151258 logged `usda_food rows: unreadable` and an empty
# template count while the reseed underneath it was perfectly fine.
#
# So this asks for JSON by name rather than hoping for it, keeps stderr out of
# the parser, silences the nag with the CLI's own switch, and decodes exactly
# one JSON document starting at the first `{` — anything the CLI prints after
# the document cannot reach the value. Nothing here matches on the CLI's
# wording, which is the only reason it survives the next release's prose.
#
# One row, one column, or it exits non-zero and says which — a caller must
# never be able to mistake "could not read" for a number. Callers that only
# log the value can choose to tolerate that (`|| true`); a caller that BRANCHES
# on it must not.
#
# Usage: scripts/db_query_value.sh "select count(*) from usda_food"
# Env:   SUPABASE_BIN  the CLI to run (default `supabase`; the test points this
#                      at a stand-in so it never touches a real project).
set -euo pipefail

sql=${1:?usage: db_query_value.sh "<sql returning one row, one column>"}
: "${SUPABASE_BIN:=supabase}"

# SUPABASE_NO_UPDATE_NOTIFIER is the CLI's own switch for the update nag. It is
# belt to the braces of decoding only the document: if a future CLI ignores it,
# or renames it, the parse still holds.
if ! out=$(SUPABASE_NO_UPDATE_NOTIFIER=1 "$SUPABASE_BIN" db query --linked \
             --output json "$sql" 2>/dev/null); then
  echo "db_query_value: supabase db query failed — $sql" >&2
  exit 1
fi

# raw_decode, not a brace count: it stops at the end of the first JSON value and
# ignores every byte after it, and it cannot be fooled by a `}` inside a string.
printf '%s' "$out" | python3 -c '
import json, sys

raw = sys.stdin.read()
start = raw.find("{")
if start < 0:
    head = " ".join(raw.split())[:120] or "(nothing)"
    sys.exit("db_query_value: the CLI printed no JSON document — got: " + head
             + "\n  (a box-drawn table here means --output json did not take)")
try:
    doc, _ = json.JSONDecoder().raw_decode(raw[start:])
except ValueError as e:
    sys.exit("db_query_value: unparsable JSON document — %s" % e)

rows = doc.get("rows")
if not isinstance(rows, list):
    sys.exit("db_query_value: the document has no `rows` array — keys: %s"
             % ", ".join(sorted(doc)))
if len(rows) != 1:
    sys.exit("db_query_value: expected one row, got %d" % len(rows))
cols = list(rows[0].values())
if len(cols) != 1:
    sys.exit("db_query_value: expected one column, got %d (%s)"
             % (len(cols), ", ".join(sorted(rows[0]))))
print(cols[0])
'
