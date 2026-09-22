# Feature: ingredients

The household's controlled vocabulary and everything that reads or writes it:
the **picker** recipes and shopping select from, the **quantity + unit** sheet,
the **manager** where rows are browsed and edited, the **barcode** module, and
the **price** a row was last bought at.

**The client never fuzzy-matches for a machine decision**
([ADR-0004](../../../../docs/decisions/0004-matching-is-online-only.md)).
Search here is deterministic retrieval for a human to pick from. The one network
read is the barcode module's Open Food Facts fetch by product code.

## Surfaces

```
/ingredients         ingredient_list_view.dart    the vocabulary, stub band on top
/ingredients/new     ingredient_detail_view.dart  the form with no row behind it;
                                                  `?name=` prefills it
/ingredients/:id     ingredient_detail_view.dart  a fact sheet; ⋯ ▸ Edit is the form

showIngredientPicker   ingredient_picker.dart     recipe editor, shopping top-up
showQuantityUnitSheet  quantity_unit_sheet.dart   every quantity + unit in the app
showUsdaPickSheet      usda_pick_sheet.dart       the USDA short-list
showPriceSheet         price_sheet.dart           enter, edit or delete a price
scanBarcodeForDraft    barcode/barcode_add.dart   the barcode module's one door
pickLabelPhoto         label_photo_door.dart      the label door's photo intake
```

`/ingredients` is a pushed route from the Library's ingredients shelf, not a
tab.

## Files

```
ingredients/
  domain/         PURE DART (no package:flutter)
    ingredient.dart             Ingredient, IngredientAlias, provenance
                                predicates, sourceProvenanceLine
    ingredient_repository.dart  the interface, IngredientFormEdit, DeleteOutcome
    allowed_units.dart          unit admission — the Dart mirror of the SQL
                                functions; allowedUnitChoicesFor
    name_namespace.dart         names and aliases as one namespace
    normalize.dart              the phrase normalizer — twin of normalize.ts
    suggest_name.dart           the form's tidied-name suggestion
    measure_repository.dart     named per-ingredient measures
    measure_authoring.dart      the one rule for authoring a measure's label
    serving_measure.dart        the label's serving, kept as one measure
    price.dart                  receipt, lines, PriceObservation, pricePer100,
                                packInBasis
    price_repository.dart       the price ledger's reads and writes, ReceiptName
    usda_probe.dart             the probe interface
    apply_draft.dart            how a barcode draft lands on the form
    label_reading.dart          one photographed label, read — the Dart half
                                of `_shared/label_types.ts`
    label_read_repository.dart  the label reader's seam
  data/
    ingredient_repository_impl.dart  SqliteIngredientRepository
    measure_repository_impl.dart     measures, merge-on-read for duplicate labels
    price_repository_impl.dart       the ledger's watched reads and its writes
    name_holder.dart                 nameHolderFor — the namespace question as SQL
    usda_probe_impl.dart             the `probe_usda` RPC
    remote_label_repository.dart     the `read-label` edge function
    label_read_provider.dart         that reader, or a refusal when unconfigured
    ingredient_providers.dart        keepAlive repo providers + watch streams
  presentation/
    ingredient_list_view.dart    the manager list
    ingredient_detail_view.dart  the page: fact sheet and form
    ingredient_facts.dart        the fact sheet's lines
    ingredient_view_models.dart  IngredientForm — the draft and its Save
    ingredient_picker.dart       the picker and AddNewIngredientRow
    quantity_unit_sheet.dart     quantity + unit chips, manage measures
    unit_chips.dart              UnitChipRow — the app's one chip row
    measures_editor.dart, measure_delete.dart   add/remove measures; the
                                 delete gate while a recipe uses one
    density_entry.dart, piece_weight_entry.dart "1 tbsp weighs __ g" and
                                 "1 piece weighs __ g", shared by both hosts
    macro_fields.dart, serving_row.dart, macros_doubt_line.dart
                                 the macro keypad, per-serving mode, the
                                 panel-disagrees line
    macros_format.dart, macro_line_text.dart    the macro line as string and
                                 widget; the one display rounding rule
    label_photo_door.dart        pickLabelPhoto — camera or gallery, one photo
    usda_pick_sheet.dart, draft_card.dart       USDA short-list; barcode result
    price_sheet.dart, price_fields.dart         the price sheet; StoreChipRow,
                                 PackField, PriceDerivedLine (shared with
                                 receipts)
  barcode/        scan → lookup → draft
    barcode_add.dart         scanBarcodeForDraft — the only public door
    barcode_scan_sheet.dart  camera reticle + a typed-number field
    off_lookup.dart, off_lookup_provider.dart   the Open Food Facts GET
    off_mapper.dart          payload → draft, PURE DART
    ingredient_draft.dart    the hand-off type — a sketch, never a row
```

## Rules

### The form

- **The form is the add flow.** Every add-new door pushes `/ingredients/new`;
  a picker pushes it over its own sheet (`context.pushOnceFor`) and awaits the
  row.
- **A new row is saved complete or not at all.** The create dock has one
  `Save`, live only while `IngredientFormDraft.completable` holds. A stored
  stub keeps both `Save` and `Mark complete`.
- **Nothing is written until Save**
  ([ADR-0011](../../../../docs/decisions/0011-one-save-one-write.md)). The form
  holds one `IngredientFormEdit` and `saveForm` applies it in one transaction.
  Measures and aliases travel as deltas, so a stream that failed to load is
  never written back as a narrowed set.
- **Honest numbers, never zeros** (invariant 3). A stub shows its badge, not
  0 kcal. Macros gate `complete`; density does not. A prefill fills fields and
  stops; confirming is a human act and reversible (`unconfirm`).

### Names

- **Names and aliases are one namespace**, keyed by `match_text`
  (`name_namespace.dart`). The form refuses a taken name when the field is
  left, and `saveForm` asks again inside the write transaction
  (`nameTakenFailure`). Every alias writer goes through `nameHolderFor`;
  `test/structure/alias_writes_ask_the_namespace_test.dart` holds that.
- The import's learning loop is silent where the form refuses, and also skips
  a phrase that is not a name (`import/domain/learnable_alias.dart`,
  [import-and-matching.md §8](../../../../docs/product-specs/import-and-matching.md)).
- A near-miss name offers `DID YOU MEAN` rows
  ([search-and-matching.md §4](../../../../docs/design-docs/search-and-matching.md)).
  On `/ingredients/new` a tap pops the form with the existing row; on a stored
  row the names are only shown — nothing merges rows.
- **There is no unique index**: two offline devices must each be able to mint
  a row and converge, so the app refuses a duplicate instead.
- **A rename rewrites `match_text`** through `normalizeMatchText` in the same
  statement. `test/features/ingredients/normalize_vectors.json` pins the Dart
  and TS normalizers together.

### Reading a label

`Read a label` is the third door in the form's `FILL IT IN FROM` row, and the
one for a pack no database knows. It opens the app's own photo intake — camera
or gallery, so a screenshot of another tab counts — takes **one** photo of the
nutrition panel and posts it to the `read-label` edge function, which returns
what the panel PRINTED and nothing else: the serving as printed, the five
macros per serving, and a per-100 column only where the label prints one. Every
figure is nullable, and a null is "not printed, or not legible" — never a zero
and never a derivation. Where the label printed a per-100 column that column
fills the fields directly, because deriving per 100 from the serving would
round the label's own number away; where it printed only a per-serving column
the form enters per-serving mode and `Macros.per100From` does the arithmetic,
exactly as a typed-in panel does. A figure the label did not print leaves its
field alone, unless the reading moved the mode or the basis, where the text
that is there is about a different hundred. The fill is a draft like every
other: the card says `From a label · not saved`, `Undo the fill` puts the
fields back, and the Save stamps `source = label_photo` with no label and no
score, because a photograph names no food. What could not be read is said on
the form's own feedback line rather than hidden. Server side:
[`supabase/functions/read-label`](../../../../supabase/functions/read-label/README.md).

### USDA and the barcode

- **A USDA pick fills the draft**; the form's Save lands it. The query is the
  name in the field. `declineUsdaPrefill` (*Not this food*) is the one USDA act
  that writes on its own, leaving `source = usda_declined`.
- **No machine matches on its own.** `usda_food` never syncs
  ([ADR-0005](../../../../docs/decisions/0005-two-tier-vocabulary.md));
  the app asks the read-only `probe_usda` RPC. `source_score` is coverage, not
  confidence — shown, never acted on.
- **The food is named, never keyed.** Surfaces print `source_label`, not an
  FDC id. `sourceProvenanceLine` is the one line under a row's name on the
  manager list and the import review; the picker prints none.
- **`source_edited`** (migration 0034) is set by `saveForm`, `setDensity` and
  `clearDensity`, and only when macros, the macros basis or the density change
  on a lookup-filled row (`isLookupFilled`). A fresh pick and *Not this food*
  clear it. Nothing server-side writes it.
- **The barcode returns an `IngredientDraft`**, and `applyDraft` lands it:
  fill what is empty, keep what was typed, stamp `off:<barcode>` only where
  there was no source. `packLabel` names the product or returns null.
- **Which 100 the panel is per** is the mapper's `_basisFor`: Open Food Facts
  files per-100 ml labels under `*_100g` keys, so it reads
  `nutrition_data_per`, then the pack's net quantity, then the serving unit,
  then the beverages category. A basis never implies a density.

### Units

- **Admission is explicit and per-ingredient**
  ([ADR-0008](../../../../docs/decisions/0008-unit-admission-model.md)).
  `allowed_units` is materialized at creation and then user-owned. A density
  unlocks the other mass/volume family
  ([ADR-0009](../../../../docs/decisions/0009-density-unlocks-both-families.md)),
  and a family is admitted whole
  ([ADR-0014](../../../../docs/decisions/0014-all-to-all-admission.md)).
  `allowed_units.dart` and the SQL functions are mirrors pinned by shared
  vectors — change one, change both.
- **A default unit the row cannot say blocks Save** (`defaultUnitOfferFor`):
  a default outside the basis family with no density, or a `piece` default
  with no piece weight. The form flags it with a one-tap fix and refuses the
  write; nothing is rewritten silently.
- **A piece weight is a row fact and is what admits `piece`**
  ([ADR-0015](../../../../docs/decisions/0015-piece-weight-is-a-row-fact.md)).
  Setting `piece_basis_amount` unions `piece` in; clearing strips it. A measure
  that weighs what the piece weighs is the row's word for one (`wholeMeasureOf`,
  [ADR-0016](../../../../docs/decisions/0016-a-measure-that-weighs-a-piece-is-its-word.md)).
  On the form the editor reports intent; in the quantity sheet it writes on
  tap, because that host has no Save.
- **`UnitChipRow` is handed a prebuilt `UnitChoiceOffer`** and knows nothing
  about ingredients, so a sub-recipe component's dock wears it too
  (`recipes/domain/component_units.dart`).
- **One filter for every ingredient surface**: `allowedUnitChoicesFor`. It
  never offers a measure whose label names a volume unit, nor the row's
  serving; both stay selectable where a line already says one. A surface with
  nothing stored opens on `firstOfferedChoice`.

### Price

Doctrine is
[ADR-0017](../../../../docs/decisions/0017-a-cost-is-a-unit-price-never-an-allocation.md).

- **A price is a `receipt_line`** (migration 0044); a hand-typed price is a
  one-line `manual` receipt. The per-basis figure is derived at read time by
  `pricePer100` — paid (`cents - discount_cents`) over
  `count × pack_basis_amount` — and never stored.
- **The pack is kept twice.** `pack_basis_amount` is what a figure is derived
  from. `pack_amount` + `pack_unit`, or a `measure_id` with a count, is what
  the person said (migration 0046), so the ledger prints `for 1 lb`.
- **The gate is at entry.** `packInBasis` refuses across mass and volume
  without the row's density; the sheet's dock says why and Done is refused.
- **A line that is not a price is not a zero.** No pack, not food, no
  ingredient or nothing paid mean no observation; the Price group says
  `— none yet`.
- **A manual price reopens `PriceEditor`** and Done is an UPDATE
  (`updatePrice`); Delete soft-deletes the line and its one-line receipt. A
  photographed line opens `/receipts/:id` instead.
- **One Price group on both the fact sheet and the form.** It is the one
  section the form's dock does not hold: the sheet writes on Done and is
  handed the stored row, never the draft. `/ingredients/new` offers no price
  door.
- **`On receipts`** lists the names this row was matched to on receipts
  ([import-and-matching.md §12.4.1](../../../../docs/product-specs/import-and-matching.md#1241-what-the-household-itself-remembers)).
  It is not the alias list. `watchReceiptNames` groups on
  `UPPER(TRIM(name_printed))`, the server's recall key. Fact sheet only,
  because a tap leaves the page.

### Writes

- **Delete is a soft delete, refused while anything live names the row** —
  recipe lines, plan entries or week overrides (`DeleteRefused`, mirroring
  migration 0041). Aliases go with the row.
- **Writes are view-safe.** Local PowerSync tables are views: plain
  INSERT/UPDATE only, never `ON CONFLICT`.
- **Mutations go through the keepAlive repo provider**, never a throwaway
  notifier held across an async gap.

## Tests

`test/features/ingredients/` mirrors the files above; repository tests run on a
real `PowerSyncDatabase`, and `barcode/` runs against committed fixtures with
no network. `density_entry_test` loads the real fonts
(`test/helpers/fonts.dart`) because the test binding's fallback glyphs change
the run count. Server-side: `supabase/tests/unit_admission.sql`,
`receipts.sql` and `source_edited.sql` (pgTAP).
