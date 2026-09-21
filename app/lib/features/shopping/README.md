# Feature: shopping

The **Shop** screen: the shopping list with provenance (spec §4). It sums each
ingredient's contributions from the cook plan plus manual top-ups, groups them
by aisle, and holds check-off state. The list is derived — edit the Week and it
re-sums ([plan 0007](../../../../docs/exec-plans/completed/0007-shopping-list.md)).

## Files

```
shopping/
  domain/         PURE DART (no package:flutter)
    shopping.dart             the inputs, ShoppingItem / ShoppingGroup /
                              ShoppingList, aggregateQuantities,
                              buildShoppingList, completesTheList
    shopping_cost.dart        a row's estimate and the trip's (ADR-0017)
    shopping_repository.dart  read/write contract
  data/           SqliteShoppingRepository (derive + overlay) + providers
  presentation/
    shopping_view.dart            the screen: aisles, basket, echo rows, doors
    add_shopping_item_sheet.dart  add an item or a top-up
    edit_top_up_sheet.dart        edit or remove one manual top-up
    shopping_format.dart          totals copy, pure Dart
    confetti_burst.dart           the last tick's burst, in a root overlay entry
    shopping_view_models.dart
```

## What is stored

Only what cannot be re-derived (migration `0006`):

- **`shopping_list_entry`** — one row per ingredient the user has touched
  (checked or topped up), plus free-text items. Holds `checked`.
- **`shopping_list_contribution`** — `manual` top-ups only. Cook contributions
  are derived live from the cook plan, which has no table of its own.

`SqliteShoppingRepository` runs the same `buildCookPlan` and
`loadComponentGraph` the Cook screen uses, scales each session's lines, and
hands them with the overlay to `buildShoppingList` (pure).

## Rules

- **Honest aggregation (invariant 3).** `aggregateQuantities` sums within a
  unit family, bridges mass and volume only with a density, and otherwise
  returns separate subtotals. Count units sum per unit; imprecise units never
  sum.
- **Asked for in one measure, bought in that measure.** When every quantified
  contribution names the same measure the item carries a `measureTotal` and
  reads `2 cans`, with the mass beside it and a round-up when fractional
  (`2½ lime, whole · 167.5 g → buy 3`).
- **A piece-weighted row is bought in pieces**
  ([ADR-0015](../../../../docs/decisions/0015-piece-weight-is-a-row-fact.md)).
  A row whose default unit is `piece` and whose contributions fold into one
  total carries a `pieceTotal`, marked `≈` when a plain mass or volume line
  joined. A single named measure wins over it.
- **A component said in the target's own measure is expanded**
  ([ADR-0018](../../../../docs/decisions/0018-a-recipe-measure-is-a-named-amount.md)):
  the list buys that share of the sub-recipe's ingredients. A measure the
  target no longer has buys nothing and is named in the `unresolvedComponents`
  echo row.
- **Lines left out are named.** Lines dropped by the `effectiveLines` seam — a
  recipe's `optional` flag or this week's leave-out — are listed under their
  recipe. Each optional name is a door: a tap writes this week's include
  override (`WeekVariantRepository.setLineIncluded`). A line the week left out
  is undone where it was made.
- **The basket.** Aisles hold what is still to grab; ticked rows move to one
  `IN THE BASKET` section that keeps its aisles (`openGroups`, `basketGroups`,
  `allTicked` on `ShoppingList`). `groups` stays the full list.
- **The last tick.** `completesTheList` decides, on the list as it stands
  before the write, whether this tick finishes a list of more than one item. A
  completion arriving by sync plays nothing. The view plays a haptic and the
  confetti; reduced motion keeps only the haptic.
- **Lifecycle.** An item shows only while it has a live contribution or is
  free text. A deleted recipe's contribution vanishes; the entry row stays
  inert, and its check-off returns if the ingredient is re-planned.
- **Removing.** A user-added line (`isUserAdded`) is swiped or long-pressed
  away through `removeEntry`. A cook-derived line is changed on the Week; its
  top-up is edited or removed by `contributionId` in the edit sheet.
- **Cost.** A row is priced like a recipe line: its total in the ingredient's
  basis (`quantityInBasis`) times the latest price
  ([ADR-0017](../../../../docs/decisions/0017-a-cost-is-a-unit-price-never-an-allocation.md)).
  The trip's estimate rides the sync line and sums only the rows it can price:
  it reads `at least …` when a row has none, and a trip with no priced row has
  no figure. Open rows carry their own estimate,
  and `no price yet` prints only once something on the trip has a price.
- **Two empty states**, told apart by the derived cook plan: nothing planned,
  or meals planned whose recipes have no ingredients.

## Doors to receipts

`ScanReceiptDoor` at the foot opens `/receipts/review`
([receipts](../receipts/README.md)). The ledger's door is a header action
opening `/receipts`, drawn only once the household has kept a receipt.

## Not built

Clear list / new trip ([backlog](../../../../docs/exec-plans/backlog.md)), and
package-size rounding (roadmap step 11, stretch).
