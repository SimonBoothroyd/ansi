#!/usr/bin/env bash
# Mechanical knowledge-base check (hobby-scale "doc-gardening"):
#   1. required harness files exist
#   2. every relative markdown link resolves to a real file
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

echo
[ "$fail" -eq 0 ] && echo "docs-check: OK" || { echo "docs-check: FAILED"; exit 1; }
