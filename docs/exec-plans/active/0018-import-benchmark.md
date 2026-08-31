# Exec plan: Import — Lane D, extraction/provider benchmark + prompts

- **Status:** active
- **Roadmap step:** Step 8 — import (lane D of the W0 DAG)
- **Created:** 2026-08-30
- **Contract:** frozen in [0014](./0014-import-foundation.md) · `ExtractAdapter` +
  `ExtractionResult` in `supabase/functions/_shared/types.ts` · gold + schema in
  `evals/datasets/extraction/gold/` · eval harness `evals/`

## Goal

Turn "which provider" into **evidence**, and develop the extraction prompts in the
same harness. Score **Gemini Flash / GPT-5 Mini / Claude Haiku** on the blessed gold
+ the web corpus, per-stage and per-path, and output a provider recommendation with
numbers. This lane also **owns the transcription + ① sanitize prompts** the tail wires in.

> Load the **`claude-api`** skill/reference before writing any Claude adapter — pin
> exact model IDs and confirm each provider's **vision + native structured-output**
> support; do not answer from memory. "Claude Haiku" = the Haiku tier.

## Deliverables

1. `supabase/functions/_shared/adapters/{gemini,gpt,claude}.ts` — each implements the
   frozen `ExtractAdapter` (`transcribe?` + `sanitize`) via the provider's **native
   structured-output** mode. Ingredient-vocab-blind; unit-aware (consume `UnitHints`).
   Keys via env; **mockable** (a reference/fake adapter for keyless runs).
2. The **prompts**: a faithful-transcription prompt (image → `RawBlob.text`) and the
   ① **sanitize·structure·align** prompt (text → `ExtractionResult`), developed against
   the gold. Enforce **never-invent** and the §4.6 alignment rules in-prompt.
3. `evals/datasets/extraction/` wiring — inputs: the 12 photos (local, gitignored) +
   the 36 `recipe_urls.txt` pages (via lane A's `jsonld`); expected: `gold/`.
4. `evals/runner/score_extraction.ts` — **programmatic** scorers (line P/R after fuzzy
   align, qty/unit correctness, servings, §7 normalize-agreement, JSON-valid rate, the
   **hallucination / force-fit ledger**, confidence calibration) + an **LLM-judge** for
   prose fidelity only. Report **per-stage** (D1 transcribe / D2 sanitize on gold text /
   D3 e2e) and **per-path** (jsonld / page_text / photo). Run on-demand + nightly
   (`evals/.github`-style workflow); calibration tool, not a merge gate.

## Boundaries

- **Real API keys only at the compare step** — Simon provides them; signal when ready.
  Harness + scorers + gold-scoring build and self-test against the mock adapter without keys.
- **Never mutate `gold/`** — it is the oracle. Read-only here.
- Provider adapters must reject/flag hallucinated output (never-invent is scored, disqualifying).

## Done when

The three adapters implement `ExtractAdapter`; the runner scores at least D2 on the
gold with the mock adapter (keyless) and is ready to run all three on a key; a
provider-comparison **report** (scorecard: fidelity + dangerous-failures ledger +
latency; cost as tiebreak) is produced once keys land.
