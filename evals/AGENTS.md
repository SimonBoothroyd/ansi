# AGENTS.md — evals

Overrides/extends the root `AGENTS.md` for `evals/`.

The import/matching pipeline is the app's hardest correctness problem, so it gets
an eval harness (import-and-matching.md §11). The eval is a **calibration tool,
not a merge gate** — it tunes the score-band thresholds and catches regressions;
it runs on demand and nightly (`.github/workflows/evals.yml`), not on every PR.

## What gets evaluated

- **Normalization** — raw ingredient text → `match_text` (§7): exact expected output.
- **Matching** — raw line → expected ingredient (or band): precision on the
  household vocabulary; used to set the ≥0.85 / 0.55–0.85 / <0.55 bands.
- **Extraction** (later) — page/photo fixtures → structured lines.

## Structure

```
datasets/matching/cases.jsonl      one golden case per line
datasets/extraction/               page/photo fixtures + expected output
runner/run.sh                      scores cases against the (server-side) engine
```

Add a case whenever you hit a real mis-match — the dataset is how taste gets
captured and defended over time.
