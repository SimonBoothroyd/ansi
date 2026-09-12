# Eval harness

Golden-case evaluation for the import + matching pipeline. Datasets are
checked-in, versioned artifacts — the same way the OpenAI harness treats
evaluation harnesses as first-class repo content.

- `datasets/normalization/cases.jsonl` — `raw → expect_normalized`.
  **Hand-labelled** and independent of `normalize`'s own output (grading it
  against `normalize(raw)` would be circular). This is scored today.
- `datasets/matching/cases.jsonl` — `raw → expect_match | expect_candidates`
  (+ `expect_band`: auto/suggest/none). Labels come from the curated household
  vocabulary via `runner/gen_matching_cases.ts` (the vocab is the oracle);
  choice/compound lines carry several candidates. **Scored** by
  `runner/score_matching.ts` through the real cascade. Regenerate after re-mining
  or editing the vocab — the labels drift when the vocab is re-curated:
  `deno run --allow-read --allow-write runner/gen_matching_cases.ts`.
- `datasets/extraction/gold/` — the blessed structured gold (the oracle, 11
  labelled recipes; read-only). The source photos live in `images/` and are
  gitignored (copyright + EXIF). Scored by the extraction / provider benchmark
  — see `runner/EXTRACTION.md` for the rubric, stages (D1/D2/D3),
  paths, and the never-invent ledger.
- `reports/` — regenerable HTML/JSON output from `runner/capture_d2_report.ts`.
  **Gitignored**: it is a rendering of a paid run, not a source artifact.
- `runs/` — the paid runs themselves: each provider's verbatim response per
  case, plus usage, latency and the exact input. **Local-only** (gitignored):
  it is a verbatim reading of copyrighted pages, and it is what the money
  bought, so keep it and `--rescore` it for free. See `runs/README.md`.
- `runner/pricing.ts` — the dated $/Mtok table the cost columns are computed
  from, one row per pinned model with its source URL and retrieval date.
- `runner/run.sh` — scores normalization, the scorers' own self-tests, the
  extraction D2 stage (keyless mock), and the matching bands through the real
  cascade. Wired into `make evals` and the nightly workflow. No paid calls.
- `deno.json` — mirrors `supabase/functions/deno.json`'s import map so the
  runners work from `evals/` without an explicit `--config`.

## Bring your own corpus

The extraction gold is not in the repo: it is a transcription of cookbook pages
the owner photographed, so it stays on his machine. A fresh clone still scores
normalization and matching (both are keyless and tracked) and reports the
extraction dimension as skipped. To score extraction yourself:

1. Photograph a few recipe pages you own, or print public-domain recipes, into
   `datasets/extraction/images/` (gitignored).
2. Label each one by hand as `datasets/extraction/gold/<slug>.json`, to the
   contract in `datasets/extraction/gold/_SCHEMA.md` — every line, its amount,
   its unit and its notes, and the method as tokens. A dozen pages is plenty;
   the value is in the labels being independent of any model's reading.
3. Run the live comparison once with your provider keys
   (`runner/run_extraction_live.ts`, see `runner/EXTRACTION.md`); it writes
   `runs/<date>-<label>/` (gitignored) and everything after that is free.

## Run

```
make evals        # or: cd evals && ./runner/run.sh
```

Everything in `run.sh` is keyless. The live provider compares
(`runner/run_extraction_live.ts`, `runner/capture_d2_report.ts`) are run on
demand and are the only things that cost money — and they now cost it **once**:
a live run saves every raw response under `runs/`, and

```
cd evals && deno run --allow-read runner/score_extraction.ts --rescore runs/<dir>
```

re-scores it with today's scorer and no API calls at all.
