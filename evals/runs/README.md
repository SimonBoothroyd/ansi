# evals/runs — persisted provider runs (COMMITTED)

Each subdirectory is one paid benchmark run:

```
<yyyy-mm-dd>-<label>/
  manifest.json           label, timestamp, runner git rev, per-provider pinned
                          model + the dated pricing row it was costed with
  <provider>/<case>.json  the provider's VERBATIM response, plus normalized
                          token usage, latency, and the exact rendered input
                          (text + sha256)
```

**These are tracked on purpose.** `evals/reports/` is gitignored because it is
derived — regenerable from the datasets for free. A run directory is the
opposite: it is the thing the run *bought*. Re-creating one means paying the
providers again.

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
