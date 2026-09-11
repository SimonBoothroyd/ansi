# Feature: shopping

**Roadmap:** Step 6 — shopping list from the cook plan (see
`docs/exec-plans/roadmap.md`,
[exec plan](../../../../docs/exec-plans/completed/0007-shopping-list.md)).

The **Shop** screen: the provenance-aware shopping list (spec §4). It sums each
ingredient's contributions from the batch cook plan, plus manual top-ups, groups
them by aisle, and holds check-off state. Read-derived — edit the Week/Cook and
the list re-sums.

## Layout

```
shopping/
  domain/         PURE DART (no package:flutter)
    shopping.dart             CookContributionInput · ShoppingEntryInput ·
                              ManualContributionInput · IngredientMetaInput;
                              ShoppingContribution · ShoppingItem ·
                              ShoppingGroup · ShoppingList; aggregateQuantities
                              + buildShoppingList + cookLabel
    shopping_repository.dart  read/write contract
  data/           SqliteShoppingRepository (derive + overlay) + providers
  presentation/   ShoppingView; add_shopping_item_sheet.dart (item / top-up);
                  edit_top_up_sheet.dart (edit / remove one manual top-up);
                  shopping_format.dart (totals copy, pure Dart);
                  shopping_view_models.dart
```

## Editing / removing a top-up

Each `manual` contribution carries its `shopping_list_contribution` id
(`ShoppingContribution.contributionId`), so a manual line in the provenance
breakdown is tappable (a pencil affordance) → the edit sheet. `editContribution`
updates that one top-up in place; `removeContribution` soft-deletes just it,
leaving the item's cook contributions and check-off intact. Removing the last
live contribution drops the item (the lifecycle rule below).

## Derived list + thin overlay (spec §4)

The list is **derived**, like the cook plan. Only what can't be re-derived is
stored (migration `0006`):

- **`shopping_list_entry`** — one row per ingredient the user has *touched*
  (checked, or topped up), plus free-text non-food items. Holds `checked`.
- **`shopping_list_contribution`** — the stored breakdown. Only `manual`
  contributions live here; the `cook_session` ones are derived live from the
  cook plan (which is itself derived — no `cook_session` table), so there is no
  stable `source_cook_session_id` to persist and nothing to reconcile.

`buildShoppingList` (pure) merges the derived cook contributions with the
overlay: it groups by ingredient, sums via `aggregateQuantities`, and keeps the
provenance breakdown. `SqliteShoppingRepository` runs the same `buildCookPlan`
the Cook screen uses, expands each session's recipe lines by its scale factor,
and hands everything to the builder.

## Honest aggregation (invariant 3)

`aggregateQuantities` sums within a unit family by the ratio table, bridges
mass↔volume **only** when a density is supplied, and never invents a number —
an ingredient with mixed families and no density yields two honest subtotals,
not a single guessed total. Count units sum per unit; imprecise units never sum.

**A row asked for in one measure is bought in that measure.** When every
quantified contribution to a line names the same measure, the item carries a
`measureTotal` and the row reads its count — "2 cans" — with the canonical mass
beside it as the secondary. The moment a plain mass line or a second measure
joins there is no single countable answer, and the family sum prints as it
otherwise does; each provenance line keeps its own words either way. The
ingredient's default unit biases only a sum that real mass or volume lines
stated — a measure-only sum stays in the basis it folded into, so a can of
lentils never comes back out as ounces.

## Entry lifecycle (the recipe-deleted-but-checked case)

An item is displayed only while it has a **live** contribution (a derived cook
one or a persisted manual one) or is a free-text item. If a recipe is deleted,
its cook contribution vanishes; an ingredient entry with no manual top-up drops
off the list (its checked row stays inert). Recipe deletion never touches the
vocab `ingredient` row, so `ingredient_id` never dangles. If the ingredient is
re-planned, its prior check-off returns with it — a "clear list / new trip"
action is still unbuilt (a shared-state gesture now that sync is live).

## Removing a line

A **user-added** line (`ShoppingItem.isUserAdded` — a free-text item, or an
ingredient that exists only as a manual top-up, i.e. no cook contribution) can
be **swiped away** (or long-pressed) → a confirm dialog → `removeEntry`. A
cook-derived line is *not* wholesale-removable: its quantity comes from the week
(edit the plan), and its top-up is dropped through the edit sheet instead.

## Empty states

Two, told apart by watching the derived cook plan: **no plan** ("Nothing to buy
yet — plan the week"), vs. a **live plan whose recipes have no ingredients yet**
("Nothing to sum yet — add ingredients to a recipe"), so the copy is never
misleading when meals are already planned.

## Deferred

- **Unit-list filtering** — the unit pickers offer every unit; they should be
  filtered per ingredient (same family as `default_unit`, cross-family only with
  a density). Aggregation stays honest without it. See the tech-debt tracker.
- Package-size / whole-unit rounding (stretch, anti-waste — step 11).
- "Clear list / new shopping trip" — a shared-state gesture, still unbuilt.
- Syncs since step 7 (the overlay tables are synced, household-scoped).
