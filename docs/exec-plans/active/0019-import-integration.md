# Exec plan: Import — Tail, integration + live verification

- **Status:** blocked (on lanes A·B·C·D)
- **Owner:** Claude (with Simon for the provider key + the sim run)
- **Roadmap step:** Step 8 — import (the join)
- **Created:** 2026-08-30
- **Contract:** [0014](./0014-import-foundation.md)

## Goal

Join the four lanes into a working end-to-end import and prove it live, then land the
doc/roadmap changes step 8 owns. This is the only inherently-serial node.

## Deliverables

1. **Wire the join** — lane D's chosen provider adapter into lane A's orchestration;
   lane B's real `matchLines`; swap lane C's fake edge fn for the real
   `functions.invoke` (register the function; auth-scoped to the household).
   - **Seam note (from lane A, 2026-08-30):** lane B's `matchLines` grew a second
     `VocabMatcher` arg (household-scoped Postgres seam) past the 0014 stub signature.
     Lane A consumes a **pre-bound** `(lines) => Promise<MatchedLine[]>` via
     `ImportDeps.matchLines`. Integration constructs the real `VocabMatcher` (auth →
     household) and closes over it here. Also confirm §7 `normalize` runs **inside**
     `match.ts` (lane A delegates, per the frozen `RawLineItem` having no `match_text`
     carrier) — do not double-normalize.
2. **Provider key** — take lane D's recommendation, set the key (Simon), pin the model.
3. **Live E2E on the iOS sim** — a `make test-sim` scenario: import a real recipe
   (URL and a photo) → reconcile (auto/suggest/none, a range, a create-new stub) →
   commit → the recipe appears with chipped steps, over **live sync**. Record the result.
4. **Docs** — rewrite import-and-matching.md **§4** (extraction = transcribe/parse →
   one ingredient-blind sanitize stage; §4.6 alignment is LLM-semantic) and **§6**
   (band source); add a decision-log note **reaffirming ADR-0004** (matching stays
   deterministic/server-side; "extraction" now = transcribe + vocab-blind sanitize) —
   not an amendment. `make docs` (regen `db-schema.md` for `0013`).
5. **Roadmap + quality** — step-8 row → 🟢 with what shipped / deferred;
   `docs/QUALITY.md` import grade; move `0014`–`0018` to `completed/`.
6. **Tech-debt** — add: **nested recipes** (sub-recipe refs are plain text for now);
   FAO/INFOODS density tail; the picker-stub `match_text` re-normalization (existing
   row, now closeable via the shared normalizer); any lane-deferred corners.

## Coordination ledger (surfaced by the lanes, resolve at the join)

- **Stub-create surface (A/B).** 0014's `CommitPayload` has the **client** insert the
  stub (synced up); the lane-B charter also gave B a **server-side** `createImportStub`
  (needed because the USDA prefill is unavoidably server-side — `usda_food` never
  syncs). Both write the identical row shape. **Pick one surface:** cleanest is client
  creates the stub on "create-new" (local insert → syncs up), and B's `prefillStubFromUsda`
  background job enriches it by `match_text` — no double-create. Wire accordingly.
- **Stale matching eval (B).** `evals/datasets/matching/cases.jsonl` (Aug 25) predates
  recent vocab edits, so ~9% of "misses" are label drift (`Cashew`→`Cashews`, new
  `Canned X` rows), not cascade defects. **Regenerate via `evals/runner/gen_matching_cases.ts`**
  so the eval tracks current `vocab.jsonl` (lane D owns `evals/`; fold into the tail if
  D hasn't).
- **matchLines/VocabMatcher seam (A/B).** Already wired directly (see deliverable 1);
  just confirm the household-scoped matcher is constructed from auth at the edge boundary.
- **Measure nouns in `UnitHints` (D).** The gold marks `can`/`clove`/`sprig` as
  `unit` with `unit_mappable: true`, but the hints contract excludes per-ingredient
  measures — so a strictly measure-blind model may emit `unit_mappable: false` and
  disagree with the gold on those. **Decide the authority:** lean toward hinting the
  *common, generic* measure nouns (`can`, `clove`, `sprig`, `slice`, `bunch`) as
  accepted count-units (matches the gold + the measures system) while leaving truly
  ingredient-specific measures to post-match resolution. Whichever way, keep the gold
  and `unit_hints.ts` consistent.
- **`require-await` in lane A's `intake` (D→fixed).** Fixed in the tail-owner pass
  (`await`ed the provider returns); server lint/check/tests green across A+B+D.

## Done when

Live import works on the sim over cloud sync; spec §4/§6 + ADR note landed; roadmap
step 8 done; `make ci` green.
