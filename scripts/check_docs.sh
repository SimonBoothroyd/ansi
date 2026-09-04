#!/usr/bin/env bash
# Mechanical knowledge-base check (hobby-scale "doc-gardening"). Every check
# below catches one class of drift that has actually happened here:
#   1. required harness files exist
#   2. every relative markdown link resolves to a real file
#   3. the local and cloud sync streams have not diverged
#   4. the generated schema matches the migrations (i.e. `make docs` was run)
#   5. no plan in active/ claims it is done; a plan that has gone quiet warns
#   6. no duplicate area in the standing table; no table split by a stray line
#   7. every ADR is linked from the design-docs index
#   8. date density in a current-state doc (warn) — the disease, not a symptom
# Wired into CI (.github/workflows/docs.yml) and `make docs-check`.
set -uo pipefail   # NB: no `-e` — grep returning 1 on no-match is expected here.
cd "$(dirname "$0")/.."

fail=0

echo "• required files"
for f in AGENTS.md ARCHITECTURE.md README.md docs/README.md \
         docs/exec-plans/roadmap.md docs/design-docs/core-beliefs.md; do
  if [ -f "$f" ]; then echo "  ✓ $f"; else echo "  ✗ missing: $f"; fail=1; fi
done

echo "• relative markdown links resolve"
broken=0
while IFS= read -r md; do
  dir=$(dirname "$md")
  # `|| true` so a link-less file doesn't abort the loop.
  links=$(grep -oE '\]\(([^)]+)\)' "$md" 2>/dev/null | sed -E 's/^\]\(([^)]+)\)$/\1/' || true)
  [ -z "$links" ] && continue
  while IFS= read -r link; do
    case "$link" in http*|mailto:*|\#*|'') continue ;; esac
    target="${link%%#*}"           # strip #anchor
    [ -z "$target" ] && continue
    if [ ! -e "$dir/$target" ]; then
      echo "  ✗ $md → $link"
      broken=$((broken + 1))
    fi
  done <<< "$links"
done < <(find . -name '*.md' -not -path './app/build/*' -not -path '*/node_modules/*' \
  -not -path './.claude/*' -not -path '*/SourcePackages/*')

if [ "$broken" -gt 0 ]; then echo "  $broken broken link(s)"; fail=1; else echo "  ✓ all links resolve"; fi

echo "• sync-rule boundary (local vs cloud streams)"
if ./scripts/check_stream_drift.sh; then :; else fail=1; fi

# A migration that lands without `make docs` leaves the generated schema
# describing a database that no longer exists.
echo "• generated docs match their source"
tmp_schema=$(mktemp)
if ./scripts/gen_docs.sh "$tmp_schema" >/dev/null 2>&1 \
   && diff -q "$tmp_schema" docs/generated/db-schema.md >/dev/null 2>&1; then
  echo "  ✓ docs/generated/db-schema.md"
else
  echo "  ✗ docs/generated/db-schema.md is stale — run \`make docs\` and commit it"
  fail=1
fi
rm -f "$tmp_schema"

# A finished plan left in active/ is how the roadmap goes quietly wrong.
echo "• active plans are actually active"
claimed_done=$(grep -lE '^- \*\*Status:\*\*.*\bdone\b' docs/exec-plans/active/*.md 2>/dev/null || true)
if [ -n "$claimed_done" ]; then
  echo "$claimed_done" | sed 's/^/  ✗ says done but sits in active\/: /'
  fail=1
else
  echo "  ✓ none claims it is done"
fi
cutoff=$(date -v-7d +%F 2>/dev/null || date -d '7 days ago' +%F)
for md in docs/exec-plans/active/*.md; do
  [ -e "$md" ] || continue
  newest=$(grep -oE '2[0-9]{3}-[0-9]{2}-[0-9]{2}' "$md" | sort | tail -1)
  [ -z "$newest" ] && continue
  # `<` on ISO dates is a string compare, which is what makes it a date compare.
  [ "$newest" \< "$cutoff" ] && echo "  ! $md — newest date stamp $newest; still active?"
done

# A stray blank line inside a markdown table splits it in two, and every table
# after the first renders headerless — 19 rows of a 58-row tracker vanished
# this way. A duplicated area in the standing table is the other half: two
# grades for one thing, and the older one wins the eye.
echo "• table integrity"
table_integrity() {   # $1 = file, $2 = optional heading to scope to
  local f="$1" body first last gaps
  if [ -n "${2:-}" ]; then body=$(sed -n "/^$2/,\$p" "$f"); else body=$(cat "$f"); fi
  first=$(printf '%s\n' "$body" | grep -n '^|' | head -1 | cut -d: -f1)
  last=$(printf '%s\n' "$body" | grep -n '^|' | tail -1 | cut -d: -f1)
  [ -z "$first" ] && { echo "  ✗ $f: no table found"; return 1; }
  gaps=$(printf '%s\n' "$body" | sed -n "${first},${last}p" | grep -cv '^|')
  if [ "$gaps" -gt 0 ]; then
    echo "  ✗ $f: $gaps line(s) inside the table are not rows — it renders as several tables"
    return 1
  fi
  echo "  ✓ $f"
}
table_integrity docs/exec-plans/tech-debt-tracker.md || fail=1
table_integrity ARCHITECTURE.md '## Where each area stands' || fail=1
dupes=$(sed -n '/^## Where each area stands/,$p' ARCHITECTURE.md | grep '^| ' \
  | cut -d'|' -f2 | sed 's/^ *//;s/ *$//' | grep -v '^Area$' | sort | uniq -d)
if [ -n "$dupes" ]; then
  echo "$dupes" | sed 's/^/  ✗ graded twice in the standing table: /'
  fail=1
else
  echo "  ✓ no area graded twice"
fi

# An ADR nobody can find from the index is a decision that gets re-made.
echo "• every ADR is linked from the design-docs index"
unlinked=0
for adr in docs/decisions/*.md; do
  grep -q "$(basename "$adr")" docs/design-docs/index.md || {
    echo "  ✗ $adr not linked from docs/design-docs/index.md"; unlinked=$((unlinked + 1)); }
done
[ "$unlinked" -gt 0 ] && fail=1 || echo "  ✓ all $(ls docs/decisions/*.md | wc -l | tr -d ' ') linked"

# A current-state doc thick with dates has stopped describing the system and
# started narrating its history (docs/README.md rule 1). Warn, never fail:
# the append-only records below are excluded because dates ARE their content.
echo "• date density in current-state docs (warn)"
while IFS= read -r md; do
  case "$md" in
    # ADRs and plans (a decision log is dated by the template), plus the two
    # append-only operational records.
    ./docs/decisions/*|./docs/exec-plans/active/*|./docs/exec-plans/completed/*) continue ;;
    ./docs/cloud-setup.md|./docs/release.md) continue ;;
  esac
  lines=$(wc -l < "$md" | tr -d ' ')
  [ "$lines" -lt 20 ] && continue
  dates=$(grep -oE '2[0-9]{3}-[0-9]{2}-[0-9]{2}' "$md" | wc -l | tr -d ' ')
  [ $((dates * 20)) -gt "$lines" ] && echo "  ! $md — $dates dates in $lines lines"
done < <( { find ./docs -name '*.md'; printf './%s\n' AGENTS.md ARCHITECTURE.md README.md; } | sort)

echo
[ "$fail" -eq 0 ] && echo "docs-check: OK" || { echo "docs-check: FAILED"; exit 1; }
