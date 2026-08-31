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
- **Extraction** — page/photo fixtures → structured lines, against the blessed
  gold, with a never-invent ledger as the disqualifying dimension.

All three are scored by `runner/run.sh`, keyless. The paid provider compares are
separate, on-demand runners.

## Structure

```
deno.json                           mirrors the functions import map (no --config needed)
datasets/normalization/cases.jsonl  raw → expect_normalized (HAND-labelled)
datasets/matching/cases.jsonl       raw → expect_match|candidates + band (GENERATED)
datasets/extraction/gold/*.json     the blessed structured gold (the oracle)
datasets/extraction/gold/_SCHEMA.md the gold contract + every owner ruling
datasets/extraction/gold/_INDEX.md  per-file confidence, rulings, what is open
datasets/extraction/images/         the 12 source photos (GITIGNORED)
reports/                            capture_d2_report.ts output (GITIGNORED)
runner/run.sh                       runs every keyless scorer (make evals)
runner/score_normalization.ts       scores the normalization dimension
runner/gen_matching_cases.ts        (re)builds the matching set from the vocab
runner/score_matching.ts            scores the band cascade over that set
runner/fixtures.ts                  gold loader, unit hints, gold → source text
runner/score_extraction.ts          extraction scorers + ledger + calibration
runner/score_extraction.test.ts     the scorers' own self-tests (run in run.sh)
runner/run_extraction_live.ts       live provider compare (needs keys)
runner/capture_d2_report.ts         per-line Claude-vs-GPT HTML report (needs keys)
runner/EXTRACTION.md                the extraction rubric, stages, paths, ledger
```

**Score honestly.** The scorers grade every number this harness reports, so they
are themselves tested in `run.sh`. Two standing rules, both learned the hard way
(see `runner/EXTRACTION.md`): headline field accuracies use the **gold**
denominator — a line the model dropped is a line it got wrong, never a line that
silently leaves the denominator — and a metric with nothing to measure (no
timers in gold **or** output) is reported as **n/a with coverage**, never as a
free 100%.

The two `cases.jsonl` differ on purpose. **Normalization is hand-labelled** —
its expected outputs must be written independently, since grading `normalize`
against `normalize(raw)` proves nothing. **Matching is generated** from the
curated household vocabulary (`supabase/seed/vocab.jsonl`), which is the human
oracle for "what should this line resolve to"; regenerate it after re-mining or
editing the vocab, or its labels go stale and the cascade takes the blame for
vocab drift.

Add a hand case whenever you hit a real mis-match — the dataset is how taste gets
captured and defended over time.
