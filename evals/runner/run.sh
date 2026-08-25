#!/usr/bin/env bash
# Eval runner — STUB. Once the server-side match engine exists, this feeds each
# case in datasets/matching/cases.jsonl through normalize()/matchLines() and
# reports normalization accuracy + per-band precision (calibrates §6 thresholds).
set -euo pipefail
cases="$(dirname "$0")/../datasets/matching/cases.jsonl"
n=$(grep -c '' "$cases" || true)
echo "eval harness: $n matching case(s) loaded from cases.jsonl"
echo "engine not implemented yet (roadmap step 8) — nothing to score."
echo "when built: report normalization accuracy + per-band precision here."
