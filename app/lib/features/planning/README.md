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
    plan_change.dart              a change set written whole or not at all
                                  (Ask Ansi's card), PlanChangedError
    week_variant_repository.dart  this week's variant, WordlessOverrideError
    use_up.dart                   last week's spare food, scoreUseUp, rankUseUp
    use_up_repository.dart        what Use up reads about last week, one read
  data/           SqlitePlanningRepository, SqliteWeekVariantRepository,
                  SqliteUseUpRepository (last week through the cook plan,
                  the shop's derivation and the receipt packs), providers
  presentation/
    week_view.dart            the phone Week: day cards, the add flow, the band;
                              the header holds the Leftovers door and Ask
    week_wide.dart            the wide Week: agenda left, day pane right
    week_header.dart          the week switcher
    week_in_the_location.dart the viewed week in the URL, shared by Week/Cook/Shop
    recipe_picker_sheet.dart  the add flow's one door (Recent · Books · Favorites)
    use_up_block.dart         Leftovers: fridge, freezer (soonest to go off
                              first; a pot not cooked yet `cooks Sat`), then
                              recipes using spare food; LeftoverTag (a
                              snowflake on the freezer's blue)
    whats_left_sheet.dart     the spare food and the ranking's cut
    use_up_view_models.dart   useUp: last week's spare, scored and offered
    confirm_meal_sheet.dart   slot, eaters, portions; macros fold for a meal
                              out; From leftovers · Cook fresh for a dish
                              with a pot to eat from
    meal_editor_sheet.dart    edit a placed meal; a leftover meal's source
                              (`cooked last Sat`, `cooks Sat`) and,
                              before its day, Cook fresh instead (with Undo,
                              `eatFromLeftoverAgain`); the variant
                              door at its foot
    meal_fields.dart          controls both sheets share
    week_macro_widgets.dart   day foot, week band, the spent line
    week_recipe_band.dart     the line-size week strip on a recipe page
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
- **A meal in a cooking** (`PlanEntry.cooking`) is a recipe meal linked to
  one pot: its group's own meals from the first tick on, and a meal picked
  from it (see the `cook_plan` README). It is bought and costed in the
  cooking's week only (`CookPlan.cookings`, `eatenFromEarlier`), macros and
  ticks count it like any meal, and its Week row says `leftover` where a
  cook marker would be once the pot is cooked, or always for food said by
  hand (`eatsFromAPot`; `LeftoverMealTag`: the fridge's green, or the
  freezer's blue when it is eaten from the freezer on its day). A move keeps
  the link; copy last week carries it as a meal to cook. The last release's
  `leftover_of` and `from_leftover` are read-only
  (`test/structure/leftover_meal_seam_test.dart`).
- `test/structure/plan_entry_kind_seam_test.dart` holds this: no wildcard, no
  null-column kind test, and both SQL derivations state their kind in `WHERE`.

## A change set

`applyPlanChanges` writes adds, removes, moves and eater changes in one
transaction — what an Ask Ansi card writes on Confirm. Every change to an
existing meal carries the meal as the card drew it, and the transaction
re-reads each one; a meal edited, moved or removed meanwhile throws
`PlanChangedError` and nothing is written. A move is a remove and an add of
the same row, as on the Week.

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
   footer offers `＋ note it` for a meal eaten out. With nothing typed it
   leads with *Leftovers*: the fridge rows good for the day, then the freezer
   rows, each soonest to go off first (`leftoversGoodOn` over the shelves; a
   row in words names no recipe and is left out), and the pots not cooked
   yet (`cooks Sat`): a cooking nobody ticked, or an earlier week's meals no
   cooking holds yet (`LeftoverShelves.pots`; the day's own week is left
   out, since a meal there already shares its batch). Each is a
   `PickedLeftover`, then
   the recipes that use the most of last week's spare food. That block and
   *Already this week* lead the list's own scroll, so however many rows it
   offers the recipes stay in reach. Returns a `PickedMeal`.
2. **The quantity sheet**, for an ingredient only, opened filled in with its
   usual amount (`ingredients/domain/default_amount.dart`): the last meal of
   it that stated one, else one of its word for one (`1 pot`), else one
   piece; with none of those, empty on the row's first chip.
3. **`showConfirmMealSheet`** — slot, eaters, portions (`plan_entry.portions`,
   null = track the eaters; a step back to the eaters' own total clears it). A meal out gets an optional per-portion macros
   fold; left empty or half-filled, the meal is placed and named as uncounted.
   A leftover's card caps the portions at what is left; the meal links to
   its cooking (`addEntry(cooking:)`; a pot not born yet is born by the
   pick). A pot not cooked yet caps nothing: the meal's portions add to what
   it makes (*Cooked with it, bought once*). A recipe with a pot the day can
   eat from (the first `leftoversGoodOn` offers for it) asks **From
   leftovers · Cook fresh** with neither picked, wherever it was found, and
   *Add* waits for one; From leftovers links the meal to that pot.

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
