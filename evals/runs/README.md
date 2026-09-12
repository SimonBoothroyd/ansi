# evals/runs — persisted provider runs (LOCAL ONLY)

Each subdirectory is one paid benchmark run:

```
<yyyy-mm-dd>-<label>/
  manifest.json           label, timestamp, runner git rev, per-provider pinned
                          model + the dated pricing row it was costed with
  <provider>/<case>.json  the provider's VERBATIM response, plus normalized
                          token usage, latency, and the exact rendered input
                          (text + sha256)
```

**These are gitignored, and kept.** `evals/reports/` is ignored because it is
derived — regenerable from the datasets for free. A run directory is the
opposite: it is the thing the run *bought*, and re-creating one means paying the
providers again — but it is also a model's verbatim reading of copyrighted
pages, so it lives on the machine that made it, never in the repo. Back the
directory up with the photos and the gold.

Because the raw response is kept verbatim, a scorer fix, a gold correction or a
brand-new metric costs nothing:

```
cd evals
deno run --allow-read runner/score_extraction.ts --rescore runs/<dir>
```

That decodes every saved response through the same adapter decoder the live call
used and scores it with today's scorer — zero API calls, no key. If a gold edit
changed the text a case was rendered from, the rescore says so (`INPUT DRIFT`)
rather than quietly grading the model on input it never saw.

Full workflow, cost columns and how to add a model: `../runner/EXTRACTION.md`.

## A discontinuity: runs dated before 2026-09-04

Every run directory dated before **2026-09-04** was prompted with an eval-local
copy of the unit hints that had drifted from the set production sends: it
offered the model `splash`, `drizzle` and `glug` as imprecise units, and it
withheld the size words `big` and `tiny`. Those hints are interpolated straight
into the extraction system prompt, so the provider comparison that chose the
pinned model — including the line-F1 numbers — was measured on a prompt that
never shipped.

`fixtures.ts` now imports `deriveUnitHints()`, so a later run is measuring the
real prompt. **The two sets of numbers are not comparable.** The owner chose
not to re-run: the choice still stands on what was measured, and the runs cost
real money. Read an earlier run as evidence about that older prompt, and
compare like with like.
