# Feature: recipes

Create a recipe, group its ingredients, scale it, and read it: the recipe page,
the editor, the method, and a component line that counts another recipe.

## Layout

```
recipes/
  domain/         Recipe/IngredientGroup/LineItem (Freezed), the repository
                  interfaces and every rule below — PURE DART
  data/           SqliteRecipeRepository and SqliteRecipeMeasureRepository over
                  the local PowerSync SQLite, Riverpod providers
  presentation/   Forui views (recipe page · editor · method editor · sheets)
                  and their Riverpod view models
```

- **Scaling is a view concern** — `scaling.dart` scales displayed quantities;
  the stored recipe is untouched, and imprecise units never scale.
- **Save diffs children, never replaces them.** PowerSync queues ops literally,
  so `saveRecipe` UPDATEs a kept id and soft-deletes a dropped one; a DELETE of
  a kept row would tombstone it for every other device.
- The ingredient picker lives in `features/ingredients`; shelf-life inputs
  (keeps / freezable / freezer days) feed the cook plan's clustering.

## The ingredient line

**One layout on every surface** — `[amount] [name] [note]`, the amount in its
own `kLineAmountWidth` column. The recipe page is the reference; the editor and
the import review's collapsed row print the same shape.

**The editor's list is one flat draggable list.** Group headings are rows in
it, so reordering a line and moving it between groups are one gesture
(`domain/line_reorder.dart`, written over `List<List<T>>` so the import review
drags by the same arithmetic). It uses `SliverReorderableList` from
`widgets.dart`, not the Material `ReorderableListView`.

- **The grip is the only thing that drags** (`DragGrip`); an open card closes
  when a drag starts (`collapseEpoch`).
- **A moved line keeps its id**, so every method chip pointing at it still
  does and the save issues an UPDATE.
- **A group emptied by a move is kept** — the heading is the cook's.

**The editor's line is the review's card** (`presentation/line_card.dart`): the
head (identity, bin, chevron), the `AMOUNT`, `UNIT` and `NOTES` rows, and the
`optional` toggle. The review adds the match cascade, `from source:`, flags and
the Save gate; the editor adds *used in N steps*, the component variant and
remove-with-chips. A tap anywhere on a collapsed row opens it, the head is the
identity door, and rows are bare at rest (`LineCard.borderAtRest`).

- **A note is printed by one function** (`noteSpans`), held by
  `test/structure/one_note_grammar_test.dart`.
- **`OptionalTag`** is the tag on a row and, handed an `onToggle`, week mode's
  switch; `OptionalFlagToggle` is the card's control and the one door that sets
  the flag on a recipe line.
- **A line's own figures** (the `⋯` toggle) print under the name and move with
  the scaler; the panel underneath is per serving and does not.

## The method

`shared/method_step_text.dart` prints prose with live numbers in it: an
ingredient chip is the word in `herbDeep` with its amount in a mono pill, a
timer chip keeps its outlined pill, and a chip whose imprecise amount the prose
already says prints no pill.

On the recipe page a tap rules a chip off, and a tap elsewhere on the step rules
off the prose and every chip in it. The set is ephemeral — a `useState` keyed
positionally (`s2`, `s2:c0`) — and a line this week leaves out reads muted,
never ruled. Full cook mode is a [backlog](../../../../docs/exec-plans/backlog.md)
row.

## The header form

`presentation/recipe_header_form.dart` is one widget with two hosts — the
editor notifier and the import review's controller — rendering
`kRecipeHeaderSections` over a `RecipeHeaderHost`. The rules every setter holds
(both halves of a yield or neither, no freezer window on a dish that does not
freeze) are `domain/recipe_header_edits.dart`.

## The panel: macros or cost

The strip closing the Ingredients tab reads one of two things about the same
lines, chosen by a `Macros | Cost` chip pair held for the session
(`CostReading`); `ShowLineFigures` prints whichever under each line.

- **Macros** come from `summarizeRecipeMacros`, the summation the pickers share.
  An incomplete recipe shows the badge and its reason, never a number; `NOT
  COUNTED` and `OPTIONAL` name what the total left out by rule. Each reason is
  a door to its fix — `needs a piece weight` opens the **ingredient's** form
  ([ADR-0015](../../../../docs/decisions/0015-piece-weight-is-a-row-fact.md)).
- **Cost** (`recipe_cost.dart`) is the same walk through the same conversion
  (`line_basis.dart`) with a price per basis unit multiplied in
  ([ADR-0017](../../../../docs/decisions/0017-a-cost-is-a-unit-price-never-an-allocation.md)).
  A line with no price is named under `UNPRICED` and takes the recipe's figure
  with it; what the priced lines come to prints as an `at least` floor
  (`pricedCents`), a field of its own, so the week, the shop and a parent
  recipe still read null. `OLDEST` names the stalest price month.
- Money never enters the macro record nor macros the cost one
  (`test/structure/cost_and_macros_stay_apart_test.dart`). Costs ride their own
  streams (`watchRecipeCosts`, `watchVariantRecipeCosts`) because a cost moves
  when a receipt lands.

**The page holds the week it was opened from.** A `?week=` link the week still
plans (`weekRecipePlacement`) draws that week's effective lines read-only, and
the `optional` tag becomes the switch: one tap writes the week's `include` row
through `WeekVariantRepository.setLineIncluded`, and the panel reads the week's
own re-summation (`watchVariantRecipeMacros`).

## A component line and a recipe's own measures

The model is [ADR-0018](../../../../docs/decisions/0018-a-recipe-measure-is-a-named-amount.md):
a recipe measure is a named amount in a unit, and a component line is said in a
catalog unit **or** in one of the target's measures. `LineItem.unit` is null
exactly when `recipeMeasureId` is set — the database's
`num_nonnulls(unit, recipe_measure_id) = 1`.

| File | What it owns |
|------|--------------|
| `domain/component_math.dart` | `resolveComponentAmount`: how many batches a line asks for, as a sealed `ComponentAmount` — resolved, or an honest refusal. Never "assume one batch". |
| `core/units/recipe_measure.dart` | The measure itself, beside `measure.dart`. |
| `domain/recipe_measure_authoring.dart` | `authorRecipeMeasure`: the label rule, the refusal of a catalog unit's name, and the `makes` gate; `recipeMeasuresOrphanedBy` is that gate read backwards. |
| `domain/component_units.dart` | `componentUnitChoices`: the chip offer — the target's measures (`wholeMeasureOfRecipe` first), then `batch`, then the yields' families — as the same `UnitChoiceOffer` the one chip row (`ingredients/presentation/unit_chips.dart`) draws. |
| `domain/line_basis.dart` · `effective_lines.dart` | The one conversion macros and cost share; the one seam choosing which lines a derivation runs over. |
| `data/recipe_measure_repository_impl.dart` | The only SQL that names `recipe_measure`: `loadRecipeMeasures` (one query per load for the whole household), `writeRecipeMeasures` (the diff inside `saveRecipe`, before the lines), `countRecipeMeasureReferrers` (the delete gate) and the direct doors. |
| `presentation/recipe_measures_editor.dart` | The one list-and-form. It knows no repository: it takes yields, measures and `onAdd` / `onRestate` / `onDelete`, and wears the shared `MeasureForm`. |
| `presentation/component_quantity_sheet.dart` | Where a measure is chosen. It returns a `ComponentQuantity` carrying exactly one denomination. |

**Two doors write a measure, and the difference is whether the host has a
Save** (ADR-0011). The header form's MEASURES section, under MAKES, defers into
`saveRecipe` — and the import review hosts it too, prefilling nothing. There
the host owns the delete gate (`mayDeleteRecipeMeasure`, with a **Show me
where** door), the orphan warning (`measuresOrphanedBySave()`, which warns and
never refuses) and the printing of `RecipeMeasureRefused`.

**Its second host is the `＋` on a component's quantity dock**
(`presentation/component_quantity_sheet.dart`), aimed at the **target** recipe —
the sauce being measured, not the one being written — because that is the recipe
the word belongs to. It has no Save, so each callback is a write through
`RecipeMeasureRepository` wrapped in `ref.write`: a `RecipeMeasureRefused`
becomes `RecipeMeasureTurnedDown` and prints under the field, any other failure
is `RecipeMeasureNotLanded` and has already been said by the write door. Three
things follow from a door opened mid-sentence — the sheet **watches**
`recipeMeasuresProvider(target.id)` rather than trusting the snapshot its caller
passed, so a coined word is a chip on return with nothing reloaded; the word is
**selected** as it lands, so back reads `3 blob`; and the selection is re-read
from the live row every build, so a re-statement follows through and a
retirement lights no chip. Retiring the word the open line was counting
reconciles the choice to the yield's own unit with a note — Done must never
write a tombstone. The `＋` is drawn for the two recipe-editor doors, the method
editor's and week mode's, and **not** for the import review's two, which strip
the target's words for the same reason: a review line has no column for a
pointer.

Every door onto a component line opens that sheet: the recipe editor's two, the
method editor's and week mode's amount cell. A line whose measure has gone
lights no chip and keeps its number and its pointer until a chip is tapped.

Three engineering facts hold the feature up:

1. **Refuse before the write, not on upload.** A rejected upload makes the
   PowerSync connector drop the whole crud transaction, so `saveRecipe` throws
   `UndenominatedLineError` and `AmountlessLineError`, and `saveOverrides`
   throws `WordlessOverrideError`. `LineItem`'s asserts are compiled out of a
   release build.
2. **The gates are the repository's.** The `makes` gate reads the yields off the
   recipe row inside the write's own transaction, and runs only on a measure the
   Save states — one carried through unchanged is never re-authored, so a
   `makes` edit that orphans it warns instead of trapping the editor. A
   retirement is refused (`RecipeMeasureInUse`) while a line or a week's
   override still says the measure, never cascaded.
3. **Every watch that reads a measure selects a column from `recipe_measure`.**
   SQLite drops a LEFT JOIN whose columns go unused, and PowerSync never fires
   for a table that was dropped.

A row whose `unit` this build's catalog does not know is skipped on read, so a
line naming it reads `ComponentMeasureMissing` rather than a wrong share.
