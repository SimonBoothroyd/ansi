# Exec plan: USDA provenance — the source shown where mismatches are caught, and a row that was edited says so

- **Status:** built (lane) — awaiting the sim leg and the cloud deploy of `0034`
- **Owner:** Simon (rulings) · agent lane (build)
- **Roadmap step:** 8.14 — field test, round five
- **Created:** 2026-09-04

## Goal

Two things about a machine-filled row. **One:** the USDA food that filled it is
named wherever a mismatch would be spotted — not only on the row's own form,
which you have to open one row at a time. **Two:** a row a human has since
edited stops claiming its numbers are USDA's.

Done: scanning the Ingredients list, you can see that *Chex Cereal* was filled
from `Cereals ready-to-eat, GENERAL MILLS, Corn CHEX` without opening it; and a
row whose density or macros you typed yourself reads *filled from USDA · edited
here*, naming what changed.

## What is true today

- The provenance line **exists and is good** — on the ingredient detail form
  only. `_UsdaProvenance` (`app/lib/features/ingredients/presentation/ingredient_detail_view.dart:753`)
  reads the row's own `source_label` / `source_score` (never a live probe) and
  prints *Filled from USDA · not confirmed · «description» · FDC 168930 · a
  close match*, with *Not this food* and *Choose another ▸*.
- Nowhere else names the source. The Ingredients list, the picker and the
  import review's identity cell all show the canonical name alone — so
  a wrong match is invisible until you open the row that has it.
- **Nothing records that a human edited a prefilled row.** `source` is
  patch-shaped and preserved across a form save
  (`ingredient_repository_impl.dart:610` — `source = COALESCE(?, source)`), so
  typing your own density or macros over a USDA prefill leaves
  `source = 'usda_fdc:<id>'` and `source_label` intact. The card then names a
  food whose numbers are no longer on the row.
- The one existing escape hatch is *Not this food* (`usda_declined`), which
  **clears** the numbers. There is no state for "I kept the match and corrected
  its figures", which is the ordinary case.

## Fronts

Every ruling below is settled.

### Front A — the source, where it is scanned

- **A-D1** The Ingredients list row carries the source description as its
  second line when the row is USDA-filled — muted mono, truncated to one line,
  the same words the form prints. A manual or barcode row shows what it always
  showed.
- **A-D2** **Ruled (owner, 2026-09-04): the import review's identity cell
  too**, under the matched name — that is the other moment a wrong food is
  cheap to catch and expensive to miss. The ingredient *picker* is deliberately
  left out: it is a search surface, and a description under every row is noise
  while you are typing.
- **A-D3** Nothing new is read: `source_label` is already synced and already on
  the summary path, or one column away from it. If it is not on the list's
  query yet, the query gains a column — not a per-row read.
- **A-D4** No description, no line. A pre-0027 row carrying a stamp and no
  label keeps saying nothing rather than inventing a name (the form's own rule).

### Front B — a row that was edited says so

- **B-D1** **Ruled (owner, 2026-09-04): one synced boolean column,
  `ingredient.source_edited`** — set by the save path when a human write changes
  **macros, macros basis or density** on a row whose `source` is a lookup
  provenance. Not set by a rename, a unit toggle, a measure or an alias — those
  do not contradict the source. The alternatives are worse: encoding it in
  `source` breaks every `usda_fdc:` parser; diffing against the USDA values
  means keeping a second copy of them on the row.
- **B-D2** The provenance card gains the third state it is missing:
  *Filled from USDA · edited here* — the food still named, the FDC id still
  shown, and one line saying **what** was overridden (*your macros* / *your
  density* / *both*). It is provenance, not a warning: muted, not amber.
- **B-D3** *Not this food* and *Choose another ▸* stay exactly as they are. A
  fresh pick clears the flag, because the numbers are the new food's again.
- **B-D4** Front A's list line follows: an edited row's second line reads
  *edited · «description»*, so the scan shows which rows are no longer the
  machine's.
- **B-D5** Migration + both sync-rule YAMLs + `schema.dart`; pgTAP that the
  column round-trips and that the flag is not set by a rename.

### Front C — what this is not

- **C-D1** Nothing here confirms a row, and nothing auto-declines one
  (0027 U-D4 stands): a human still promotes a stub.
- **C-D2** No new probe, no live lookup. Every surface reads the row's own
  stamped columns, so it is all true offline.

## Acceptance criteria

- [x] The Ingredients list names the USDA food behind a filled row; a manual
      row is unchanged. (`sourceProvenanceLine` →
      `IngredientRow.showSource`, which the manager sets and the picker does
      not.)
- [x] Editing macros or density on a USDA-filled row flips `source_edited`; a
      rename does not.
- [x] The provenance card reads *edited here* and names what was overridden.
- [x] Choosing another food clears the flag.
- [x] Tests: repo tests for the flag's writers and non-writers (16 cases),
      a widget test per surface (manager list, picker's deliberate silence,
      the card's third state, the review's identity cell, and the validation
      that feeds it), pgTAP for the column.
  - [ ] The sim leg that edits a prefilled row and re-reads the card — the
        orchestrator schedules `make test-sim` (one simulator, serial).
- [x] Docs: `ingredient-detail.html` and `ingredients-manager.html` re-drawn
      (plus `import-review.html` and `ingredient-picker.html`, which the same
      rule touches), `app/lib/features/ingredients/README.md`,
      `docs/generated/db-schema.md` regenerated by `make docs`.

## Approach

1. Front A first — read-only, no migration, and it is the half that answers
   "spot the mismatch" today.
2. Front B second: column + writers + pgTAP before the card's third state.

## Decision log

- 2026-09-04 — Filed from the owner: *"if an ingredient has a matching USDA
  code, can we make sure to show the source description to make it easier to
  spot mismatches? we should also flag if this is 'dirty' (i.e. a user override
  some properties)"*. The description is already stored and already rendered on
  the form (0027 U-D1) — the gap is **where** it is shown; the dirty flag does
  not exist in any form.

### Built (lane, 2026-09-04)

Every D-list ruling landed as written. The judgement calls the lane had to
make, each recorded rather than left implicit:

- **The flag's writers are three, not one.** B-D1 says "the save path"; the app
  has three client paths that can change a number on a stored row, and all
  three set it: `saveForm`, and `setDensity` / `clearDensity`, which are the
  **quantity sheet's** density entry writing directly. The flag is a fact about
  the row, not about the screen you were standing on — a density typed into the
  unit sheet contradicts the source exactly as much as one typed on the form.
  Nothing else writes it, and there is deliberately **no trigger**: 0029
  removed the last server-side writer of provenance and this does not
  re-introduce one.
- **"A lookup provenance" reads as `usda_fdc:<id>` OR `off:<barcode>`**
  (`isLookupFilled`). Both stamps assert "these numbers came from somewhere
  else", so both are contradictable. Only the USDA half renders anywhere today
  — a barcode row has no `source_label` and so no line and no card — but the
  column is then true for the day the barcode card exists, rather than needing
  a backfill.
- **The flag is sticky once set, until a fresh pick.** B-D1 refused to keep a
  second copy of the source's figures, so nothing can tell a number typed back
  to the food's value from a coincidence. Typing your macros and then typing
  them back leaves the row reading *edited here*, which is the honest answer
  available.
- **B-D2's "what was overridden" is derived from what the row carries, not
  from which field was typed** — *your macros* / *your density* / both. One
  boolean records **that** the numbers were overridden and cannot record
  **which**; that is B-D1's own trade, and the claim is therefore made at row
  granularity, which is the granularity the fact has. The board frame's line is
  unchanged in the common (both) case.
- ***Not this food* clears the flag.** B-D3 rules the two doors unchanged and
  they are — same offer, same write, same words. The flag going back to false
  alongside the macros and the density it names is a consequence of its
  definition, not a change to the door: after a decline there are no numbers
  and no fill, so `true` would be a claim about a state that no longer exists.
- **The card's *edited here* replaces the confirm word** rather than sitting
  beside it. "Filled from USDA · confirmed" on a row whose numbers you typed
  reads as a claim about the numbers, which is the thing this front exists to
  stop.
- **No YAML change was needed.** Both sync-rule files already
  `select * from ingredient`, so the column syncs as-is and
  `scripts/check_stream_drift.sh` stays green; the client schema gained
  `Column.integer('source_edited')` (PowerSync carries a boolean as 0/1).
- **The `· yours` marker beside the density field, drawn on the proposed
  frame, did not ship.** It needs the per-field knowledge the boolean does not
  have, and it was drawn against the density row that plan 0036 has since
  replaced. The card's own line carries the fact instead.
- **`ingredient-picker.html` and `import-review.html` were re-drawn too.** The
  review's identity cell is A-D2's other half, and the picker's frame now says
  its silence is deliberate, so a later pass does not "fix" it.

Verification: `make gen`, `make analyze` (analyzer + custom_lint), `make test`
(1786 app tests · 156 edge-function tests), `make docs`, `make docs-check`, and
`supabase test db` — 12 suites, 333 assertions, on migrations 0000–0032 + 0034
(no 0033: that number belongs to another lane).

## Notes / open questions

- B-D1's fence is what keeps this honest: the flag means *the numbers are no
  longer the source's*, so only writes that touch numbers may set it.

## Step-done checklist

- [ ] Roadmap row updated.
- [ ] `ARCHITECTURE.md` standing table matches for `features/ingredients`.
- [ ] `app/AGENTS.md` current focus still true.
- [ ] `make test-sim` run, result recorded here.
- [ ] Tech-debt rows added/retired.
- [ ] Migration recorded: `0034_source_edited.sql` is **local only** — applied
      to the local stack and pinned by `supabase/tests/source_edited.sql`. It
      has NOT reached cloud; the owner deploys it, and the
      `docs/cloud-setup.md` ledger entry follows when it does.
- [ ] `make ci-full` green (needs Docker).
