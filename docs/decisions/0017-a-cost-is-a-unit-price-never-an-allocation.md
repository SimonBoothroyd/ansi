# ADR-0017 — A cost is a unit price, never an allocation

- **Status:** accepted (2026-09-16, Simon — owner-ruled on the 0049 design);
  rule 4 amended 2026-09-19 with the floor a partly priced recipe prints, and
  rule 8 added the same day for the aggregates that leave a meal or a row out
- **Rests on:** [ADR-0007](./0007-shopping-list-thin-overlay.md) (the app keeps
  no inventory), [ADR-0008](./0008-unit-admission-model.md) and
  [ADR-0009](./0009-density-unlocks-both-families.md) (which amounts may reach
  which basis), [ADR-0015](./0015-piece-weight-is-a-row-fact.md) (a bare count
  reaches the basis through the row's piece weight),
  [ADR-0016](./0016-a-measure-that-weighs-a-piece-is-its-word.md) (the word a
  counted pack is bought in)

## Context

The household wanted to know what a recipe, a week and a shop cost. The first
framing was the obvious one: a receipt is a list of what was paid, a week is a
list of what was cooked, so **allocate** the receipt's lines to the week's
meals and each meal carries its share.

That framing needs an inventory, and needs it for every case that actually
happens. A Sunday shop feeds Wednesday's dinner and half of next week's. A
2 kg bag of rice is bought once a quarter and eaten sixty times. A jar of
harissa is opened in March and finished in June. Leftovers move a portion from
one day to another. To allocate a receipt line to a meal, the app would have to
know what is in the cupboard, what came out of it, and what went back —
quantities on hand, consumed and remaining, kept in step across two phones that
are frequently offline.

[ADR-0007](./0007-shopping-list-thin-overlay.md) deliberately keeps no
inventory: it persists only what cannot be re-derived, precisely so two devices
never have stored quantities to reconcile. Allocation would reverse that, and
it would reverse it to produce a number that is *less* useful than the simple
one: the household's question is "what does this recipe cost to cook", not
"which of April's receipts paid for Tuesday".

There is a second cost, and it is worth naming so it is clearly not this one:
what a shop actually *came to*. That is a fact about a piece of paper, and it
already has a home — the receipt itself.

## Decision

**A cost is a unit price applied to an amount. Nothing is ever allocated from
a receipt to a meal.**

1. **The price is the latest one paid, per unit of the row's basis.** A price
   is a `receipt_line` with a stated pack; the figure `77¢ / 100 g` is derived
   from it at read time and never stored — `paid ÷ (count × pack_basis_amount)`,
   because a line may ring up several of the pack and the pack is what ONE of
   them comes in (migration 0050). Latest wins — no average, no sale flag, no
   forecast (a shop's own decision log entry for 0049).

2. **A recipe costs its lines.** Each line's amount is converted to the
   ingredient's basis unit through **the same conversion the macros use**
   (`line_basis.dart`), then multiplied by that row's latest price per basis
   unit. A component line contributes its target's whole-recipe cost × the
   batches it asks for. Per serving is the recipe total over its servings, and
   is therefore scale-invariant, exactly as the per-serving macros are.

3. **Planned and spent are two figures, shown together and never reconciled.**
   *To cook* is the planned week at the latest prices. *Spent* is the sum of
   the receipts dated inside that week. Both appear on the week's band; the gap
   between them is the pantry filling or emptying, and no line attempts to
   explain it. There is no reconciliation table, no variance figure, and no
   rule that makes one of them "correct".

4. **An unpriced line is named, and takes the figure with it.** A line with no
   price, or with no honest path from its amount to the row's basis (a volume
   line on a gram row with no density; a bare count on a row with no piece
   weight), is **unpriced**. The recipe then has no cost at all — the cells go,
   and the lines it is waiting on are named (invariant 3: a total that quietly
   skipped the tomatoes would understate the recipe by the tomatoes).

   **What the priced lines come to is still said, as a floor.** Where some of
   a recipe's lines are priced and some are not, the recipe page prints the
   priced sum under the refusal — `at least $1.65 a serving · at least $6.60
   the recipe` — with **each figure wearing its own `at least`**, because a
   bare `$1.65 a serving` beside a floor would be read as what a serving costs,
   and what a serving costs is exactly what is not known. The cells stay gone,
   the unpriced lines stay named, and the sentence under the figure says what
   it is: a floor, not the cost, which the lines named below can only add to.

   A floor is a **separate field** (`pricedCents`, and its per-serving twin),
   never a partial total: the cost stays null, so the week's figure, the shop's
   estimate and a parent recipe's component share are unchanged by it, and a
   component whose target is incomplete is still **unpriced** in its parent
   rather than contributing a floor. With nothing priced there is no floor
   worth printing — `at least $0` reads as free rather than as unknown — so
   that recipe keeps the plain refusal. A floor wears no `≈`: what is uncertain
   about it is not the arithmetic, it is the lines nobody has priced.

5. **Imprecise and optional lines are out by exactly the macro rule**, through
   the same `effectiveLines` seam, and are named in their own row. A `handful`
   is not unpriced — it is unweighable by nature, and calling it a gap would
   send somebody to fix what cannot be fixed.

6. **Money and macros never meet.** The cost record carries no nutrition and
   the macro record carries no money; they share the walk and the conversion,
   nothing else. Held by
   `test/structure/cost_and_macros_stay_apart_test.dart`.

7. **`≈` marks a summed estimate**, and such an estimate reads to the dollar
   (`≈ $71 to cook`, `≈ $58 still to buy`). A figure read off ONE price prints
   plain and to the cent, with the chain behind it (`$6.58 · $1.10 / 100 g ·
   TJ's, Sep`), because a reader can follow it to the receipt line that made
   it. The recipe panel's cells wear neither: their third cell says
   `prices from Sep` outright, which is the same caveat in words.

8. **A sum that left something out says `at least`, and drops the `≈`.** The
   week's figure is the meals that resolved, and a meal with one unpriced line
   is out of it *whole*; the shop's is the rows it could price, and a row it
   could not adds nothing. Both therefore understate, by meals and by rows
   rather than by rounding — so both print the floor's own words the moment
   anything is missing (`at least $71 to cook · 3 lines unpriced`, `at least
   $58 still to buy · 2 rows unpriced`) and keep the plain `≈` reading for a
   week or a walk that is whole. The two glyphs never ride together: `≈`
   hedges the arithmetic, and the arithmetic is the exact part (rule 4's
   wording, applied to the aggregates).

   Naming the gap beside the number was not enough. The count of unpriced
   lines has always been there, and a reader still took the figure for what
   the week costs — which is the owner's ruling: the number has to say what it
   is, not merely sit next to what is missing.

   **What is summed does not change.** Folding recipes' floors into the week
   was weighed and refused: the figure would then mix whole meals with parts
   of meals, and no reader could say which they were looking at. A floor is
   still a separate field on a recipe, and the week still counts only meals
   that resolved.

## Consequences

- **Nothing new is stored.** Every cost in the app is derived at read time from
  rows that already exist, so a corrected receipt moves every screen at once
  and there is nothing to migrate, recompute or reconcile.
- **A price improves silently.** Re-weigh a pack or fix a discount and every
  recipe, week and shopping row that reads that row moves with it.
- **The gap is visible and honest.** A household that has priced ten rows sees
  ten rows priced and the rest named; there is no point at which the app
  pretends to know more than it does. A recipe halfway through that work says
  both halves at once — the floor it has reached, and the lines it is waiting
  on — so pricing a row is visibly worth something before the last one is done.
- **A stale price is visible rather than smoothed.** The panel states the month
  its figures come from and names the oldest line when that month differs, so a
  July jar under an otherwise-September recipe is something you can see.
- **Some questions this cannot answer**, and that is the trade: what the
  pantry is worth; which receipt paid for a particular meal; how a price has
  moved over time beyond "here is what was paid before". Each would need the
  inventory ADR-0007 refuses, and each can be reopened as its own ADR.
- **A week's figure is a sum of the meals that resolved**, with the lines that
  kept the rest out named — the week's existing doctrine for macros, applied to
  money — and it reads as a floor for as long as any of them are unpriced, so
  pricing the last one is visibly what turns it into the week's cost.

## Alternatives rejected

- **Allocate receipt lines to meals.** The first framing, and the reason this
  ADR exists. It needs the inventory ADR-0007 refuses, it is wrong whenever a
  shop spans weeks (which is most of them), and it answers a question the
  household did not ask.
- **Average the prices, or weight the recent ones.** A moving average hides the
  one thing a person wants to see — that the olive oil went up — and it makes
  every figure unfollowable: no receipt line is behind it. Latest wins, and the
  panel says which month "latest" is.
- **Price from the web.** Rejected on availability, not on principle: TJ's has
  no API, and Whole Foods' prices live inside Amazon. Scraping a shelf tag would
  also break the property that every figure in the app traces to something the
  household actually paid.
- **A third tab on the recipe page for cost.** It would have to list the
  ingredients again to mean anything, and the page holds one list. The strip is
  already where the lines are summed, so it takes two readings instead.
- **Two menu items, `Show line macros` and `Show line costs`.** Weighed and
  set aside: one item that follows the panel is one thing to learn, and a
  second item is a line of code away if the two readings are ever wanted under
  one name at once.
