# Extraction / provider benchmark (lane D)

Turns "which provider" into evidence, and is where the transcription + ①
sanitize prompts are developed. Scores **Gemini Flash / GPT-5 Mini / Claude
Haiku** on the blessed gold (`datasets/extraction/gold/`, the oracle —
read-only) per-stage and per-path, with a never-invent ledger as the
disqualifying dimension.

Contract: `docs/exec-plans/active/0018-import-benchmark.md` (charter) +
`0014-import-foundation.md` (frozen `ExtractAdapter` / `ExtractionResult`).

## Files

| File                                                         | Role                                                                                                                |
| ------------------------------------------------------------ | ------------------------------------------------------------------------------------------------------------------- |
| `supabase/functions/_shared/adapters/{claude,gemini,gpt}.ts` | The three provider adapters behind the frozen `ExtractAdapter` (native structured output; vocab-blind, unit-aware). |
| `supabase/functions/_shared/adapters/mock.ts`                | Keyless reference adapter — makes the harness self-test with no key.                                                |
| `supabase/functions/_shared/adapters/schema.ts`              | The one structured-output JSON Schema + coercion + structural never-invent validation.                              |
| `supabase/functions/_shared/prompts/extraction.ts`           | The transcription prompt and the ① sanitize prompt.                                                                 |
| `runner/fixtures.ts`                                         | Gold loader, the unit-hint set, and the gold → source-text renderer (the D2 input).                                 |
| `runner/score_extraction.ts`                                 | Programmatic scorers + ledger + calibration + LLM-judge seam; keyless mock CLI.                                     |
| `runner/run_extraction_live.ts`                              | The live provider compare (needs keys).                                                                             |
| `runner/score_extraction.test.ts`                            | Keyless self-test (oracle → perfect; degraded → ledger fires).                                                      |

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
`recipe_urls.txt` pages via lane A's `jsonld.ts`). The web paths are wired but
gated on lane A (`blobFromUrl` seam in `run_extraction_live.ts`).

## Scoring rubric

All programmatic except the last. Line-level metrics are computed after a fuzzy
alignment of the model's line items onto the gold's (token-Jaccard over §7
`normalize`d ingredient text, greedy best-first, threshold 0.34).

| Metric                           | Definition                                                                                                                                           |
| -------------------------------- | ---------------------------------------------------------------------------------------------------------------------------------------------------- |
| **json-valid rate**              | Fraction of cases the adapter returned a coercible `ExtractionResult` for (a parse error ⇒ invalid ⇒ that case scores 0).                            |
| **line P / R / F1**              | Precision/recall of aligned line items (extras = hallucinated lines; misses = omissions).                                                            |
| **qty accuracy**                 | Over aligned pairs: qty (or the qty_low/qty_high range) matches within tolerance, and the amount _shape_ agrees (single vs range vs none).           |
| **unit accuracy**                | Over aligned pairs: unit string equal (case-folded) **and** `unit_mappable` equal.                                                                   |
| **§7 normalize-agreement**       | Over aligned pairs: `normalize(got) === normalize(gold)` — the ingredient identity survives to the same match-text.                                  |
| **servings**                     | `servings_base` exact (null-safe).                                                                                                                   |
| **time total / cook**            | `TimeField` equality (null-safe, range-aware).                                                                                                       |
| **step-ref F1**                  | Multiset match of step `ref` tokens, with the model's flattened line indices remapped through the line alignment.                                    |
| **timer F1**                     | Multiset match of `timer` tokens (low/high seconds).                                                                                                 |
| **calibration ECE**              | Expected calibration error of per-line `confidence` vs actual (qty+unit) correctness, 10 bins. A calibration tool, not a gate.                       |
| **prose fidelity** _(LLM-judge)_ | Keyed only. Judges whether step **text** spans faithfully preserve the source prose — the one dimension not mechanically checkable. Keyless ⇒ `n/a`. |

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

Keyless (mock — plumbing + scorer + ledger self-check; part of `make evals`):

```
cd evals && ./runner/run.sh
# or just the extraction scorer:
deno run --allow-read --allow-env runner/score_extraction.ts
deno test --allow-read --allow-env runner/score_extraction.test.ts
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

## Pinned model IDs

| Provider     | Model id           | Vision | Native structured output                               | Source                                         |
| ------------ | ------------------ | ------ | ------------------------------------------------------ | ---------------------------------------------- |
| Claude Haiku | `claude-haiku-4-5` | yes    | `output_config.format` `json_schema` (Messages API)    | `claude-api` reference                         |
| Gemini Flash | `gemini-2.5-flash` | yes    | `generationConfig.responseSchema` + `responseMimeType` | provider knowledge — re-confirm before compare |
| GPT-5 Mini   | `gpt-5-mini`       | yes    | `response_format: json_schema` (Chat Completions)      | provider knowledge — re-confirm before compare |

Override any id via the adapter's `model` option or by editing the exported
constant. Only the Claude id/behaviour was pinned against the `claude-api`
reference (Anthropic-only); the Gemini/GPT ids come from general provider
knowledge and should be re-confirmed against each vendor's docs at the compare
step.
