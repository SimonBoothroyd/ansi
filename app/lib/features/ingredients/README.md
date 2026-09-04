# Feature: ingredients

**Roadmap:** steps 1, 7.6–7.8 and **8.5** (see `docs/exec-plans/roadmap.md`).

The household's controlled vocabulary and everything that reads or writes it:
the **picker** recipes and shopping select from, the **quantity + unit** entry
surface (chips, measures, density), and the **manager** — the screen where the
vocabulary is browsed and edited, including turning a bare `stub` into a
`complete` ingredient.

**The client never fuzzy-matches for a machine decision** (ADR-0004). Search
here is deterministic retrieval for a human to pick from, over the ~300 synced
household rows. The one network call in the feature is the barcode module's
Open Food Facts read — an exact-key fetch by product code, not matching.

## The surfaces

```
/ingredients            ingredient_list_view.dart    the whole vocab, stub band on top
/ingredients/new        ingredient_detail_view.dart  the form with no row behind it —
                                                     THE add door; `?name=` prefills it
/ingredients/:id        ingredient_detail_view.dart  the same form over a stored row

showIngredientPicker    ingredient_picker.dart       recipe editor, shopping top-up
   └── AddNewIngredientRow: push /ingredients/new → back → resolves with the row
showQuantityUnitSheet   quantity_unit_sheet.dart     every quantity+unit in the app
        └── manage measures + DensityEntry (density_entry.dart)
showUsdaPickSheet       usda_pick_sheet.dart         the USDA short-list a person picks from

scanBarcodeForDraft     barcode/barcode_add.dart     the barcode module's one door
applyDraft              domain/apply_draft.dart      how a draft lands on the form's fields
```

`/ingredients` is a **pushed** route reached from the Library's ingredients
shelf, not a fifth bottom-nav tab: the four tabs are the cooking loop, and a
vocabulary is reference data.

## One form, one Save

**The form is the add flow.** There is no separate new-ingredient sheet: a
creation is `/ingredients/new`, which is the same widget with no row behind it
yet. Every add-new door — the manager's ＋, the editor picker's footer, the
shopping top-up, the import review's create-new — pushes that route, and a
picker pushes it *over its own sheet* through `context.pushOnceFor` and awaits
the pop, so the quantity sheet that follows offers the units the form just set.

**Nothing is written until Save** ([ADR-0011](../../../../docs/decisions/0011-one-save-one-write.md)).
The form holds everything it intends — the row's fields, the density, the
measures added and removed, the aliases, what a bare count means, and whether
to mark the row complete — as one `IngredientFormEdit`, and `saveForm` applies
the lot in a single transaction. `saveForm(null, …)` creates the row and its
children together. Two consequences the surfaces depend on:

- a form with no row behind it is coherent, and backing out of one leaves
  nothing to clean up — no stub is minted as a side effect of opening a screen;
- partial success is not representable. `Mark complete` saves and marks in the
  same statement rather than as two writes with a failure possible between them.

The measures and aliases travel as **deltas**, not replacement lists, so a
stream that failed to load can never become a narrowed set written back.

## USDA, and the barcode

A **USDA pick fills the draft**, exactly like typing does. *Fill it in from ▸
Look up in USDA* and *Choose another ▸* open the same short-list
(`usda_pick_sheet.dart` over `UsdaProbe.search`); the pick puts the food's
macros, its density and its provenance into the draft the form is holding, and
the form's own Save lands them. Nothing writes on the tap, and nothing about a
pick confirms the row. **Not this food** (`declineUsdaPrefill`) is the one USDA
act that writes on its own: it strips the prefilled density with the units it
alone unlocked, drops the macros, and leaves `source = usda_declined` — a
distinct fact from "nobody ever linked one", which the provenance line reads.

The query is the name **in the field**, not the stored row, so a rename can be
looked up before it is saved.

**No machine matches on its own.** `usda_food` never syncs to a device
(ADR-0005), so the app asks the server through the read-only `probe_usda` RPC
(migration `0016`, widened by `0027` to name each candidate and take a limit).
The `ingredient_usda_prefill` trigger that used to enrich stubs on upload was
dropped in migration `0029`: a stub whose owner deliberately did not use the
search would otherwise come back filled one sync later, with a provenance line
claiming a match no human ever made. A stub with no macros is a good stub.

`source_score` is **coverage, not confidence** — the idf-weighted share of the
query the matched description accounts for. It is shown and never acted on.

The barcode module is the same shape: `scanBarcodeForDraft` returns an
`IngredientDraft`, a *sketch* that is never a row, and `applyDraft` lands it on
the form's fields — filling what is empty, keeping what a human typed, and
stamping `off:<barcode>` only where there was no source.

## Layout

```
ingredients/
  domain/         PURE DART (no package:flutter)
    ingredient.dart          Ingredient + IngredientAlias (Freezed)
    ingredient_repository.dart  the interface + IngredientFormEdit + DeleteOutcome
    allowed_units.dart       ADR-0008/0009 admission — the Dart mirror of
                             default_allowed_units() / density_unlocked_units()
    normalize.dart           the PHRASE normalizer — Dart twin of normalize.ts
    usda_probe.dart          the probe interface + its offline contract
    measure_repository.dart  named per-ingredient measures
    apply_draft.dart         the one rule for landing a barcode draft on a form
  data/
    ingredient_repository_impl.dart  SqliteIngredientRepository — read + write
    measure_repository_impl.dart     measures, with merge-on-read for dup labels
    usda_probe_impl.dart             the `probe_usda` RPC — the feature's one
                                     deliberate read that is not local SQLite
    ingredient_providers.dart        keepAlive repo providers + watch streams
  presentation/
    ingredient_list_view.dart   the manager list
    ingredient_detail_view.dart the form — create at /ingredients/new, edit at /:id
    usda_pick_sheet.dart        the USDA short-list and its candidate rows
    ingredient_picker.dart      the picker + the add-new chain's row
    measures_editor.dart        add/remove named measures, shared by two hosts
    serving_row.dart            the per-serving macro mode's "1 tbsp (14 g)" row
    draft_card.dart             the barcode result card
    quantity_unit_sheet.dart    quantity + unit chips, manage measures
    density_entry.dart          g/ml ⇄ "1 tbsp weighs N g", shared
    macros_format.dart          the per-100 macro line
  barcode/        the scan → lookup → draft module
    barcode_add.dart      scanBarcodeForDraft(context) — the ONLY public door
    barcode_scan_sheet.dart camera reticle + a permanent typed-number field
    off_lookup.dart       the on-device Open Food Facts GET + its failure states
    off_mapper.dart       payload → draft, PURE DART, four nutriment keys
    ingredient_draft.dart the hand-off type — a sketch, never a row
```

## The rules this feature exists to hold

- **Honest numbers, never zeros** (invariant 3). A `stub` shows its badge, not a
  0 kcal macro line. Anything a lookup could not establish stays **null with a
  reason attached** — the draft type, the mapper, and the form all preserve that.
- **Macros gate `complete`; density does not; confirming is a human act.** A row
  with no macros cannot be marked complete, so the gate holds below the disabled
  CTA. A USDA or barcode prefill fills fields and stops. Confirming is reversible
  (`unconfirm`).
- **Unit admission is explicit and per-ingredient** (ADR-0008). `allowed_units`
  is materialized at creation and thereafter **user-owned** — extended by
  writes, never silently re-materialized. Since
  [ADR-0009](../../../../docs/decisions/0009-density-unlocks-both-families.md) a
  density unlocks the other mass/volume family whatever the default's family;
  `setDensity` unions that in the same transaction, and `clearDensity` strips
  what the density granted. `allowed_units.dart` and the SQL function are
  mirrors pinned by shared vectors — change one, change both.
- **A rename rewrites `match_text`** through `normalizeMatchText` in the same
  statement. The server writes `match_text` with the phrase rules; the app must
  write the same ones, or a locally created row carries text the next import's
  cascade would never find. Vectors in
  `test/features/ingredients/normalize_vectors.json` are copied from
  `normalize.test.ts` and pin the two implementations together.
- **Delete is refused while a live recipe line points at the row**, with the
  count. It is a soft delete, and the aliases go with it — an alias outliving
  its ingredient resolves to nothing.
- **Writes are view-safe**: local PowerSync tables are SQLite views, so every
  statement is a plain INSERT/UPDATE — a view rejects `ON CONFLICT`.
- **Mutations go through the keepAlive repo provider**, never a throwaway
  notifier held across an async gap.

## Tests

- Domain: `allowed_units_test` (the ADR vectors, shared with
  `supabase/tests/unit_admission.sql`), `normalize_test` (the shared JSON
  vectors), `apply_draft_test`.
- Repo on a real `PowerSyncDatabase`: `ingredient_repository_test`,
  `measure_repository_test` — search/recents, `saveForm` create and edit,
  density round-trips, confirm/unconfirm, delete refusal, aliases.
- Widget: `ingredient_manager_test` (list band, form, confirm gate, delete),
  `ingredient_picker_test`, `quantity_unit_sheet_test`.
- Barcode: `barcode/` — mapper and lookup against committed fixtures (no
  network), the scan sheet's failure states, and the public door's contract.
- Server-side: the admission functions are pinned by
  `supabase/tests/unit_admission.sql` (pgTAP), not by anything in this feature.
