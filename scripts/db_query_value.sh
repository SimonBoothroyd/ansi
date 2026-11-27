#!/usr/bin/env bash
# Read ONE value back out of the linked Supabase project.
#
# `supabase db query` prints a box-drawn table unless JSON is asked for by
# name, and may chat before and after the document on either stream. So this
# asks for JSON, parses stdout alone and decodes only the first document.
#
# One row, one column, or it exits non-zero saying why (the CLI's own error
# included): "could not read" must never pass for a number.
#
# Usage: scripts/db_query_value.sh "select count(*) from usda_food"
# Env:   SUPABASE_BIN  the CLI to run (default `supabase`; the test points this
#                      at a stand-in so it never touches a real project).
set -euo pipefail

sql=${1:?usage: db_query_value.sh "<sql returning one row, one column>"}
: "${SUPABASE_BIN:=supabase}"

err=$(mktemp)
trap 'rm -f "$err"' EXIT

# SUPABASE_NO_UPDATE_NOTIFIER is the CLI's own switch for its update nag.
if ! out=$(SUPABASE_NO_UPDATE_NOTIFIER=1 "$SUPABASE_BIN" db query --linked \
             --output json "$sql" 2>"$err"); then
  echo "db_query_value: supabase db query failed — $sql" >&2
  tail -n 5 "$err" >&2
  exit 1
fi

# raw_decode, not a brace count: it stops at the end of the first JSON value and
# ignores every byte after it, and it cannot be fooled by a `}` inside a string.
printf '%s' "$out" | python3 -c '
import json, sys

raw = sys.stdin.read()
# The CLI prints {"rows": [...], ...} where it wraps results for an agent, and
# a bare [...] of rows elsewhere (CI). Decode the first value that parses at a
# "{" or "[" (a colour code like "\x1b[31m" does not).
doc = None
broken = None  # the first object that started but did not parse
for i, ch in enumerate(raw):
    if ch not in "{[":
        continue
    try:
        doc, _ = json.JSONDecoder().raw_decode(raw[i:])
    except ValueError as e:
        if ch == "{" and broken is None:
            broken = e
        continue
    if isinstance(doc, (dict, list)):
        break
    doc = None
if doc is None and broken is not None:
    sys.exit("db_query_value: unparsable JSON document — %s" % broken)
if doc is None:
    head = " ".join(raw.split())[:120] or "(nothing)"
    sys.exit("db_query_value: the CLI printed no JSON document — got: " + head
             + "\n  (a box-drawn table here means --output json did not take)")

rows = doc if isinstance(doc, list) else doc.get("rows")
if not isinstance(rows, list):
    sys.exit("db_query_value: the document has no `rows` array — keys: %s"
             % ", ".join(sorted(doc)))
if rows and not isinstance(rows[0], dict):
    sys.exit("db_query_value: a row is not an object — got %r" % (rows[0],))
if len(rows) != 1:
    sys.exit("db_query_value: expected one row, got %d" % len(rows))
cols = list(rows[0].values())
if len(cols) != 1:
    sys.exit("db_query_value: expected one column, got %d (%s)"
             % (len(cols), ", ".join(sorted(rows[0]))))
print(cols[0])
'
