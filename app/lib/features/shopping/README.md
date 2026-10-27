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
    shopping_cost.dart        a row's figure and the trip's, at the Shop's
                              price, a rounded row on what you buy
    at_home.dart              what is already at home: leftToBuy,
                              amountForAll, whyNotAtHome
    shopping_repository.dart  read/write contract
  data/           SqliteShoppingRepository (derive + overlay) + providers
  presentation/
    shopping_view.dart            the screen: the toggle, aisles, the folded
                                  basket, At home and notes
    shop_add_field.dart           the one way to add: search, then a top-up
                                  or a non-food item
    edit_top_up_sheet.dart        edit or remove one manual top-up
    at_home_sheet.dart            how much is at home (sheet, or the wide pane)
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
- **The amount at home** (migration `0058`) — three columns on the week's
  entry, `at_home_quantity · at_home_unit · at_home_measure_id`, stored as
  said. Duplicate entries keep the newest amount, and a fold carries it onto
  the survivor.

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
  reads `2 cans`, with the mass beside it.
- **A row that rounds leads with what you buy**
  ([ADR-0016](../../../../docs/decisions/0016-a-measure-that-weighs-a-piece-is-its-word.md)
  point 4). A fractional measure count, a fractional piece count and a
  whole-unit hint on a mass total all print the whole count bought as the
  headline (`3 lime, whole`, `3 piece`, `3 potato, large`), and the sub-line
  opens with the need: `need 2½ · 167.5 g`, or `need ≈ 2¼ · 600 g` when the
  count was read from a weight — the `≈` stays on the need (`itemTotal`,
  `itemNeed`). The basket prints the same headline. The at-home pass, its
  sheet and the *At home* section print the need unrounded (`itemAmount`,
  `needTotal`), because they weigh what is here against what the week asks.
- **The sub-line's order** is at home, need, weight, price, each only when it
  applies: `5 at home · need 1½ · 165 g · $1.54 at Aldi` (`itemSubLine`).
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
- **A row acts from its box and its chevron, and nowhere else.** On a phone
  a row is one line, or two with its sub-line. Only the check box ticks, on
  a 44 × 44 target centred on it (`shopTickTargetKey`). Only the chevron
  after the amount opens and folds the recipes, the sessions and the manual
  top-up under it, on a 48 × 48 target centred on it and reaching the row's
  right edge (`shopChevronTargetKey`). The name, the amount, the sub-line and
  the gaps do nothing on a tap; long-press and swipe still remove a
  user-added row. The opened breakdown takes no tap either, except its
  top-up, which is its own 44 px row with a pencil that opens
  `edit_top_up_sheet.dart`. The
  chevron says what is: `chevronRight` closed, `chevronDown` open, in herb,
  as the Library's folds draw it; a row with nothing to trace (free text)
  has none. The amount stays plain text: the herb-soft chip belongs to the
  at-home pass. What is open (`shopOpenProvider`) is this phone's, lasts the
  visit and is never synced; a tick folds its row, and leaving the tab folds
  everything. At expanded no row opens: the box ticks, and a tap anywhere
  else on the row points the pane, which holds the breakdown.
- **The basket.** Aisles hold what is still to grab; ticked rows move to one
  `IN THE BASKET · n` section that keeps its aisles (`openGroups`,
  `basketGroups`, `allTicked` on `ShoppingList`). `groups` stays the full
  list.
- **Three folded lines close the walk**: `IN THE BASKET · n`, `AT HOME · n`
  and `N notes from the plan`, each a 44 px line with the same chevron pair,
  opening from anywhere on the line. Opened, a basket row unticks only from
  its box, and an *At home* row goes back to its aisle only from its house
  (a 44 × 44 target, `shopHomeTargetKey`). The notes line holds the three echo rows below; it
  reads amber with a flag while any note is a defect (an unresolved
  component, a retired ingredient), and muted when every one is a line left
  out. The list draws no caption.
- **The last tick.** `completesTheList` decides, on the list as it stands
  before the write, whether this tick finishes a list of more than one item. A
  completion arriving by sync plays nothing. The view plays a haptic and the
  confetti; reduced motion keeps only the haptic.
- **Lifecycle.** An item shows only while it has a live contribution or is
  free text. A deleted recipe's contribution vanishes; the entry row stays
  inert, and its check-off returns if the ingredient is re-planned.
- **Adding starts from one field** (`shop_add_field.dart`), `Add to the
  list`, under the toggle and over the walk; at expanded it tops the walk's
  column. It is not drawn while `At home?` is on. While it holds text and has
  focus its answer stands where the walk was: the picker's own tiers
  (`useIngredientSearch`, `IngredientResultList`), and a result already on
  this week's list says so after its category, `Produce · on the list · 3
  lime, whole`. Every search with text ends with the same two rows, worded in
  parallel: `＋ "paper towels" as a non-food item` writes `addFreeTextItem`
  with no sheet, and `＋ "paper towels" as a new ingredient` runs the
  picker's add-new chain (`AddNewIngredientRow`, in this field's words), so
  the form's row lands on the quantity sheet. A pick opens the shared
  quantity sheet, **Add to list** writes `addTopUp` (a measure stores
  `pieces` beside its id), and the field clears; backing out writes nothing
  and leaves the results as they were. Clearing the field, or leaving it,
  brings the walk back.
- **A top-up opens on its usual amount**: the last top-up of that
  ingredient in any week, else one of its word for one, else one piece
  (`defaultAmountFor`), read by `lastTopUp`. A tub with no history opens
  empty.
- **Removing.** A user-added line (`isUserAdded`) is swiped or long-pressed
  away through `removeEntry`. A cook-derived line is changed on the Week; its
  top-up is edited or removed by `contributionId` in the edit sheet.
- **Cost.** A row is priced like a recipe line: what it buys in the
  ingredient's basis (`quantityInBasis`) times the Shop's price
  ([ADR-0017](../../../../docs/decisions/0017-a-cost-is-a-unit-price-never-an-allocation.md)).
  The Shop's price is its own rule, `shopPriceOf`: the cheapest per-100
  figure paid on a receipt in the 90 days up to today (a sale counts; a tie
  goes to the newest), else the price every other cost reads (newest
  receipt, else base price). It comes from `shopPriceMapProvider`, re-keyed
  by `todayProvider`, and reaches no other cost; the recipe page, the Week
  and Ask's other figures read the latest. A row that rounds up (`→ buy 3`)
  is priced on the whole count bought (`roundedBuy`), a part-have on what is
  left. Open rows print the figure plain to the cent with where it was seen
  (`$1.80 at Aldi`; `$2.42 at TJ's, Jun` for an older receipt; `$2.42 at
  Aldi, Sep` or `$2.42 · base price, Sep` for a base price), and `no price
  yet` prints only once something on the trip has a price. The trip sums the
  same figures on the sync line, `≈ $51 at the cheapest`, or `at least $51 at
  the cheapest · 1 row unpriced` when a row has none, and a trip with no
  priced row has no figure. Ask's trip answer is this figure
  (`readShopTripCost`).
- **Two empty states**, told apart by the derived cook plan: nothing planned,
  or meals planned whose recipes have no ingredients.
- **Already at home.** The `To buy · At home?` toggle under the sync line
  (`ShopToggle`, Forui's tabs) enters a pass and, tapped back to `To buy`,
  leaves it; it reads and writes `shopCheckingProvider`, this phone's alone.
  Leaving the tab sets it back to `To buy`, and so does the wide pane's ×.
  It is drawn while the list holds an ingredient row, and at expanded it sits
  over the walk's column. A row tap stores `amountForAll` — the need as it stands, never a
  flag — or clears what was said; the amount chip opens `at_home_sheet.dart`,
  the wide pane at expanded. `leftToBuy` takes the amount off the need
  through the same bridges the sum uses, or returns `NotCounted` with the
  reason the sub-line prints. Imprecise words ride along; a row with two
  measurable totals cannot take an amount (`whyNotAtHome`). `openGroups` drop
  rows all at home, which sit in `atHome` under the basket; the trip's cost
  follows, `completesTheList` ignores them, and `allAtHome` closes the list on
  *everything's at home*. Ask's `shopping` tool names both.

## Doors to receipts

One door: the header's receipts icon opens `/receipts`, always drawn, with or
without a receipt kept. Scanning lives there, on the ledger's **Scan a
receipt** ([receipts](../receipts/README.md)); the walk's foot holds no door.

## Not built

Clear list / new trip ([backlog](../../../../docs/exec-plans/backlog.md)), and
package-size rounding (roadmap step 11, stretch).
