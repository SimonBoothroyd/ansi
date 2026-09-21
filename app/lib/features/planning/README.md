# Feature: planning

The **Week** tab: one active week, several entries per (day, slot), eaters per
meal, copy last week. It is the input to the derived cook plan and shopping
list — you say what you want to eat, nothing about batching
([plan 0005](../../../../docs/exec-plans/completed/0005-week-planning.md)).

A planned meal is a **recipe**, a **bare ingredient** (a yoghurt) or a **meal
eaten out** (its words and, when stated, its macros) — exactly one of the three
(`plan_entry_target_xor`, migrations 0033 and 0045).

## Files

```
planning/
  domain/         PURE DART
    planning.dart                 Member, PlanEntry, PlanEntryKind, WeekPlan,
                                  demandPortions, mealSlotRank, defaultMealSlot
    week_macros.dart              sumPlannedMacros, ingredientPortionMacros
    week_cost.dart                the week's cost to cook, ingredientPortionCost
    planning_repository.dart      read/write contract
    week_variant_repository.dart  this week's variant, WordlessOverrideError
  data/           SqlitePlanningRepository, SqliteWeekVariantRepository, providers
  presentation/
    week_view.dart            the phone Week: day cards, the add flow, the band
    week_wide.dart            the wide Week: agenda left, day pane right
    week_header.dart          the week switcher
    week_in_the_location.dart the viewed week in the URL, shared by Week/Cook/Shop
    recipe_picker_sheet.dart  the add flow's one door (Recent · Books · Favorites)
    confirm_meal_sheet.dart   slot, eaters, portions; macros fold for a meal out
    meal_editor_sheet.dart    edit a placed meal; the variant door at its foot
    meal_fields.dart          controls both sheets share
    week_macro_widgets.dart   day foot, week band, the spent line
    week_recipe_band.dart     "Planned Tue · Sat this week" on a recipe page
    week_widgets.dart         Pill, EaterAvatar, PortionsChip, OutTag, …
    week_format.dart, copy_last_week.dart, household_section.dart
    week_variant_door / _editor / _format / _view_models
```

## The entry kinds

- An **ingredient** entry states one portion: `quantity` + `unit`, or a
  `measure_id` with `unit` as the count fallback. Amount columns are refused on
  the other two kinds.
- A meal **eaten out** states its `label` and optional per-portion `macros`.
  Null macros mean not stated, never zero.
- Every kind carries `eaters` and the `portions` override, and multiplies by
  demand.
- **Read `PlanEntry.kind`, never a null `recipeId`.** Every derivation switches
  on the kind with no wildcard:
  - week macros weigh an ingredient meal from its row
    (`ingredientPortionMacros`) and a meal out from its stated figures, or name
    it as uncounted (`MealExclusion.outNotStated`);
  - the cook plan ignores both;
  - the shopping list buys an ingredient meal
    (`SqliteShoppingRepository._derivePlannedIngredients`) and nothing for a
    meal out;
  - copy last week carries every kind whole.
- `test/structure/plan_entry_kind_seam_test.dart` holds this: no wildcard, no
  null-column kind test, and both SQL derivations state their kind in `WHERE`.

## This week's variant

A recipe can be cooked differently for one week without being edited. The
variant is per **(week, recipe)**, stored as `week_recipe_line_override` rows
(replace, add, exclude, include), recomputed whole on save.

- **One door**: a row at the foot of the meal editor sheet, opening the recipe
  editor's week mode (`/recipes/:id/edit?week=`).
- **`effectiveLines` is the one seam.** Shopping, the cook plan and week macros
  all read overrides through it. Amounts are absolute.
- Week macros re-sum only a varied recipe; the rest borrow the Library's
  per-recipe figure.
- Copy last week does not carry a variant, and says which recipes it left.
- A component override may carry a `recipe_measure_id` with `unit` NULL
  ([ADR-0018](../../../../docs/decisions/0018-a-recipe-measure-is-a-named-amount.md)).
  A measure with no number is refused before the write
  (`WordlessOverrideError`), because the server would refuse the upload and
  drop the whole transaction. The week's watches join `recipe_measure`.

## The add flow

`_addMealFlow` in `week_view.dart`:

1. **`showRecipePickerSheet`** — one door for all three kinds. Typed words
   search recipes and the household vocabulary; when they hit nothing, the
   footer offers `＋ note it` for a meal eaten out. Returns a `PickedMeal`.
2. **The quantity sheet**, for an ingredient only, opened on the row's default
   unit.
3. **`showConfirmMealSheet`** — slot, eaters, portions (`plan_entry.portions`,
   null = track the eaters). A meal out gets an optional per-portion macros
   fold; left empty or half-filled, the meal is placed and named as uncounted.

Both sheets open on `defaultMealSlot`, the day's first unfilled default slot.
Recipe rows show shelf-life chips and a "same batch" hint
(`batchHintFor`); snacks and meals out do not.

## Model notes

- **A week is keyed by the date of its first day**, and
  `plan_entry.day_of_week` is the offset from it, 0..6. The household picks the
  first day (`household.week_starts_on`, set in `/account`); changing it
  re-homes every week on the server. `WeekShape` (`core/week_shape.dart`) is
  the only place an offset becomes a weekday name —
  `test/structure/weekday_labels_go_through_the_shape_test.dart`.
- **`plan_entry.eaters`** is a JSON array of member ids, last-write-wins.
  Demand is the sum of the eaters' `portion_factor` (`demandPortions`, printed
  as a fraction) unless `portions` is set.
- **Slots are free text.** `kDefaultMealSlots` are the four offered;
  `mealSlotRank` orders them. The slot is a field of the meal editor
  (`setMealSlot`); the day is not — a meal changes day by remove and re-add.
- **Members** are created server-side by `ensure_onboarded` and synced down;
  the app writes only `portion_factor`.

## Cost

`week_cost.dart` mirrors `sumPlannedMacros` — same entries, portions and lens
([ADR-0017](../../../../docs/decisions/0017-a-cost-is-a-unit-price-never-an-allocation.md)).

- A recipe with an unpriced line drops out whole, and the band reads
  `at least $71 to cook · 3 lines unpriced`, naming the distinct lines.
- An ingredient meal is costed from its own row (`ingredientPortionCost`); a
  meal out is passed over.
- The **spent** line (`$84.12 spent · 1 receipt · TJ's, Sun`) reads the week's
  receipts (`receipts/domain/receipt_ledger.dart`), is drawn only when a
  receipt is dated inside the week, and opens the ledger. The two figures are
  never reconciled.
- Both lines are on the phone's band only; the wide foot band carries macros.

## Not built

Recipe photos — picker thumbnails are placeholders until Storage exists.
