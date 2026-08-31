# Exec plan: Import — Lane B, match cascade + stubs + learning loop

- **Status:** active
- **Roadmap step:** Step 8 — import (lane B of the W0 DAG)
- **Created:** 2026-08-30
- **Contract:** frozen in [0014](./0014-import-foundation.md) · types in
  `supabase/functions/_shared/types.ts` · matching spec
  `docs/product-specs/import-and-matching.md` §6, §8, §9 · [ADR-0004](../../decisions/0004-matching-is-online-only.md)

## Goal

The deterministic, server-side match cascade over the **household** vocab
(~150–300 rows), returning bands + candidates; the user-driven stub path (no silent
auto-stub) with USDA background prefill; and the correction→alias learning loop.
This lane is the most independent island — it consumes **sanitized lines**
(`RawLineItem`, a W0 shape) and does not care how they were extracted.

## Deliverables

1. `supabase/functions/_shared/match.ts` — implement `matchLines`: §7 `normalize`
   each line → cascade (import-and-matching §6): **exact** `match_text` equality vs
   `ingredient` + `ingredient_alias` → auto; **trigram** (`pg_trgm similarity`) →
   auto (high) / suggest (mid, top-3) / none (low). Bands per §6 (≥0.85 / 0.55–0.85 /
   <0.55 — starting points, calibrated by lane D's eval, not a merge gate). Runs
   server-side against the household vocab (SQL / Postgres RPC using `pg_trgm`, indexes
   already exist in `0002`). **No embedding tier** (back-pocket per 0014).
2. **Stub lifecycle** (§9): the create-new path writes `ingredient` with
   `status='stub', source='import_stub'`; a background job searches `usda_food` by
   `match_text` and prefills density/macros (stays `stub` until the user confirms).
   No silent auto-stub — band `none` is surfaced to the user (lane C owns the UI).
3. **Learning loop** (§8): on a correction, write `ingredient_alias`
   `source='import_correction'` on the chosen ingredient (server contract/RPC; the
   trigger is a lane-C action).

## Boundaries

- **No LLM. No extraction.** Deterministic only. Consumes `RawLineItem`.
- Within-import **dedupe**: identical `none` lines resolve onto one just-created
  ingredient (coordinate the surface with lane C; the server keeps it idempotent).
- `usda_food` is server-only, never synced, never matched at import (ADR-0005).

## Tests

- `matchLines` against `evals/datasets/matching/cases.jsonl` + hand cases (regenerate
  from vocab with `evals/runner/gen_matching_cases.ts` if vocab changed).
- Band boundaries; exact-vs-trigram precedence; alias hits; `none` → empty candidates.
- Stub creation + USDA prefill (real-schema repo test); alias write-back.

## Done when

`matchLines` resolves the eval set at expected precision; stub + prefill + alias paths
covered by tests; `make ci` (edge-function tests) green.
