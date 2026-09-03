# Feature: ingredients

**Roadmap:** steps 1, 7.6–7.8 and **8.5** (see `docs/exec-plans/roadmap.md`;
the manager's plan is `docs/exec-plans/completed/0020-ingredients-manager.md`).

The household's controlled vocabulary and everything that reads or writes it:
the **picker** recipes and shopping select from, the **quantity + unit** entry
surface (chips, measures, density), and the **manager** — the screen where the
vocabulary is actually browsed and edited, including turning a bare `stub` into
a `complete` ingredient.

**The client never fuzzy-matches for a machine decision** (ADR-0004). Search
here is deterministic retrieval for a human to pick from, over the ~300 synced
household rows. The one network call in the feature is the barcode module's
Open Food Facts read — an exact-key fetch by product code, not matching.

## The surfaces

```
/ingredients            ingredient_list_view.dart    the whole vocab, stub band on top
   └── /ingredients/:id ingredient_detail_view.dart  the flesh-out form (edit + confirm),
                                                     which also scans a barcode into itself
showNewIngredientSheet  new_ingredient_sheet.dart    manual · USDA · barcode — THE add door;
                                                     hands the row back, pushes nothing

showIngredientPicker    ingredient_picker.dart       recipe editor, shopping top-up
   └── AddNewIngredientRow: sheet → form → back → resolves with the re-read row
showQuantityUnitSheet   quantity_unit_sheet.dart     every quantity+unit in the app
        └── manage measures + DensityEntry (density_entry.dart)

scanBarcodeForDraft     barcode/barcode_add.dart     the barcode module's one door
applyDraft              domain/apply_draft.dart      how a draft lands — sheet and form alike
```

`/ingredients` is a **pushed** route reached from Library ▸ ⋯ ▸ Ingredients, not
a fifth bottom-nav tab (plan 0020 D8): the four tabs are the cooking loop, and a
vocabulary is reference data.

**No path creates an ingredient without landing on the flesh-out form** (plan
0025 D3, owner-ruled: "move away from allowing stubs; ideally only the seeded
rows are stubs"). Every add-new — the manager's ＋, the editor picker's footer,
the shopping top-up, the import review's create-new — opens the same sheet; the
sheet creates the row and hands it back; the host pushes the form. A picker
pushes it *over its own sheet* through `context.pushOnceFor` and awaits the
pop, then re-reads the row, so the quantity sheet that follows offers the
units the form just set. Backing out unconfirmed still hands the row over — it
exists, badged `stub` — because D3 forbids minting a stub *as a side effect*,
not a human leaving a form early. The seed's stubs are the one exception, and
they are curation debt, not a path.

## Layout

```
ingredients/
  domain/         PURE DART (no package:flutter)
    ingredient.dart          Ingredient + IngredientAlias (Freezed)
    ingredient_repository.dart  the interface + IngredientEdit + DeleteOutcome
    allowed_units.dart       ADR-0008/0009 admission — the Dart mirror of
                             default_allowed_units() / density_unlocked_units()
    normalize.dart           the PHRASE normalizer — Dart twin of normalize.ts
    search_query.dart        the character-level normalizer (search + matching)
    measure_repository.dart  named per-ingredient measures
    apply_draft.dart         the one rule for landing a barcode draft on a row:
                             fill what is empty, keep what a human typed, stamp
                             `off:<barcode>` only where there was no source
  data/
    ingredient_repository_impl.dart  SqliteIngredientRepository — read + write
    measure_repository_impl.dart     measures, with merge-on-read for dup labels
    ingredient_providers.dart        keepAlive repo providers + watch streams
  presentation/
    ingredient_list_view.dart   the manager list
    ingredient_detail_view.dart the flesh-out form
    new_ingredient_sheet.dart   the add flow's three sources (USDA = a search)
    usda_pick_sheet.dart        "Choose another": the USDA short-list, and the
                                candidate rows the add sheet's USDA leg shares
    ingredient_picker.dart      picker v2 (7.7) + the add-new chain's row
    draft_card.dart             the barcode result card, drawn by sheet and form
    quantity_unit_sheet.dart    quantity + unit chips (7.7), manage measures
    density_entry.dart          g/ml ⇄ "1 tbsp weighs N g" (7.8), shared
    macros_format.dart          the per-100 macro line
  barcode/        the scan → lookup → draft module (8.5 lane B)
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
- **Macros gate `complete`; density does not; confirming is a human act**
  (plan 0020 D5). `confirmStub` throws without macros, so the gate holds below
  the disabled CTA. A USDA or barcode prefill fills fields and stops. Confirming
  is reversible (`unconfirm`).
- **Unit admission is explicit and per-ingredient** (ADR-0008). `allowed_units`
  is materialized at creation and thereafter **user-owned** — extended by
  writes, never silently re-materialized. Since
  [ADR-0009](../../../../docs/decisions/0009-density-unlocks-both-families.md) a
  density unlocks the other mass/volume family whatever the default's family;
  `setDensity` unions that in the same transaction, and `clearDensity` strips
  what the density granted (D4b). `allowed_units.dart` and the SQL function are
  mirrors pinned by shared vectors — change one, change both.
- **A rename rewrites `match_text`** through `normalizeMatchText` in the same
  statement (D6). The server writes `match_text` with the phrase rules; before
  the port the app wrote only the character rules, so a locally created stub
  carried text the next import's cascade would never find. Vectors in
  `test/features/ingredients/normalize_vectors.json` are copied from
  `normalize.test.ts` and pin the two implementations together.
- **Delete is refused while a live recipe line points at the row**, with the
  count (owner ruling). It is a soft delete, and the aliases go with it — an
  alias outliving its ingredient resolves to nothing.
- **Writes are view-safe**: local PowerSync tables are SQLite views, so every
  statement is a plain INSERT/UPDATE — never UPSERT.
- **Mutations go through the keepAlive repo provider**, never a throwaway
  notifier after an async gap (the standing `LibraryActions` lesson).

## What the server does, and why it has to

`usda_food` never syncs to a device (ADR-0005), so the app cannot look an
ingredient up in it. The enrichment happens **in the database** instead
(migrations `0014`/`0015`, plan 0020 D7): an
`after insert or update of canonical_name` trigger probes `usda_food` by
`match_text` and copies density + macros onto a **bare** stub — inside the
client's PowerSync upload transaction, so it is one indexed trigram probe and
every error is swallowed rather than failing the upload. The row stays `stub`.
A companion trigger extends `allowed_units` when a density lands from anywhere.

Since `0016` the same probe is also a read-only RPC (`probe_usda`), so the
app can ask at creation and from the form without waiting for the round
trip; since `0027` (plan 0027 front U) the probe **names its answer** —
`usda_probe` returns `description` + `category` and takes a limit — and both
writers stamp `source_label` + `source_score` beside `usda_fdc:<id>`. That is
what lets the form say *which* food filled a row, offline, at the head of its
macros section, with two doors: **Not this food** (`declineUsdaPrefill` — one
write: the density and its D4b strip, the macros, `source = usda_declined`,
which the 0015 WHEN clause never refills) and **Choose another ▸**
(`usda_pick_sheet.dart` over `probe.search`, the pick applied through
`applyUsdaProbe(explicitPick: true)` — the only thing that writes over a
decline or over the prefill's own fill; numbers a person typed are never
overwritten). The New-ingredient sheet's USDA leg is the same search, and
Create applies the pick as the row is made. Nothing in any of it confirms a
row (U-D4).

## Tests

- Domain: `allowed_units_test` (the ADR vectors, shared with
  `supabase/tests/unit_admission.sql`), `normalize_test` (the shared JSON
  vectors), `search_query_test`.
- Repo on a real `PowerSyncDatabase`: `ingredient_repository_test`,
  `measure_repository_test` — search/recents, stub creation, density
  round-trips, edits, confirm/unconfirm, delete refusal, aliases.
- Widget: `ingredient_manager_test` (list band, form, confirm gate, delete),
  `ingredient_picker_test`, `quantity_unit_sheet_test`.
- Barcode: `barcode/` — mapper and lookup against committed fixtures (no
  network), the scan sheet's failure states, and the public door's contract.
- Server-side: the triggers are pinned by `supabase/tests/unit_admission.sql`
  (pgTAP), not by anything in this feature — and by nothing on-device yet
  (tech-debt tracker).
