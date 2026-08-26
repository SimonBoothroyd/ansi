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
- `datasets/extraction/` — page/photo fixtures with expected structured output
  (added later; extraction is roadmap step 8).
- `runner/run.sh` — scores normalization now; reports the matching set as ready
  but unscored until the engine exists. Wired into `make evals` and the nightly
  workflow.

## Run

```
make evals        # or: cd evals && ./runner/run.sh
```
