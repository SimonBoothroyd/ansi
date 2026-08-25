#!/usr/bin/env bash
# Best-effort: vendor dependency docs (llms.txt where available) into
# docs/references/ so the harness has offline knowledge of key deps. Needs
# network. Commit the snapshots you want to rely on; note the fetch date.
set -euo pipefail
cd "$(dirname "$0")/../docs/references"
stamp="$(date -u +%Y-%m-%d)"
fetch () { # url outfile
  if curl -fsSL "$1" -o "$2" 2>/dev/null; then
    printf '<!-- fetched %s from %s -->\n' "$stamp" "$1" | cat - "$2" > "$2.tmp" && mv "$2.tmp" "$2"
    echo "  ✓ $2"
  else
    echo "  ✗ $1 (skipped)"
  fi
}
echo "Fetching dependency references ($stamp)…"
fetch "https://forui.dev/llms.txt"        forui-llms.txt
fetch "https://supabase.com/llms.txt"     supabase-llms.txt
# PowerSync / Riverpod: no llms.txt yet — capture the reference index pages if desired.
echo "Done. Review + commit the snapshots you want the harness to depend on."
