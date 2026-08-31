# Exec plan: Import — Lane A, deterministic extraction + orchestration

- **Status:** done — all three deliverables shipped (`_shared/jsonld.ts`,
  `_shared/unit_hints.ts`, `import-recipe/index.ts` orchestration with injected
  `ImportDeps`); real wiring lives in `import-recipe/live.ts` (see [0019](./0019-import-integration.md)).
- **Roadmap step:** Step 8 — import (lane A of the W0 DAG)
- **Created:** 2026-08-30
- **Contract:** frozen in [0014](./0014-import-foundation.md) · types in
  `supabase/functions/_shared/types.ts` · gold shape in
  `evals/datasets/extraction/gold/_SCHEMA.md`

## Goal

The deterministic spine of the server pipeline: intake → `RawBlob` → (sanitize
adapter) → `ExtractionResult` → §7 normalize → (match) → `ReconciliationPayload`.
Everything here is deterministic and offline-testable; the LLM adapters (lane D)
and the match cascade (lane B) are consumed **through their frozen interfaces**,
faked in tests.

## Deliverables

1. `supabase/functions/_shared/jsonld.ts` — fetch a URL, parse every
   `schema.org/Recipe` JSON-LD block → `RawBlob{source:"jsonld"}` (or
   `{source:"page_text"}` when absent/malformed). **Port the proven logic from
   `supabase/seed/scripts/mine_recipes.ts`** (it already does this). Pure/deterministic.
2. `supabase/functions/_shared/unit_hints.ts` — the `UnitHints` deriver (canonical
   units + accepted imprecise words + size words). A hand-maintained **server mirror**
   of `app/lib/core/units`, with a header pointer to that Dart source (the single
   source of truth — keep them in step). NOT the ingredient vocab.
3. `supabase/functions/import-recipe/index.ts` — the orchestration, replacing the
   501 stub. Accept `{url}` or `{images}`; build `RawBlob` (jsonld/page_text for URLs;
   images → `adapter.transcribe`); call `adapter.sanitize(blob, hints)`; run §7
   `normalize` per line; call the matcher (lane B); assemble `ReconciliationPayload`.
   The adapter + matcher are **injected** (real ones wired at integration; fakes in tests).

## Boundaries (what this lane must NOT do)

- **No LLM prompt work** — that's lane D. Depend on the `ExtractAdapter` interface;
  test with a fake adapter that returns a canned `ExtractionResult` (reuse a gold file).
- **No match cascade** — that's lane B. Depend on its `matchLines` signature; fake it.
- Sanitize input is **ingredient-vocab-blind** (ADR-0004) — never pass vocab into ①.
- Honour **never-invent**: pass warnings/confidence/ranges through untouched.

## Tests

- JSON-LD parse against saved HTML fixtures (pull a few from `recipe_urls.txt`),
  including a `needs_fallback` page → `page_text`.
- Orchestration against a fake adapter + fake matcher → a known `ReconciliationPayload`
  (assert wiring, normalize call, group/line/step passthrough, refs stay by index).

## Done when

`deno check`/`deno test` green; orchestration returns a valid `ReconciliationPayload`
for both a URL and an images payload using fakes; JSON-LD parity with `mine_recipes.ts`
on shared fixtures.
