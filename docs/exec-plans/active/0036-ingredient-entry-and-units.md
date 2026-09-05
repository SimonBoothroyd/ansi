# Exec plan: ingredient entry — the default measure, `tsp`, and the units section

- **Status:** draft
- **Owner:** Simon (rulings) · agent lane (build)
- **Roadmap step:** 8.14 — field test, round five
- **Created:** 2026-09-04

## Goal

Three things a cook hit in one sitting: adding garlic to a recipe offers
`piece` when the household has already said a bare count means a **clove**;
a teaspoon of sugar cannot be written at all; and the *Units & measures*
section runs its density sentence off the edge of a 402 pt phone.

Done: `＋ ingredient → garlic` opens on `clove`; `1 tsp` of a cup-default row
is admissible; and the section reads as three separated subjects with the
density sentence on one line.

## What is true today

- **The default measure is honoured on one surface only.** The import review
  already implements "a bare count means the row's stated measure"
  (`line_validation.dart:306`, `Ingredient.defaultMeasureId`, migration 0023).
  The quantity sheet — the one entry surface app-wide — seeds its choice as
  `initialChoice ?? UnitOption(ingredient.defaultUnit)`
  (`quantity_unit_sheet.dart:146`) and never reads `defaultMeasureId`. Adding
  garlic from the editor therefore opens on `piece`; picking `clove` afterwards
  is the two-step the owner described.
- **`tsp` is not in `cup`'s kitchen mates.** `_kitchenMates` gives `cup` →
  `{cup, tbsp, ml, l, pint, quart}` (`allowed_units.dart:47`), so a cup-default
  row like `Granulated Sugar` (seed `vocab.jsonl:167`) never admits `tsp`,
  while `tbsp`'s mates *do* include `cup`. The asymmetry is visible in one
  screenshot: the ALLOWED UNITS row reads `cup · tbsp · ml · l · pt · qt · g ·
  kg` while the density sentence right below it offers `tsp` as a spoon.
- **The section's spacing is a real layout break, not taste.** `ALLOWED UNITS`
  chips are followed immediately by `DENSITY 0.13 g/ml` with no gap — every
  other `_Label` in the group has one — and the density `Wrap`
  (`density_entry.dart:155-186`) breaks so the 72 pt `FTextField` lands on its
  own line at full field height, with `Add` full-width under it. The
  self-describing sentence becomes three stacked rows.

## Fronts

Every ruling below is settled.

### Front A — a bare count means the stated measure, everywhere

- **A-D1** `QuantityUnitEditor` seeds its choice from `defaultMeasureId` when
  the caller passes no `initialChoice`: once the measures stream lands, if the
  row states a default measure that is live, the choice becomes
  `MeasureOption(it)`. The stated fact wins over the derived one.
- **A-D2** The seed is **not** a pick: `unitPicked` stays false, so a caller
  preserving an unresolved `measure_id` behaves as before.
- **A-D3** A stated default whose measure has not synced to this device leaves
  the seed alone (the review's own rule — never a *different* measure than the
  household named).
- **A-D4** No new provider: the sheet already watches
  `ingredientMeasuresProvider`.

### Front B — `tsp` for a cup-default row

- **B-D1** **Ruled by the owner's own ask ("need to allow tsp of sugar"), and
  it lands as an ADR-0008 amendment, not a patch:**
  `cup`'s mates gain `tsp`, making the volume ladder symmetric — `tsp` already
  mates `tbsp`, `tbsp` already mates `cup`, and a teaspoon of a cup-default
  ingredient (sugar in a dressing, salt in a dough) is an ordinary kitchen
  line. The magnitude argument ADR-0008 makes ("no litres of yeast") is about
  *big* units, and `tsp` is small.
- **B-D2** **Yes, the database changes too — in three places.** The owner asked
  the right question: `allowed_units` is not derived at read time, it is
  **stored**.
  1. `default_allowed_units()` is the SQL mirror of the Dart rule
     (`supabase/migrations/0012_unit_admission.sql:90`). One rule, two
     implementations, pinned by the shared vectors
     (`supabase/seed/scripts/gen_admission_vectors.ts`). Both move together or
     the phone and the server disagree about what a line may say.
  2. Every row already carries a **materialized** list: a `before insert`
     trigger stamps the defaults (`:185`), and 0012 backfilled the whole
     existing vocabulary. So changing the rule reaches **no existing row** —
     sugar keeps its old list until something writes to it.
  3. The seed template's rows are materialized the same way and are
     regenerated.
- **B-D3** **The widening statement, and what it must not touch.** A migration
  adds `tsp` only to rows whose `allowed_units` still **equals the old derived
  default** for that row. A household that curated its own list — every
  `stopOfferingPiece` removal, every toggled chip — is left alone, because
  ADR-0009 rule 3 forbids a backfill from removing, and this is the same
  principle in the other direction: a backfill may not overwrite a stated fact.
  A row that has drifted keeps what it has and gains `tsp` the next time a
  human saves it.
- **B-D4** A superseding ADR records the rule change (ADR-0008 is immutable),
  naming the vectors that changed and B-D3's fence.
- **B-D5** pgTAP covers all three: the function's new answer, the migration
  widening a pristine row, and the migration **not** touching a curated one.

### Front C — the Units & measures section reads

- **C-D1** `DENSITY` gets the same leading space as every other `_Label` in the
  group; the density block is one subject, spaced from the admission chips.
- **C-D2** The density sentence goes truly inline: the number field compact
  (single-line height, no full field chrome), and `Add` a small button on the
  same run, so `1 [tbsp] of this weighs [__] g [Add]` is one row on a 402 pt
  screen. It stays a `Wrap` — G2's lesson holds — but it must not break for
  the common case.
- **C-D3** **Ruled (owner, 2026-09-04): it folds.** With a density set the
  block collapses to `0.13 g/ml · change`; tapping opens the sentence. It is
  stated once and read often, and the folded state is what makes C-D2's inline
  row the exception rather than the everyday height of the section.

## Acceptance criteria

- [x] Adding garlic from the editor opens the sheet on `clove`; a row with no
      stated default is unchanged.
- [x] `1 tsp` is admissible on a cup-default row with a density, in Dart **and**
      in SQL, with the shared vectors regenerated and green.
- [x] Existing rows are migrated: a pristine `allowed_units` gains `tsp`, a
      curated one is untouched — both asserted in pgTAP.
- [x] The units section renders as one row per subject at 402 pt — measured in
      a widget test with the real fonts loaded rather than eyeballed, because
      the section's width budget is 24 pt either way (see C1 below).
- [x] Tests: `quantity_unit_sheet_test` (A-D1/A-D3), `allowed_units_test` +
      pgTAP admission vectors and the migration's two fence assertions (B),
      `density_entry_test` at 402 pt (C).
- [x] Docs: [ADR-0012](../../decisions/0012-tsp-mates-cup.md),
      `ingredient-detail.html` and `quantity-measures.html` re-drawn,
      `app/lib/features/ingredients/README.md`.

## Approach

1. Front A — smallest, and the one with a user-visible payoff per tap.
2. Front C — layout only, no rules.
3. Front B last: it is a rule change with a migration-shaped tail (the SQL
   mirror + vectors), and it wants the ADR written before the code.

## Decision log

- 2026-09-04 — Filed from the owner's round-five notes ("garlic still showing
  piece not clove", "need to allow tsp of sugar", "spacing … too small … a more
  inline style"). The `Chex Cereal` screenshot the owner sent shows both the
  spacing break and the missing `tsp` in one frame.
- 2026-09-04 — Owner: *"do we also need to update the db? aren't allowed
  measures stored in the DB?"* — yes. B-D2/B-D3 rewritten: the SQL mirror, the
  materialized lists on every existing row, and a widening migration that
  refuses to overwrite a curated list. This is no longer a Dart-only change,
  and it now carries a migration.
- 2026-09-04 — **C1, build finding: "of this" cannot stay.** C-D2 names the
  target sentence as `1 [tbsp] of this weighs [__] g [Add]`. Measured with the
  real fonts at 402 pt, the section has **338 pt** of usable width in the
  tightest host and that run needs **421**. Every lever was tried: dense spoon
  chips, an `xs` button with trimmed padding taking its own width, a compact
  field with Forui's 44 pt touch floor lifted, prose at 12 pt. The gap only
  closes at 10 pt prose with 4 pt chip padding, which is a compressed mess
  rather than a sentence. `of this` costs 58 pt on its own, so the connector
  is **`weighs`** — `1 tbsp weighs 15 g` says the same thing, and the subject
  is named by the headline directly above it and by the screen it sits on.
  With it the run measures 322 of 338. `density_entry_test.dart` pins that,
  and loads the real faces to do it: under the test binding's fallback font
  every glyph is a square of the font size, so a layout assertion made without
  them measures a typeface nobody ships.
- 2026-09-04 — **C2: the fold is where the section OPENS, not something that
  happens under your hands.** C-D3 is implemented as the state a row with a
  stated density is *drawn* in. Collapsing the moment a number lands was tried
  and rejected twice over: it pulls the field being typed in out of the tree
  (keyboard, focus and an in-flight ensure-visible scroll with it, which the
  widget tests catch as a torn-down render object), and it hides the
  equivalence line `= 0.66 g/ml` at exactly the moment that line is the
  receipt for what was just done. So a landed number leaves the sentence
  where it is for this visit, gains the `remove the density` affordance, and
  the next time the section is drawn it is one line.
- 2026-09-04 — **B1: the widening fence is checkable, not a guess.** B-D3
  needs the OLD derived default per row, and 0032 computes it rather than
  carrying a copy of the old function: the only change to
  `default_allowed_units()` is `'tsp'` in the `cup` branch of the mates leg,
  and for a `cup` default no other leg of that function can emit `tsp` (basis
  → `g`/`kg` or `ml`/`l`; density cross for a volume default → `g`/`kg`;
  imprecise → words). So `old = new − {tsp}` for a cup-default row and
  `old = new` for every other, which is why the migration only looks at
  cup-default rows at all. Compared as sorted distinct arrays — `allowed_units`
  is a set, and its stored order is nobody's contract.

## Notes / open questions

- Front B is the only place this plan touches existing data, and B-D3 is the
  fence: a backfill may add where the row never stated anything, never
  overwrite what a household stated.

## Step-done checklist

- [ ] Roadmap row updated.
- [ ] `ARCHITECTURE.md` standing table matches for `features/ingredients` + `core/units`.
- [ ] `app/AGENTS.md` current focus still true.
- [ ] `make test-sim` run, result recorded here. The integration flow was
      updated for the new wording and the fold (the second density entry taps
      `· change` first) but has not been run on a simulator.
- [ ] Tech-debt rows added/retired.
- [ ] Migration status (B-D2's SQL mirror) stated in the roadmap row, and a
      `cloud-setup.md` ledger entry when it lands on cloud. **`0032` has not
      been pushed to cloud.**
- [x] `make ci-full` green, pgTAP included (Docker was available):
      `unit_admission.sql` at 112 assertions, all 11 files passing.
