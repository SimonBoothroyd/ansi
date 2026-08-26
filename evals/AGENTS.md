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
datasets/normalization/cases.jsonl  raw → expect_normalized (HAND-labelled)
datasets/matching/cases.jsonl       raw → expect_match|candidates + band
datasets/extraction/                page/photo fixtures + expected output
runner/score_normalization.ts       scores the normalization dimension
runner/gen_matching_cases.ts        (re)builds the matching set from the vocab
runner/run.sh                       runs the scorers
```

The two `cases.jsonl` differ on purpose. **Normalization is hand-labelled** —
its expected outputs must be written independently, since grading `normalize`
against `normalize(raw)` proves nothing. **Matching is generated** from the
curated household vocabulary (`supabase/seed/vocab.jsonl`), which is the human
oracle for "what should this line resolve to"; regenerate it after re-mining or
editing the vocab.

Add a hand case whenever you hit a real mis-match — the dataset is how taste gets
captured and defended over time.
