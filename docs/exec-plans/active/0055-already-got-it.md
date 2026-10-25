# Exec plan: Already got it

- **Status:** draft. The design is ruled and drawn; no code yet
- **Owner:** Simon (design and rulings), agents in lanes
- **Roadmap step:** Next 7, from the owner's ask
- **Created:** 2026-10-25

## Goal

*"For ingredients, we need to be able to say 'already got x'."* — the owner,
2026-10-25.

Before a trip, either of us can go down the Shop list at home and say what is
already in the cupboard: all of a row, or an amount of it. A whole-have leaves
the aisles. A part-have shortens the row to what is left to buy and says so.
The trip's cost follows on its own. The tick keeps meaning *bought*, and the
Week's cost does not move, because the food is still eaten.

## Rulings

Taken with the owner over three rounds, 2026-10-25, against the frames drawn
as `proposed` on [the Cook & Shop board](../../product-specs/board/cook-shop.html).

- **No new gesture.** On the phone the row is the tick, and stays the tick.
  The app has no swipe or long-press anywhere else, so *already got it* is a
  **mode**: a second dashed door at the list's foot, **⌂ check what's at
  home**, beside *＋ add item or top up an ingredient*.
- **The checking pass.** A band at the top reads *What's already at home?*
  with **Done**. Each open ingredient row shows a house where the box was and
  its amount as a chip. **A tap on the row** says all of it, and a second tap
  clears it. **A tap on the amount** opens the amount sheet. Provenance and
  prices are hidden. Ticked rows and free-text rows are not shown. Every tap
  writes at once, as a tick does, and **Done** only leaves the mode.
- **The amount sheet.** *Flour at home*, the week's need, a stepper and the
  row's own unit chips, *still to buy* worked out live, and **Save**. Opened
  on a row that already has an amount, it adds **Remove**, as the top-up sheet
  does. You say what you have, not what you need.
- **A part-have is said on the sub-line (option B).** The total is what is
  left to buy. The line under it opens with what is at home, muted:
  `200 g at home · ≈ $0.81`, or `5 at home · 220 g · ≈ $0.97` for a counted
  row. The provenance is untouched and still says what the week asked for.
  The list itself has no edit target for the amount; it is changed in the
  checking pass.
- **What is stored is an amount, never "all".** A row tap stores the need
  as it stood (5 onions). If the week then grows (a Shakshuka adds 2), the
  row comes back out of *At home* as a part-have, `2 onion, medium · 5 at
  home`. If the week shrinks, the row stays at home.
- **At home is its own section, last, under the basket.** Its rows are muted
  but never struck through, show a filled house where the tick would be, and
  carry no price. A tap puts the row back in its aisle, as a tap on a basket
  row unticks it.
- **The cost line is silent.** *Still to buy* drops by what is at home and
  does not say by how much. The Week's cost line, Ask's cost answers and
  receipts do not change.
- **Per week, shared.** The amount belongs to that week's list, like a tick or
  a top-up, so the other phone sees it at once and next week starts clean.

### Rejected

- **Swipe a row for *Got some* / *Got it*, with a long-press menu as the
  fallback.** These gestures are used nowhere else in the app.
- **An *always have it* switch on the ingredient for staples**, named in a
  muted foot line. Not wanted.
- **A signed `✎ at home −200 g` line in the provenance (option A).** It
  would have been the list's own place to edit the amount, but the reason the
  number shrank would be the last thing read. The checking pass is the one
  place to edit.
- **The total saying it, `300 of 500 g` (option C)**, and **the need struck
  through, ~~500~~ `300 g` (option D).** C makes the widest total on the row,
  and D reuses the strike that means *bought*.
- **Storing "all".** It would quietly hide a real shortfall when the week
  grows.
- **The cost line naming what was taken off (`· $3 at home`).** That prices
  something that was not bought, which is the receipts' job, not the list's.

## Approach

Phases land in order, and each one can ship alone.

### Phase 0: the board

1. Done: four phone frames and one wide frame, drawn as `proposed` in
   `cook-shop.html`. **Wide:** the pass sits in the 640 measure. The house
   takes the check box's 44 px target, a tap on the rest of the row points
   the pane, and the pane holds the amount sheet in place of the provenance.
   There is no sheet at this width.

### Phase 1: storage

2. **Migration `0058_shopping_at_home.sql`.** Add three nullable columns to
   `shopping_list_entry`: `at_home_quantity numeric`, `at_home_unit text`,
   and `at_home_measure_id uuid references ingredient_measure(id)`, plus an
   index on the measure id. Add a check that an amount is positive and only
   sits on an ingredient entry (`ingredient_id is not null`). RLS, grants and
   the publication are unchanged: the boundary is still `household_id`.
   - **Columns on the entry, not a contribution row.** An entry has one
     amount at home, not a list of them, so the write is an update in place.
     `shopping_list_contribution` stays *manual top-ups only* (ADR-0007).
     The week-start flip (`setWeekStart`) re-keys entries, so the amount
     moves with its week for free.
3. **Sync.** Add the columns to the local schema (`core/sync/schema.dart`).
   Both stream files select `*`, so they gain the columns without a rule
   change. Confirm that on the cloud instance at deploy.
4. **pgTAP** (`supabase/tests/shopping_at_home.sql`): the check refuses an
   amount on a free-text entry and a non-positive amount; the existing
   household-isolation test still covers the table.

### Phase 2: the domain (pure Dart, `shopping/domain`)

5. **Input.** `ShoppingEntryInput` gains the stored amount (quantity, unit,
   resolved measure). Duplicate entries for the same ingredient and week
   already merge onto the oldest row. For the amount, the most recently
   updated non-null one wins, and the write in step 9 clears the others.
6. **`leftToBuy`.** Given an item's need (its `totals`, `measureTotal` and
   `pieceTotal` as `buildShoppingList` makes them today) and the amount at
   home, return one of three results:
   - **Left:** new totals, a measure or piece total recomputed, and the
     round-up hint recomputed on what is left.
   - **All at home:** the amount covers the need.
   - **Not counted, with the reason:** the amount cannot honestly come off.
   The subtraction is honest (invariant 3):
   - A count in the row's own measure comes off the measure count.
   - Otherwise the amount must convert into the row's single total through
     units, density or piece weight, the same bridges `aggregateQuantities`
     uses.
   - **Imprecise words ride along.** `pinch`, `dash`, `handful` and
     `to taste` never sum, so a row can carry one beside an amount
     (`1 tsp + to taste` of salt). They are not amounts to buy, so an
     amount comes off the one measurable total and the words follow it: once
     that total is covered, the whole row is at home. A row of words only
     (`to taste`) has no amount chip, and its row tap stores `1 to_taste`
     as *have it*.
   - **Two measurable totals** (mass and volume with no density between
     them, or `piece` with no piece weight) cannot take an amount, and
     neither can an amount with no bridge. Admission rules out both for
     fresh lines (ADR-0009, ADR-0015). They arise only when a density or
     piece weight was deleted after lines used it, or from foreign data.
     Such a row prints its full need with
     `200 g at home · not counted (no density)`, the list's existing
     *not counted* grammar. The amount is never guessed and never silently
     dropped.
   - Anything at or under a small epsilon left is all at home.
7. **`ShoppingItem`** gains `atHome` (the amount as said, for the sub-line)
   and `isAtHome`. `totals` and the rest become what is left. `contributions`
   are unchanged, so provenance still reads the need.
   **`ShoppingList`:**
   - `openGroups` drops at-home rows.
   - A new `atHome` list sits beside `basket`.
   - A ticked row is in the basket even if it also has an amount (a sync
     race; the pass never shows ticked rows).
   - `allTicked` stays "no open rows, and something in the basket".
   - `completesTheList` counts only ticks, so a row moving to *At home*
     never plays the confetti.
8. **Cost.** No change to `shopping_cost.dart`. `tripCostCents` already
   prices `openGroups` by their totals, so a part-have is priced on what is
   left and a whole-have drops out. A test pins both, and another pins that
   the Week's cost (`recipe_cost`) is unchanged by an amount at home.

Tests mirror each rule in `shopping_test.dart` and `shopping_cost_test.dart`:
grams, a measure count, piece weight, a density bridge (`cup` of flour), the
refusals, the growth and shrink cases, and duplicate entries.

### Phase 3: writes

9. **`ShoppingRepository`:**
   - `setAtHome({ingredientId, quantity, unit, measureId?, weekStart})`
     finds or creates the week's entry, as `addTopUp` does, and clears the
     amount on any duplicate entries.
   - `clearAtHome({ingredientId, weekStart})`.
   The row tap's *all of it* is `setAtHome` with the need as the item shows
   it:
   - a measure total: its count, in `pieces`, with the measure id;
   - a piece total: its count in `piece`;
   - otherwise: the single total.
   A row with two measurable totals shows a muted house in the pass, and a
   tap says why it can't take an amount (the deleted density or piece
   weight). It is never silently left out.
   Repository tests in `shopping_repository_test.dart`: week scoping,
   find-or-create, clearing, the measure FK, and an entry carrying only an
   amount dropping off when its last derived contribution goes (the existing
   lifecycle rule).

### Phase 4: the Shop screen

10. **The door.** `⌂ check what's at home` in the foot, drawn while any
    ingredient row is open or at home.
11. **The pass.** A screen-local mode (`shopCheckingProvider`). It is this
    phone's alone and never synced. Leaving the Shop tab ends it, and changing
    the week keeps it. While checking:
    - the band with **Done**;
    - the house box: dashed when empty, filled ⌂ for all of it, **½** for some;
    - the amount chip: `all 5` or `200 of 500 g`;
    - no provenance, prices, basket or free text.
    At ≥ 1024 the box target becomes the house, the rest of the row points
    the pane, and the pane holds the amount editor (step 12) in place of
    the provenance. After **Done** it goes back to provenance.
12. **The amount sheet** (`presentation/at_home_sheet.dart`) on the shared
    `showQuantityUnitSheet`, with its body also usable as the wide pane. It shows the need line, the unit chips the
    ingredient admits (`allowed_units`), and *still to buy* from
    `leftToBuy`, live. An amount it cannot take is refused inline, in the
    domain's words. It has Save, plus Remove when an amount exists.
13. **The list after.** The sub-line opens with the amount at home, muted
    (`shopping_format.dart`: `atHomeWords`). The **At home · N** section goes
    after the basket, with its rows tapping back to their aisle. When nothing
    is open, the closing line reads *everything's at home* if nothing is in
    the basket; otherwise it is today's *everything's in the basket*
    (ruled).

Widget tests in `shopping_screen_test.dart` cover the door, entering and
leaving the pass, the row tap and its second tap, the chip into the sheet,
the sub-line, the section, the tap back, the silent cost line, and the wide
row's targets. `at_home_sheet_test.dart` covers Save, Remove and the
refusal.

### Phase 5: Ask

14. **`shoppingResult`** (`ask_week_tools.dart`) adds `at_home` to a row
    that has an amount, and a top-level `at_home` list of whole-have rows
    beside `left_to_buy`. *Do we need flour?* can then answer *300 g; you
    said 200 g is at home*. Ask does not write amounts at home in this plan.
    One eval case for the question, run with the next paid eval; it does not
    block this plan.

### Docs, with the code

- Product spec §4 *Shopping list*: the third stored fact, the subtraction
  rules, and the At home section.
- [ADR-0007](../../decisions/0007-shopping-list-thin-overlay.md): one
  consequence line. The overlay now stores an amount at home, which cannot
  be re-derived, so the decision stands and needs no new ADR.
- `features/shopping/README.md`: *What is stored* and *Rules*.
- The board: the frames go from `proposed` to built, and the index status
  line follows. (The backlog row was retired when this plan was written.)

## Acceptance criteria

- [ ] A row tapped in the pass leaves the aisles for *At home* on both phones,
      and the trip's figure drops by its price.
- [ ] An amount shortens the row, the sub-line says it, and the provenance is
      unchanged.
- [ ] Growing the week brings a whole-have back as a part-have; shrinking it
      keeps the row at home.
- [ ] An amount that cannot honestly come off is shown as *not counted*,
      never guessed.
- [ ] Ticks, the basket, the confetti, receipts and the Week's cost behave as
      before.
- [ ] Next week's list starts with nothing at home.
- [ ] Tests cover the domain, repository, screen and sheet;
      `make analyze`, `make test` and `make docs-check` pass, as does
      `make ci-full` for the migration.
- [ ] Docs above updated in the same commits.

## Decision log

- 2026-10-25: Rulings and rejections above, from three rounds with the owner
  on the board frames.
- 2026-10-25: Storage is three columns on `shopping_list_entry`, not a new
  `source_type` on contributions. There is one amount per entry, top-ups
  keep their table to themselves, and the week-start flip carries it for
  free.
- 2026-10-25: Imprecise words ride along with the measurable total instead of
  blocking an amount. Two measurable totals only come from a deleted density
  or piece weight, so they get a muted house with the reason.
- 2026-10-25: Owner's rulings: the closing line is *everything's at home*
  when the basket is empty; wide gets a frame, and the pane is the amount
  editor.

## Open questions

None open. Resolved 2026-10-25:

- **Rows with two measurable totals** are rare (see step 6). They get a muted
  house that says why, rather than being left out of the pass.
- **The closing line:** *everything's at home* when the basket is empty,
  today's line otherwise.
- **Wide:** a frame, with the pane as the amount editor.

## Step-done checklist

- [ ] Roadmap row updated: status flipped, one line on what shipped and what
      was deliberately deferred.
- [ ] `ARCHITECTURE.md`'s standing table matches reality for Shop.
- [ ] `app/AGENTS.md` "Current focus" and command list still true.
- [ ] `make test-sim` run once on a booted simulator, and the result recorded
      here.
- [ ] Tech-debt rows added for corners knowingly cut, and retired or
      narrowed for debt this plan paid off.
- [ ] Migration `0058`: say in the roadmap row whether it has reached
      **cloud**, and append a `docs/cloud-setup.md` ledger entry when it
      does.
- [ ] `make ci` green.
