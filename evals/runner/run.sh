#!/usr/bin/env bash
# Eval runner. Every dimension with a working engine is SCORED here:
#   - normalization (raw → match_text, §7) against the hand-labelled set.
#   - the scorers' own self-tests, so a miscalibrated scorer fails loudly
#     instead of quietly reporting flattering numbers.
#   - extraction D2 (sanitize on the reconstructed gold text) with the keyless
#     MOCK adapter.
#   - matching / bands (§6) through the real cascade.
#
# `evals/deno.json` re-exports the functions import map, so no --config is
# needed from here. Nothing in this script makes a paid provider call.
set -euo pipefail
here="$(dirname "$0")"

deno run --allow-read "$here/score_normalization.ts"

echo
# The scorers grade every other number in this run, so they get graded first.
# Whole-directory so a new *.test.ts is picked up without editing this script.
# `--allow-read` is required: the tests read the seed vocab and the blessed
# extraction gold, and a denied read makes a catch-and-skip test pass silently
# (the same trap documented in supabase/functions/deno.json).
deno test --allow-read --allow-env "$here/"

echo
# Extraction (§4.4) — scores D2 (sanitize on reconstructed gold text) with the
# keyless MOCK adapter: proves the harness + scorers + never-invent ledger are
# wired and green with no provider key. The live Gemini/GPT/Claude compare
# (runner/run_extraction_live.ts) needs keys and is run on demand — see
# runner/EXTRACTION.md.
deno run --allow-read --allow-env "$here/score_extraction.ts"

echo
# Matching / bands (§6) — the real cascade (_shared/match.ts + match_trgm.ts)
# over the generated calibration set. Calibration, not a gate: it reports band
# precision/recall against BAND_AUTO_MIN / BAND_SUGGEST_MIN and never fails.
deno run --allow-read "$here/score_matching.ts"
