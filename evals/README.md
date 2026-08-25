# Eval harness

Golden-case evaluation for the import + matching pipeline. Datasets are
checked-in, versioned artifacts — the same way the OpenAI harness treats
evaluation harnesses as first-class repo content.

- `datasets/matching/cases.jsonl` — each line: a raw ingredient line, the
  expected normalized form, and the expected match/band. Grow this from real
  mistakes.
- `datasets/extraction/` — page/photo fixtures with expected structured output
  (added later; extraction is roadmap step 8).
- `runner/run.sh` — runs the cases and prints a score. STUB until the engine
  exists; wired into `make evals` and the nightly workflow.

## Run

```
make evals        # or: cd evals && ./runner/run.sh
```
