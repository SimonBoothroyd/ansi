# Extraction / provider benchmark

Turns "which provider" into evidence, and is where the transcription + ①
sanitize prompts are developed. Scores **Gemini Flash / GPT-5 Mini / Claude
Haiku** on the blessed gold (`datasets/extraction/gold/`, the oracle —
read-only) per-stage and per-path, with a never-invent ledger as the
disqualifying dimension.

Contract: `docs/exec-plans/completed/0018-import-benchmark.md` (charter) +
`0014-import-foundation.md` (frozen `ExtractAdapter` / `ExtractionResult`).

## Files

| File                                                         | Role                                                                                                                |
| ------------------------------------------------------------ | ------------------------------------------------------------------------------------------------------------------- |
| `supabase/functions/_shared/adapters/{claude,gemini,gpt}.ts` | The three provider adapters behind the frozen `ExtractAdapter` (native structured output; vocab-blind, unit-aware). Each also exports a pure `decode<Provider>Sanitize` — the decode path a rescore replays. |
| `supabase/functions/_shared/adapters/usage.ts`               | Per-provider token-usage parsing, normalized onto one `TokenUsage` contract.                                        |
| `supabase/functions/_shared/adapters/mock.ts`                | Keyless reference adapter — makes the harness self-test with no key. Emits deterministic fake usage.                |
| `supabase/functions/_shared/adapters/schema.ts`              | The one structured-output JSON Schema + coercion + structural never-invent validation.                              |
| `supabase/functions/_shared/prompts/extraction.ts`           | The transcription prompt and the ① sanitize prompt.                                                                 |
| `runner/fixtures.ts`                                         | Gold loader, the unit-hint set, and the gold → source-text renderer (the D2 input, `notes` included).               |
| `runner/pricing.ts`                                          | The dated $/Mtok price list, one row per model, each with its source URL + retrieval date. Checked in.              |
| `runner/run_store.ts`                                        | Persisted-run format: write/read `evals/runs/<date>-<label>/`, and replay a saved response through its decoder.     |
| `runner/score_extraction.ts`                                 | Programmatic scorers + ledger + calibration + cost + LLM-judge seam; keyless mock CLI; `--rescore`.                 |
| `runner/run_extraction_live.ts`                              | The live provider compare (needs keys). Persists raw responses. `blobFromUrl` → `_shared/jsonld.ts` for web paths.  |
| `runner/capture_d2_report.ts`                                | Per-line Claude-vs-GPT D2 capture → a self-contained HTML report (needs keys; `--render-only` re-renders for free). |
| `runner/score_extraction.test.ts`                            | Keyless self-test (oracle → perfect; degraded → ledger fires; every honesty rule above pinned). Part of `run.sh`.   |
| `runner/cost_rescore.test.ts`                                | Keyless self-test for pricing + the persist → rescore round-trip. Part of `run.sh`.                                 |

## Stages and paths

**Stages** — where in the pipeline the model sits:

- **D1 transcribe** — photo → `RawBlob.text`. No committed gold transcription
  exists, so D1 is not scored against a text oracle; its faithfulness surfaces
  through the D3 never-invent ledger and the (keyed) prose judge.
- **D2 sanitize** — text → `ExtractionResult`, scored against the gold. Run
  keyless on the reconstructed gold text (`goldToSourceText`), which puts the
  printed amount in front of the model and tests whether it _structures_ it
  correctly (never-invent included).
- **D3 e2e** — photo → transcribe → sanitize, scored against the gold. Needs a
  vision key + the local images.

**Paths** — where the input came from: `photo` (the 12 gitignored images),
`page_text` (reconstructed gold text / a web page's text), `jsonld` (the 36
`recipe_urls.txt` pages). The web paths run through `_shared/jsonld.ts`
(`fetchRawBlob` → `buildRawBlob`), wired at `blobFromUrl` in
`run_extraction_live.ts`. There is no structured gold for those 36 pages, so
they are an **input** corpus for the ledger and the prose judge, not a scored
oracle; the scored rows are the 11 gold recipes.

### The D2 input (what the model actually sees)

`goldToSourceText` reconstructs a printed page from the gold. Three rules keep it
a fair test rather than a friendly one:

- **`notes` is emitted.** The cook-prep half of a line ("destemmed and roughly
  chopped", "for garnish") is roughly a third of the gold's line content. It used
  to be dropped, which meant the model was never shown the text it is graded on
  splitting out — `notes` was structurally unscoreable.
- **No normalized-token leak.** A gold line with no `raw_amount` renders printed
  prose ("1 red bell pepper", "2 teaspoons salt"), never the structured
  `"1 piece"` — that would hand over our unit vocabulary.
- **No double-print.** When the printed amount already spells the identity
  ("Juice of 1 lemon"), it is not repeated, and a note that merely restates the
  amount (", juiced") is dropped.

## Scoring rubric

All programmatic except the last. Line-level metrics are computed after a fuzzy
alignment of the model's line items onto the gold's (token-Jaccard over §7
`normalize`d ingredient text, greedy best-first, threshold 0.34).

**The headline denominator is the GOLD line count, not the aligned pairs.** A
line the model omitted is a line it got wrong, so it counts against qty / unit /
normalize / notes. Scoring over aligned pairs alone let a model raise its
accuracy by dropping the lines it was least sure of. The aligned-only reading is
still printed, explicitly labelled, next to a **line-weighted (micro)**
aggregate — the per-recipe macro treats an 8-line recipe and a 34-line recipe
equally, the micro does not.

| Metric                           | Definition                                                                                                                                                       |
| -------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------ |
| **json-valid rate**              | Fraction of cases the adapter returned a coercible `ExtractionResult` for (a parse error ⇒ invalid ⇒ that case scores 0).                                        |
| **line P / R / F1**              | Precision/recall of aligned line items (extras = hallucinated lines; misses = omissions).                                                                        |
| **qty accuracy**                 | qty (or the qty_low/qty_high range) matches within tolerance and the amount _shape_ agrees (single vs range vs none). Over the gold denominator.                 |
| **unit accuracy**                | Unit agreement (see the unit rule below) **and** `unit_mappable` equal. Over the gold denominator. `unit exact` is the strict string reading, reported beside it. |
| **§7 normalize-agreement**       | `normalize(got) === normalize(gold)` — the ingredient identity survives to the same match-text. Over the gold denominator.                                        |
| **notes agreement**              | Cook-prep survived into the note slot (see the notes rule below). Over the gold denominator.                                                                     |
| **servings**                     | `servings_base` exact (null-safe).                                                                                                                               |
| **time total / cook**            | `TimeField` equality (null-safe, range-aware).                                                                                                                   |
| **step-ref F1**                  | Multiset match of step `ref` tokens, with the model's flattened line indices remapped through the line alignment. **n/a recipes excluded** (see below).           |
| **timer F1**                     | Multiset match of `timer` tokens (low/high seconds). **n/a recipes excluded** (see below).                                                                       |
| **calibration ECE**              | Expected calibration error of per-line `confidence` vs actual (qty+unit) correctness, 10 bins. A calibration tool, not a gate.                                    |
| **prose fidelity** _(LLM-judge)_ | Keyed only. Judges whether step **text** spans faithfully preserve the source prose — the one dimension not mechanically checkable. Keyless ⇒ `n/a`.             |
| **$/import · $/100 imports**     | Total token cost over the scored recipes, divided by the number of imports. Priced from `runner/pricing.ts` (see "Cost" below). Unpriced model ⇒ `n/a`, never `$0`. |

### The comparison rules

- **Numbers (`numEq`).** Equal within `max(0.006 absolute, 0.2% relative)`. The
  absolute term lets a rounded vulgar fraction pass (gold `⅓ → 0.33` vs a model's
  `0.3333`); the tiny relative term only absorbs float noise. The previous 2%
  relative tolerance scored `400 g` vs `395 g`, and `30 min` vs `29 min`, as hits.
- **Units.** Three grades. `exact` — same case-folded unit after singularizing a
  measure noun and folding `tin → can`, with `unit_mappable` equal. `family` —
  the **generic** count unit `piece` against a **specific** count-measure noun
  (`clove`, `sprig`, `can`, `head`, `loaf`, `block`, `slice`, `bunch`, `stalk`),
  `unit_mappable` still equal: "2 garlic cloves" read as `2 piece` is a labelling
  choice inside one family, and this was the largest single source of the
  residual unit-accuracy gap. `mismatch` — everything else, including two
  different specific nouns (`clove` vs `can`) and **any** `unit_mappable`
  disagreement, because a forced mapping is a ledger event, not a near-miss. The
  headline counts `exact` + `family`; `unit exact` counts only `exact`. The
  measure-noun list mirrors `_shared/unit_hints.ts` and the gold's
  `_SCHEMA.md` "count-measure nouns are mappable" rule.
- **Notes.** Lowercase, split on non-alphanumerics, drop the stopwords
  (`a an the of and or to into with if then in on at is it`), compare the two
  token **sets** by Jaccard. Both empty ⇒ agree; exactly one empty ⇒ disagree;
  otherwise agree at Jaccard ≥ 0.6. That tolerates word order and punctuation
  ("chopped, for garnish" ≡ "for garnish, chopped") but not a dropped qualifier
  ("finely diced" vs "diced" scores 0.5 and fails).
- **Empty sets.** A recipe with no timers in the gold **and** none in the output
  proves nothing about timer extraction, so it is **excluded** from the timer
  macro instead of collecting a free 1.0 — same for step-refs. Each metric prints
  its coverage (the fraction of recipes it actually covers). A gold-empty /
  model-non-empty case is still scored, at 0.
- **Calibration composition.** ECE is over the whole gold, not the aligned
  subset: an **invented** line enters at the model's own confidence with
  `correct: false` (a confident hallucination must cost something), and an
  **omitted** line enters at confidence 0. Omissions therefore barely move ECE —
  the honest headline for that failure mode is the ledger's `omitted_lines` and
  the gold-denominator accuracies, which is why the sample composition
  (`aligned / invented / omitted`) is printed next to the number.

### The never-invent / force-fit ledger (disqualifying)

The dangerous-failure dimension — a provider that scores well but invents is
disqualified. Counts, per case, summed per provider:

- `invented_lines` — a model line matching no gold line.
- `omitted_lines` — a gold line the model dropped (recorded, not counted in the
  dangerous total).
- `invented_qty` — gold had no amount, the model put a number in.
- `collapsed_range` — gold was a range, the model force-fit a single number.
- `forced_unit` — gold amount was unmappable, the model mapped it to a unit.
- `invented_time` / `invented_servings` / `invented_timers` — a recipe-level
  value the source doesn't carry.

Adapters additionally self-flag structural inconsistencies
(`validateExtractionResult`) into `parse_warnings`; the scorer counts those too.

## Run

All commands below are run **from `evals/`**. `evals/deno.json` re-exports the
functions import map, so no `--config` flag is needed; if you run a runner from
somewhere else, add `--config supabase/functions/deno.json` (the adapters import
`imagescript`, which fails to resolve without an import map).

Keyless (mock — plumbing + scorer + ledger self-check; part of `make evals`):

```
cd evals && ./runner/run.sh
# or the pieces:
deno test --allow-read --allow-env runner/score_extraction.test.ts
deno run  --allow-read --allow-env runner/score_extraction.ts
```

Live compare (needs keys; run on demand once Simon provides them):

```
source ../.env.local          # ANTHROPIC_API_KEY / OPENAI_API_KEY / GEMINI_API_KEY
deno run --allow-read --allow-write --allow-env --allow-net --allow-run=git \
  runner/run_extraction_live.ts --label=first-compare
# optional: --providers=claude-haiku,gpt-5-mini  --stage=D2  --no-persist
```

A provider whose key is unset is skipped with a note, never a crash.
`--allow-write` + `--allow-run=git` are for the run artifact below; without
`--allow-run` the run still saves, with `git_rev: "unknown"`.

## Cost, and never paying twice

The benchmark reports **dollars beside accuracy**, and a paid run is saved so it
can be re-scored for free. Three pieces:

**1. Usage capture.** `ExtractAdapter` carries an optional `onCall` observer
(`_shared/types.ts`). The edge function never sets it and is unaffected; the
runner sets it and receives, per call, the provider's **verbatim response**, its
token usage, and the latency. `_shared/adapters/usage.ts` normalizes the three
vendors' disagreeing usage blocks onto one contract:

- `input_tokens` is **uncached, non-cache-write** billable input. Anthropic
  already excludes cache tokens from `input_tokens`; OpenAI and Gemini fold them
  in, so the parsers subtract.
- `output_tokens` **includes** reasoning/thinking, which every vendor bills at
  the output rate — Gemini reports `thoughtsTokenCount` outside
  `candidatesTokenCount`, so it is added in; OpenAI's reasoning is already
  inside `completion_tokens`, so it is not.
- A field the provider did not report stays `null`, never `0`, and a cost
  computed over one is flagged as a **lower bound**.

**2. Pricing.** `runner/pricing.ts` is a checked-in, dated table: $/Mtok input /
output / cache-read (+ cache-write where billed), one row per exact model id,
each row carrying the vendor URL it came from and the date it was read. It is
checked in rather than fetched because a run is a dated artifact — fetching at
score time would silently re-price an old run at today's rates. A model with no
row costs `n/a`, never `$0.00`.

**3. Persisted runs → `--rescore`.** A live run writes

```
evals/runs/<yyyy-mm-dd>-<label>/manifest.json          label, time, git rev, models + price rows
evals/runs/<yyyy-mm-dd>-<label>/<provider>/<case>.json raw response + usage + latency + exact input
```

Those files are **kept, locally** — gitignored like the photos and the gold,
because a raw response is the model's verbatim reading of a copyrighted page.
`evals/reports/` is ignored because it is derived; a run directory is the
opposite: it is what the run *bought*, so back it up with the corpus.
Failed cases are saved too (a run keeping only its successes cannot be re-scored
honestly — the failures are the json-valid rate). Then:

```
deno run --allow-read runner/score_extraction.ts --rescore runs/<yyyy-mm-dd>-<label>
```

replays every saved response through the **same** adapter decoder the live call
used and scores it with today's scorer — zero API calls, no key. So a scorer
fix, a gold correction or a brand-new metric costs nothing after the first run.

Two guards keep a rescore honest: each saved case stores the sha256 of the exact
text the provider saw, so a gold edit that changed the rendered input is
reported as **INPUT DRIFT** rather than silently graded as if the model had seen
the new text; and a case whose gold no longer exists is reported as an
**orphan** rather than scored as a total miss (which would look identical to a
model that failed it).

The persist → rescore round-trip is self-tested keyless in
`runner/cost_rescore.test.ts`: a fake run written from the MockAdapter must
rescore to byte-identical headline numbers.

### Adding a model

1. Pin its **exact** id in the adapter constant (`GPT_MINI_MODEL`,
   `GEMINI_FLASH_MODEL`, `CLAUDE_HAIKU_MODEL`) — never an alias like `-latest`
   or `-preview`, which re-points under you and makes two dated runs
   incomparable. Confirm the id against the vendor's own model-list endpoint
   (`GET /v1/models`, `GET /v1beta/models`), not from memory.
2. Add a `runner/pricing.ts` row keyed by that exact id, with `source` and
   `retrieved`.

That is the whole change — nothing else keys off the model string, and
`cost_rescore.test.ts` fails if a pinned model has no price row.

Per-line Claude-vs-GPT capture → a self-contained HTML report (needs the two
keys; `source ../.env.local` first):

```
deno run --allow-read --allow-write --allow-env --allow-net \
  runner/capture_d2_report.ts
# re-render the HTML from the saved JSON dump — no API calls, no keys:
deno run --allow-read --allow-write --allow-env --allow-net \
  runner/capture_d2_report.ts --render-only
```

(`--allow-net` is needed even for `--render-only`: the adapters pull
`imagescript`, whose wasm loads at import time. No provider is called.)

It writes `evals/reports/extraction-d2-compare.{html,json}`. Those reports are
**regenerable output and gitignored** — `--render-only` re-renders the HTML from
the saved JSON dump for free, so iterate on the layout without paying for the
run again.

## Pinned model IDs

Ids come from the adapters' exported constants — those are the source of truth;
this table mirrors them. All three were confirmed on **2026-08-31** against each
vendor's own model-list endpoint (a free call), not from memory.

| Provider     | Model id           | Constant             | Vision | Native structured output                               | Confirmed against                                       |
| ------------ | ------------------ | -------------------- | ------ | ------------------------------------------------------ | ------------------------------------------------------- |
| Claude Haiku | `claude-haiku-4-5` | `CLAUDE_HAIKU_MODEL` | yes    | `output_config.format` `json_schema` (Messages API)    | `GET api.anthropic.com/v1/models` + `claude-api` ref     |
| Gemini Flash | `gemini-3.5-flash` | `GEMINI_FLASH_MODEL` | yes    | `generationConfig.responseSchema` + `responseMimeType` | `GET generativelanguage.googleapis.com/v1beta/models`    |
| GPT (budget) | `gpt-5.6-luna`     | `GPT_MINI_MODEL`     | yes    | `response_format: json_schema` (Chat Completions)      | `GET api.openai.com/v1/models` + developers.openai.com   |

Notes on the two that moved:

- **`gemini-flash-latest` → `gemini-3.5-flash`.** The old pin was an **alias**.
  Aliases re-point silently, which makes two dated benchmark runs
  incomparable — the whole reason the 0018 convention says exact ids. The
  models list reports `gemini-3.5-flash` at version `3.5-flash-05-2026`.
- **`gpt-5.4-mini` → `gpt-5.6-luna`.** The GPT-5.6 family renamed its tiers:
  `sol` (flagship, $4/$20), `terra` (mid, $2/$12), `luna` (budget, $0.20/$1.20).
  `luna` is the successor to the `-mini` tier and the one that matches this
  project's flash-tier framing. There is no dated `gpt-5.6-luna-YYYY-MM-DD`
  snapshot in the models list, so that string *is* the exact pin.

Claude stays on `claude-haiku-4-5`, and that string **is** the complete pin —
the Haiku 4.5 id carries no date suffix and is not an alias that re-points. A
newer Haiku generation would arrive under a different id, which is an edit to
`CLAUDE_HAIKU_MODEL` and therefore a re-run of this eval.

Alternatives the owner may prefer, all already priced in `runner/pricing.ts` so
a swap is a one-line change: `gemini-3.7-flash` (newer than the pinned 3.5 and
currently *cheaper* at a promotional $0.75/$3.75 through 2026-12-31),
`gemini-3.6-flash` (same price), `gemini-3.5-flash-lite` ($0.30/$2.50), and
`gpt-5.4-mini` ($0.75/$4.50, the previous pin).

Override any id via the adapter's `model` option or by editing the exported
constant.

## Prices (per 1M tokens, read 2026-08-31)

Mirrors `runner/pricing.ts`, which is the source of truth.

| Model                   | Input        | Output       | Cache read | Cache write | Source                                            |
| ----------------------- | ------------ | ------------ | ---------- | ----------- | ------------------------------------------------- |
| `claude-haiku-4-5`      | $1.00        | $5.00        | $0.10      | $1.25 (5m)  | platform.claude.com/docs/en/about-claude/pricing  |
| `gpt-5.6-luna`          | $0.20        | $1.20        | $0.02      | n/a         | developers.openai.com/api/docs/pricing            |
| `gemini-3.5-flash`      | $1.50        | $9.00        | $0.15      | n/a         | ai.google.dev/gemini-api/docs/pricing             |
| `gemini-3.7-flash` \*   | $0.75        | $3.75        | $0.075     | n/a         | ai.google.dev/gemini-api/docs/pricing             |
| `gemini-3.5-flash-lite` | $0.30        | $2.50        | $0.03      | n/a         | ai.google.dev/gemini-api/docs/pricing             |
| `gpt-5.4-mini`          | $0.75        | $4.50        | $0.075     | n/a         | developers.openai.com/api/docs/pricing            |

\* promotional through 2026-12-31, then $1.50 / $7.50.

On these rates the pinned trio is **not** the cheap trio it looks like: at equal
token counts Gemini 3.5 Flash is ~7.5× GPT-5.6 Luna on input and ~7.5× on
output, and Claude Haiku ~5×/~4×. That spread is exactly what the `$/import`
column exists to surface next to the accuracy numbers.
