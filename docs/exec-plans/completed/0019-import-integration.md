# Exec plan: Import — Tail, integration + live verification

- **Status:** done — live URL import works end to end; the doc/roadmap close-out
  landed 2026-08-31 (this file's own deliverables 4–6 shipped late, in the
  step-done pass that also wrote the decision log below).
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
   - **Result:** URL path driven live (Mango Salsa, 14 ingredients, committed with
     chips). Photo path driven live from the **gallery picker** (a Dense Bean Salad
     cookbook photo: 19 ingredients, "2.5 can"/"handful"/notes all correct) — there is
     no in-app camera capture, and no run on a physical phone. The scripted `make test-sim`
     scenario 4 (import → reconcile → commit) is committed but its **tail** (stub loop
     → Save → post-commit asserts) has not been run on-sim yet. Both are tracker rows.
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

## Coordination ledger (surfaced by the lanes, resolve at the join) — CLOSED

- **Stub-create surface (A/B). → RESOLVED: client, at commit.** The client inserts
  the `status='stub', source='import_stub'` row inside the commit transaction
  (`SqliteImportRepository.commit`), keyed by the coalescing key so identical
  no-match lines share one created ingredient; it syncs up like any other write.
  Lane B's server-side `createImportStub` is not on the live path.
  `prefillStubFromUsda` remains the enrichment leg — **but nothing invokes it yet**
  (tech-debt tracker).
- **Stale matching eval (B). → done in the hardening pass.** Regeneration from the
  current `vocab.jsonl` (plus the scorer's mappable-equivalence gap) is owned by the
  post-step-8 hardening sweep, not by this tail.
- **matchLines/VocabMatcher seam (A/B). → RESOLVED.** `live.ts` builds the
  household-scoped `sqlVocabMatcher` from the verified JWT's `household_id` claim
  (never from the request body) and closes over it as `ImportDeps.matchLines`.
  `normalize` runs inside `match.ts` only — no double-normalize.
- **Measure nouns in `UnitHints` (D). → RESOLVED: hint them.** `unit_hints.ts` grew a
  distinct `measures` list — `clove · head · sprig · loaf · block · slice · can ·
  bunch · stalk` — the everyday counting nouns, kept separate from the canonical
  `units` and from the per-ingredient measure *table* (which stays app-side and never
  biases sanitize). This matches the gold, and stops ① force-fitting "2 garlic
  cloves" onto `piece`. `tin` is deliberately excluded; the prompt normalises
  `tin → can` so measure labels don't fragment.
- **`require-await` in lane A's `intake` (D→fixed).** Fixed in the tail-owner pass
  (`await`ed the provider returns); server lint/check/tests green across A+B+D.

## Decision log

Backfilled 2026-08-31 during the step-done pass — these were settled live, at the
keyboard, during the integration + owner-review iteration.

- 2026-08-31 — **The review screen merged into ONE editable surface.** 0014/0017
  designed a triage screen → a preview → commit. Driving it for real, the split read
  as ceremony: the user wants to *see the recipe* and fix it in place. Shipped
  instead: a single **Review recipe** screen, every line a card that is compact by
  default and expands in place to a full edit card (amount · ingredient · notes),
  with the read-only method fold rendering the same recipe a save would write. The
  design board's "Import & recipe view · v3" frames are therefore stale (tracker row).
- 2026-08-31 — **Band-based auto-lock, not band-based screens.** The match band no
  longer decides *which screen* a line appears on; it decides whether the line starts
  resolved (`auto`), starts with "did you mean" chips (`suggest`), or starts open
  (`none`). Validity — matched · range picked · unit admitted — is what gates Save,
  and it is recomputed per line (`line_validation.dart`), so a line the band locked
  can still be flagged if its unit isn't one the matched ingredient admits.
- 2026-08-31 — **Generic measure nouns ARE hinted to ①** (incl. `can`) — see the
  ledger entry above. This is the one place the "unit-aware, measure-blind" line was
  redrawn: counting *nouns* are unit vocabulary; the gram/ml *basis* riding on one
  ingredient stays out of the prompt.
- 2026-08-31 — **Provider = Claude Haiku 4.5**, on lane D's numbers (98.9% line-F1
  vs GPT-5.4-mini 93.4%; GPT's recall collapses on dense recipes). Not a guess, not
  a price call — the benchmark was the point of lane D.
- 2026-08-31 — **Stub creation is a client write inside the commit transaction**
  (ledger above). One surface, one row shape, no double-create.
- 2026-08-31 — **The flesh-out form slipped.** ADR-0008, the product spec, roadmap
  7.8 and two tracker rows all deferred the `allowed_units` editing surface *to step
  8*. Step 8 did not build it — an unrecorded slip, caught in the step-8 review. It
  is now its own unscheduled slice in the tech-debt tracker, and those references
  point at the tracker rather than at "step 8".

## Done when

Live import works on the sim over cloud sync; spec §4/§6 + ADR note landed; roadmap
step 8 done; `make ci` green. — **Met**, with the doc leg (deliverables 4–6) landing
in the later step-done pass rather than with the code.
