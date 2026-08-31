# Extraction / provider benchmark (lane D)

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
| `supabase/functions/_shared/adapters/{claude,gemini,gpt}.ts` | The three provider adapters behind the frozen `ExtractAdapter` (native structured output; vocab-blind, unit-aware). |
| `supabase/functions/_shared/adapters/mock.ts`                | Keyless reference adapter — makes the harness self-test with no key.                                                |
| `supabase/functions/_shared/adapters/schema.ts`              | The one structured-output JSON Schema + coercion + structural never-invent validation.                              |
| `supabase/functions/_shared/prompts/extraction.ts`           | The transcription prompt and the ① sanitize prompt.                                                                 |
| `runner/fixtures.ts`                                         | Gold loader, the unit-hint set, and the gold → source-text renderer (the D2 input, `notes` included).               |
| `runner/score_extraction.ts`                                 | Programmatic scorers + ledger + calibration + LLM-judge seam; keyless mock CLI.                                     |
| `runner/run_extraction_live.ts`                              | The live provider compare (needs keys). `blobFromUrl` → `_shared/jsonld.ts` for the web paths.                      |
| `runner/capture_d2_report.ts`                                | Per-line Claude-vs-GPT D2 capture → a self-contained HTML report (needs keys; `--render-only` re-renders for free). |
| `runner/score_extraction.test.ts`                            | Keyless self-test (oracle → perfect; degraded → ledger fires; every honesty rule above pinned). Part of `run.sh`.   |

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
`recipe_urls.txt` pages). The web paths run through lane A's `_shared/jsonld.ts`
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
export ANTHROPIC_API_KEY=…   # Claude Haiku
export OPENAI_API_KEY=…       # GPT-5 Mini
export GEMINI_API_KEY=…       # Gemini Flash
deno run --allow-read --allow-env --allow-net runner/run_extraction_live.ts
# optional: --providers=claude-haiku,gpt-5-mini  --stage=D2
```

A provider whose key is unset is skipped with a note, never a crash.

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
this table mirrors them.

| Provider     | Model id             | Constant              | Vision | Native structured output                               | Source                                         |
| ------------ | -------------------- | --------------------- | ------ | ------------------------------------------------------ | ---------------------------------------------- |
| Claude Haiku | `claude-haiku-4-5`   | `CLAUDE_HAIKU_MODEL`  | yes    | `output_config.format` `json_schema` (Messages API)    | `claude-api` reference                         |
| Gemini Flash | `gemini-flash-latest`| `GEMINI_FLASH_MODEL`  | yes    | `generationConfig.responseSchema` + `responseMimeType` | provider knowledge — re-confirm before compare |
| GPT-5 Mini   | `gpt-5.4-mini`       | `GPT_MINI_MODEL`      | yes    | `response_format: json_schema` (Chat Completions)      | provider knowledge — re-confirm before compare |

Override any id via the adapter's `model` option or by editing the exported
constant. Only the Claude id/behaviour was pinned against the `claude-api`
reference (Anthropic-only); the Gemini/GPT ids come from general provider
knowledge and should be re-confirmed against each vendor's docs at the compare
step.
