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
  choice/compound lines carry several candidates. Scored once the cascade lands
  (step 8). Regenerate after re-mining or editing the vocab:
  `deno run --allow-read --allow-write runner/gen_matching_cases.ts`.
- `datasets/extraction/gold/` — the blessed structured gold (the oracle, 11
  labelled recipes; read-only). The source photos live in `images/` and are
  gitignored (copyright + EXIF). Scored by the extraction / provider benchmark
  (lane D) — see `runner/EXTRACTION.md` for the rubric, stages (D1/D2/D3),
  paths, and the never-invent ledger.
- `runner/run.sh` — scores normalization + the extraction D2 stage (keyless mock)
  now; reports the matching set as ready but unscored until the engine exists.
  Wired into `make evals` and the nightly workflow.

## Run

```
make evals        # or: cd evals && ./runner/run.sh
```
