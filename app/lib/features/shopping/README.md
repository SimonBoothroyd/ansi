# Feature: shopping

**Roadmap:** Step 6 — shopping list from the cook plan (see
`docs/exec-plans/roadmap.md`,
[exec plan](../../../../docs/exec-plans/completed/0007-shopping-list.md)).

The **Shop** screen: the provenance-aware shopping list (spec §4). It sums each
ingredient's contributions from the batch cook plan, plus manual top-ups, groups
them by aisle, and holds check-off state. Read-derived — edit the Week/Cook and
the list re-sums.

## The aisles and the basket

The aisles hold only what is still to grab. A ticked row leaves its aisle for
**one section at the bottom** — `IN THE BASKET · 4`, under the aisles and above
the echo rows — which keeps its aisles inside it (`PRODUCE`, then `PANTRY`, a
size down), so a row is re-found the way it was found; an aisle whose rows are
all ticked leaves the top. Tapping a basket row unticks it and
it returns to its aisle on the next derivation. When every row is ticked the
aisles give way to one quiet line, `everything’s in the basket`. All of it is
derived on the domain (`ShoppingList.openGroups` / `basketGroups` / `basket` /
`allTicked`);
`groups` stays the full list for whatever counts items.

## The last tick

Whenever the tick that finishes the list is made **on this phone**, the phone
celebrates: a light haptic, and confetti of the food itself — about thirty
pieces, Lucide glyphs the app already ships (leaf, wheat, carrot), a berry
and plain strips, in the eight `AnsiConfetti` colours, the one deliberate
break from the two-ink palette — burst from the box just ticked, arc across
the whole width of the screen and fall past the bottom, over the list. One
`CustomPainter` driven by one `AnimationController`, in an overlay entry on
the root overlay that ignores pointers and removes itself when the last piece
has fallen (`confetti_burst.dart`), so the list re-flowing underneath never
moves it. The tail is the shipped state arriving: the tick writes exactly as
before, the stream re-derives, the row moves to the basket and the quiet line
appears.

The rules are held in code and tested. `completesTheList` (domain) says
whether this tick takes the list from exactly one unticked row to none — never
on a list of one item — decided on the list as it stands before the write, so
a completion arriving by sync plays nothing. The view asks it on every tick
and nothing is remembered between them: untick the last row, tick it again,
and the confetti comes back. `MediaQuery.disableAnimations` skips the burst
and keeps the haptic.

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
                  confetti_burst.dart (the last tick's burst + overlay door);
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

## What the list left out, and the door on it

A line the `effectiveLines` seam drops contributes nothing, so the recipe it
belongs to says which lines — `2 optional lines not listed — lime, coriander`,
in the group-header voice, muted rather than amber (a rule somebody chose is not
a defect somebody can fix). Both kinds of drop take that row: the recipe's own
`optional` flag, and a line this week leaves out. Component lines are ruled on
by the same seam, so an optional **sub-recipe** the week does not cook is named
there by its title.

On an optional row **each name is a door**: a tap writes this week's `include`
override for that line (`WeekVariantRepository.setLineIncluded`, through
`ref.write`), and the ingredient arrives in its aisle on the next derivation
carrying `· this week, ticked in`. A line the *week* left out is not a door —
that change is undone where it was made.

**A component said in the target's own word is expanded like any other.** `3
blob` of a sauce that makes 20 of them is 0.15 batches, and the walk buys 0.15 of
the sauce's own ingredients — you buy almonds, never aioli. The words ride the
same `loadComponentGraph` the cook plan reads, so the two derivations cannot
disagree about how much of a sauce this week needs, and the watch joins
`recipe_measure` so re-stating a word moves the amounts. A word the target no
longer has buys **nothing** and takes the `unresolvedComponents` echo naming the
parent that is short — never a count of the yield, which would buy a confidently
wrong amount rather than admit a gap (invariant 3).

## Honest aggregation (invariant 3)

`aggregateQuantities` sums within a unit family by the ratio table, bridges
mass↔volume **only** when a density is supplied, and never invents a number —
an ingredient with mixed families and no density yields two honest subtotals,
not a single guessed total. Count units sum per unit; imprecise units never sum.

**A row asked for in one measure is bought in that measure.** When every
quantified contribution to a line names the same measure, the item carries a
`measureTotal` and the row reads its count — "2 cans" — with the canonical mass
beside it as the secondary and, when the count is fractional, the round-up
after that ("2½ lime, whole · 167.5 g → buy 3"): you buy whole limes and whole
cans alike. The moment a plain mass line or a second measure
joins there is no single countable answer, and the family sum prints as it
otherwise does; each provenance line keeps its own words either way. The
ingredient's default unit biases only a sum that real mass or volume lines
stated — a measure-only sum stays in the basis it folded into, so a can of
lentils never comes back out as ounces.

**A piece-weighted row is bought in pieces.** A row that states what one of it
weighs (`piece_basis_amount`, ADR-0015) prices a bare `piece` line through that
weight, exactly as a measure is priced through its own — so `1 lime, whole`
here and `1½ piece` there are one mass subtotal, never `67 g + 1½ piece`. When
that row's default unit is `piece` and everything asked for folded into one
basis-family total, the item carries a `pieceTotal` and the row reads the count
— "2½ piece" — with the mass beside it and, when the count is fractional, the
round-up after that ("167.5 g → buy 3"). The count is exact when every
contribution was a `piece` line or a measure that is a whole number of pieces,
and marked `≈` when a plain mass or volume line joined or a measure did not
divide evenly. A row asked for in one named measure keeps that count instead —
`2 potato, large` is the more specific thing to buy — and a row with no piece
weight is untouched: its `piece` lines stay an honest bare count, which is the
row's own legacy state to fix.

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

## What the trip costs

`shopping_cost.dart` prices a row the way the recipe panel prices a line: the
rolled-up total converted to the ingredient's basis through the same
`quantityInBasis` seam, times the latest price per unit of that basis
([ADR-0017](../../../../docs/decisions/0017-a-cost-is-a-unit-price-never-an-allocation.md)).

The trip's estimate rides the **sync line**, where the one sentence about the
whole list already lives, and stays put while the sync words fade in and out
beside it. Each **open** row carries its own under the grams; the basket's
carry none, because the line answers what is left to buy. A row that cannot be
priced says `no price yet` — but only once something on the trip HAS a price, so
a household that has entered none is never nagged by forty rows at once.

## The door that ends the trip

A second foot door, beside the top-up one and drawn in herb, **scans the
receipt** (`ScanReceiptDoor` → `/receipts/review`,
`features/receipts/README.md`). On the web it says what it can actually do,
because the photo import is gated there: shoot the receipt on the phone,
review it anywhere.

The **ledger's door is in the header**, not at the foot: a receipt action in
the switcher's suffix, opening `/receipts`. The foot is the end of a list you
have to walk to reach, and the one door that is not about *this* trip belongs
in the chrome, where it is in the same place at every scroll position and at
every width — so it is the Shop's door on a phone and at a desk alike, and
nothing at the foot repeats it. The switcher stays **centred** beside it:
`FHeader.nested` centres its title in the header's whole width and moves it
only when title and action would collide, so a balancing spacer opposite would
buy no centring and cost the title room.

It is drawn **only once the household has kept a receipt**: a door onto an
empty page is furniture, and the header is the one strip on screen for the
whole walk. `scan a receipt` is what teaches the feature; the header action is
what gets you back to what it kept.

The trip figure sums the rows it can price and lets the rows name the rest.
That is this list's own doctrine, not a softening of invariant 3: it already
sums an ingredient's honest subtotals and shows the provenance of every part,
and there is no silent zero anywhere — a trip nothing on it can price has **no**
figure rather than `≈ $0`.
