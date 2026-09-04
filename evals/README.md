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
  case, plus usage, latency and the exact input. **Committed**, because this is
  what the money bought; `--rescore` re-scores it for free. See
  `runs/README.md`.
- `runner/pricing.ts` — the dated $/Mtok table the cost columns are computed
  from, one row per pinned model with its source URL and retrieval date.
- `runner/run.sh` — scores normalization, the scorers' own self-tests, the
  extraction D2 stage (keyless mock), and the matching bands through the real
  cascade. Wired into `make evals` and the nightly workflow. No paid calls.
- `deno.json` — mirrors `supabase/functions/deno.json`'s import map so the
  runners work from `evals/` without an explicit `--config`.

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
