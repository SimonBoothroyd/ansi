#!/usr/bin/env bash
# Eval runner. Scores each dimension that has a working engine:
#   - normalization (raw → match_text, §7) — LIVE, scored below.
#   - matching (raw → ingredient / band, §6) — pending the server-side cascade
#     (roadmap step 8); reported as not-yet-scored.
set -euo pipefail
here="$(dirname "$0")"
cases="$here/../datasets/matching/cases.jsonl"

n=$(grep -c '' "$cases" || true)
echo "eval harness: $n matching case(s) loaded from cases.jsonl"

deno run --allow-read "$here/score_normalization.ts"

echo "matching/band: engine not implemented yet (roadmap step 8) — not scored."
