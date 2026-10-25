# Exec plan: Shop refresh

- **Status:** design — frames drawn as `proposed` on the board; nothing built
- **Owner:** Simon (design and rulings), agents in lanes
- **Roadmap step:** Next 8, from the owner's ask
- **Created:** 2026-10-25

## Goal

*"The shop page is starting to get a bit clunking on modal... can you do a
critical review of the UI / UX, and think on if we need a slight refresh."*
Then: *"the add receipt being at the bottom is also a bit strange, should
maybe be on the receipt page?"* — the owner, 2026-10-25.

The review of the phone Shop found:

- Every open row always prints its whole provenance, four to eight wrapped
  lines an item, so about three items fit a screen.
- The figure you act on (`→ buy 3`) is buried in the sub-line, while the
  headline is the fractional need. The sub-line stacks at-home, weight,
  round-up and price.
- The foot holds three dashed doors (*add item or top up*, *check what's at
  home*, *scan a receipt*) under every aisle, the basket, *At home* and the
  echo rows.
- Adding is a two-mode sheet (*Non-food item* / *Top up an ingredient*) and
  then a second, stacked quantity sheet.
- Small targets (a top-up's edit line, the optional-line doors) sit inside a
  row whose tap ticks.
- The caption `summed from the cook plan · with provenance` is dev-speak.

The at-home pass already uses a compact one-line row (box · name · amount
chip). The refresh brings the walk to that density. What you buy leads, where
it came from is one tap away, adding starts from one field at the top, and
the foot holds no doors.

## Rulings

Taken with the owner interactively, 2026-10-25, against the frames drawn as
`proposed` on [the Cook & Shop board](../../product-specs/board/cook-shop.html)
and [the Receipts board](../../product-specs/board/receipts.html).

- **R1 Lead with what you buy.** On a rounded row, the big figure is the whole
  amount bought (`3 lime, whole`). Under it, small: `need 2½ · 167.5 g`. Rows
  with no rounding are unchanged. This amends the print shape in
  [ADR-0016](../../decisions/0016-a-measure-that-weighs-a-piece-is-its-word.md)
  point 4. The measure's word stays.
- **R2 The breakdown is collapsed by default on the phone.** A tap on the row
  ticks, as today. A tap on the amount opens the breakdown in place: recipes,
  sessions, and the manual top-up, editable on a full-size target. This is
  the split the wide screen and the at-home pass already make. A part-have's
  `5 at home` stays on the row's sub-line.
- **R3 The price stays on the row, as the cheapest seen.** The row shows the
  cheapest unit price seen on any receipt in the **last 90 days**, with its
  store: `550 g · $1.80 at Aldi`. The owner's reason: *"it can be very handy
  to know the expected cheapest price, as that may motivate buying in another
  store."* The trip total on the sync line sums the same cheapest figures, so
  the rows and the total agree: `≈ $51 at the cheapest`. **This applies to the
  Shop only.** Recipe costs, the Week's cost and Ask keep the latest price
  (ADR-0017), so
  [ADR-0017](../../decisions/0017-a-cost-is-a-unit-price-never-an-allocation.md)
  is amended for the Shop. The fallbacks are in Phase D, and what is not
  settled is under *Open questions*.
- **R4 One search field at the top for adding.** It replaces the two-mode
  sheet and the foot's add door. Typing finds ingredients. Text that matches
  none offers `add "paper towels"` as a non-food item. Picking an ingredient
  **still opens the quantity sheet**, filled with its usual amount
  (`defaultAmountFor`, as today), before anything is added.
- **R5 The at-home check is a toggle at the top.** `To buy · At home?` sits
  under the sync line and replaces the foot's *check what's at home* door.
  The pass itself is unchanged: house boxes, amount chips, the amount sheet.
  - **The toggle replaces the pass's band.** The band (*What's already at
    home?* · **Done**) goes. The `At home?` segment asks the band's question,
    and tapping back to `To buy` is **Done**. Two controls for one mode would
    be the accretion this plan removes.
  - **0055's "no new gesture" ruling holds.** A segment is a tap like any
    other. The row is still the tick, and there is no swipe or long-press.
  - **Leaving the Shop tab still ends the pass**, and the toggle goes back to
    `To buy`.
- **R6 Scanning moves to the receipts page.** The receipts icon is always in
  the Shop header. It no longer waits for a first receipt (`hasAnyReceipt`).
  The ledger gets **Scan a receipt** as its main action, in its empty state
  too. Today the empty state says *scan one from the Shop*. The Shop's foot
  scan door goes.
- **Also in the refresh** (part of the proposal, no ruling needed):
  - The caption goes.
  - The basket and *At home* sections each fold to one counted line,
    `IN THE BASKET · 12 ›` and `AT HOME · 3 ›`.
  - The echo rows (unresolved components, retired ingredients, optional
    lines) fold to one line, `3 notes from the plan ›`, that opens them.
  - With R4 to R6, **the foot holds no doors.**

### Rejected

- **R1:** keep the need as the headline.
- **R2:** keep the breakdown always open; a separate chevron to open it.
- **R3:** the latest price plus a *cheaper at another store* clause; the
  latest price only; the total at the latest price under cheapest rows;
  30-day or all-time windows.
- **R4:** a one-tap add at the usual amount; keeping the sheet.
- **R5:** a house icon in the header (three header icons); keeping the door
  at the foot.
- **R6:** a scan door in both places.

## Approach

Four build lanes after the board. A and C touch only presentation, B only the
add path, and D is domain-first. Each can ship alone, but **A lands before B
and C**, because all three edit the top and foot of `shopping_view.dart`. D
can run beside A: it changes only the words the sub-line and sync line print.

### Phase 0: the board

1. Done: four phone frames in `cook-shop.html` (the refreshed list, adding,
   picking an ingredient, and the at-home pass from the toggle) and two in
   `receipts.html` (the ledger's action, filled and empty), all `proposed`. The current frames
   stay until this ships. Then the frames these replace are deleted: the foot
   doors, the caption and the always-open provenance.

### Phase A: the walk

R1, R2, the folds, the caption, and the R5 toggle.

- **Files:**
  - `shopping/presentation/shopping_view.dart`: `_ItemRow`, `_Basket`,
    `_AtHomeSection`, the echo rows, `_ListCaption`, `CheckAtHomeDoor`,
    `_CheckingBand`, and `_WideShop`.
  - `shopping/presentation/shopping_format.dart`.
  - `shopping/presentation/shopping_view_models.dart`: the toggle reads and
    writes `shopCheckingProvider`, with no new state.
- **R1, the headline.** `itemTotal` prints the whole count bought when the
  row rounds, and the need moves to the sub-line's front: `need 2½ · 167.5 g`.
  A rounded row is any row whose sub-line prints `→ buy N` today:
  - a fractional measure count (`2½ lime, whole`);
  - a fractional piece count (`≈ 2½ piece` reads `3 piece` over
    `need ≈ 2½ · 300 g`);
  - a whole-unit hint on a mass total (`600 g` with `≈ 2.25 potato, large`
    reads `3 potato, large` over `need ≈ 2¼ · 600 g`).

  The `≈` stays on the need, because the need is the approximate part. What
  you buy is a whole number. The basket row prints the same headline. The
  at-home pass keeps the need on its amount chip (`2½ lime, whole`), because
  the pass asks what you have against what the week needs.
- **The sub-line's order:** at home, then need, then weight, then price, each
  only when it applies. For example, `5 at home · need 1½ · 165 g · $0.54 at
  Aldi`.
- **R2.** On a phone `_Provenance` is not drawn until the amount is tapped.
  - The amount is the total and its sub-line together, at least 44 px tall.
  - The row's tap keeps ticking. The opened amount wears the herb-soft chip
    the pass uses.
  - A manual top-up in the opened breakdown is its own 44 px row with its ✎,
    opening `edit_top_up_sheet.dart` as today.
  - Opening is this phone's and lasts the visit; it is not synced. A ticked
    row folds its breakdown as today.
  - At expanded nothing changes: the row already has no inline breakdown.
- **The folds.** `_Basket` and `_AtHomeSection` start folded to their counted
  label. A tap opens the section in place, and the rows behave as today. The
  echo rows fold behind one `N notes from the plan ›`:
  - it reads amber with ⚑ when any note is a defect (unresolved or retired);
  - it reads muted when every note is an optional line;
  - opened, it shows today's rows with the optional names still doors.
  
  `everything's in the basket` and `everything's at home` stay as they are.
- **The caption** (`_ListCaption`) is deleted.
- **R5, the toggle.** A two-segment control under the sync line: `To buy` and
  `At home?`.
  - It replaces `CheckAtHomeDoor` and `_CheckingBand`.
  - It is drawn while the week's list holds an ingredient row. If every row
    is ticked, the pass says its existing `nothing left to check`.
  - While `At home?` is on, the search field (Phase B) is hidden. The pass
    walks only *do we have it*.
  - At expanded the toggle sits above the 640 walk. The pane's × sets it back
    to `To buy`, as it ends the pass today.
- **Tests:**
  - `shopping_format_test.dart` holds the R1 strings for the three rounded
    kinds and an unrounded row (unchanged), and the sub-line's order with a
    part-have.
  - `shopping_screen_test.dart` holds that:
    - a phone row shows no provenance until its amount is tapped;
    - the row's tap ticks and does not open the breakdown;
    - the opened top-up's target is at least 44 px and opens the edit sheet;
    - the basket, *At home* and notes lines show their counts and open in
      place, with amber or muted notes as above;
    - the caption is gone and the foot holds no door;
    - the toggle enters and leaves the pass;
    - leaving the tab resets it;
    - the wide pane's × resets it;
    - at expanded the row still selects the pane.

### Phase B: search first (R4)

- **Files:**
  - a new `shopping/presentation/shop_add_field.dart`;
  - `shopping_view.dart` (the field under the toggle; `_AddItemButton`
    removed);
  - `add_shopping_item_sheet.dart`, removed, with its test reworked into
    `shop_add_field_test.dart`.

  It reuses `useIngredientSearch`, `IngredientResultList` and
  `AddNewIngredientRow` from `ingredients/presentation/ingredient_picker.dart`.
- **Typing.** The results replace the walk below the field until the field is
  cleared or loses focus. They are the picker's own tiers: spelled-right
  rows, else the *did you mean* band. A result already on this week's list
  says so in its category line (`Produce · on the list · 3 lime, whole`),
  because a pick tops it up.
- **Text that matches none.** When nothing is spelled right, the first row is
  `＋ add "paper towels"`, a non-food item, written through
  `addFreeTextItem` with no second sheet. The new-ingredient door
  (`AddNewIngredientRow`) stays the last row, as in every picker.
- **Picking an ingredient** opens `showQuantityUnitSheet` filled by
  `usualAmountOf`, exactly as `_TopUpBody` does now. The `hostContextOf` and
  container-before-await rules carry over unchanged. The confirm label reads
  **Add to list**. Add writes `addTopUp`, the field clears, and the row
  arrives in its aisle.
- **Tests** (`shop_add_field_test.dart`):
  - typing finds ingredients, and *on the list* shows for a listed one;
  - a pick opens the sheet filled with the usual amount, and Add writes a
    top-up (unit, and a measure with `pieces`);
  - backing out writes nothing;
  - no-match text shows `add "…"`, and a tap writes a free-text item;
  - the new-ingredient chain still lands on the sheet;
  - the field clears after an add.
  
  `integration_test/week_test.dart` uses today's door copy and is updated in
  the same lane.

### Phase C: receipts (R6)

- **Files:**
  - `shopping/presentation/shopping_view.dart`: `_ReceiptsDoor` drops its
    gate, and `ScanReceiptDoor` leaves the Shop.
  - `receipts/presentation/receipt_ledger_view.dart`.
  - `receipts/data/receipt_providers.dart`: `hasAnyReceipt` is deleted if no
    other reader is left.
  - `test/features/receipts/scan_receipt_door_test.dart`, which moves with
    the door.
- **The ledger.** A full-width **Scan a receipt** (camera icon) under the
  header, above the month band, opening `/receipts/review`. The browser's
  *no camera, shoot it on the phone* line moves with it. The empty state
  draws the same action over `no receipts yet — a scanned shop files here by
  week; a price typed on an ingredient stays on the ingredient`. Saving a
  scan started here pops back to the ledger.
- **Tests:**
  - the Shop's header shows the receipts icon with no receipt kept;
  - the Shop has no scan door;
  - the ledger shows the action when empty and when filled, and a tap pushes
    `/receipts/review`;
  - the web words show under it.

### Phase D: the cheapest price (R3)

The domain is pure Dart and is built first.

1. **The rule, in `ingredients/domain/cost_price.dart`.** Add a second
   resolver beside `costPriceOf`: `shopPriceOf({required
   List<PriceObservation> paid, BasePrice? base, required DateTime today})`.
   It returns the price and how it was chosen, in this order:
   - **Cheapest seen.** Among the row's receipt prices dated within the
     90 days up to and including `today` (the app's day), keep those in the
     row's current basis whose `per100` reads. Pick the lowest per-100 figure.
     A tie goes to the newest. The comparison is per 100 of the basis, never
     the pack's cents, so a 1 kg bag and a 500 g bag compare honestly. What
     was paid is `paidCents`, after the printed discount, as every price
     reads.
   - **No receipt in the window:** exactly what `costPriceOf` returns, which
     is the row's newest receipt price, else its base price. This keeps
     ADR-0017 rule 1's order, that a price paid outranks a base price, and
     matches the README's *newest receipt → base price → un-priced* chain.
   - **Neither:** unpriced, as today.
2. **The words.** A row's figure is read off one price, so it prints plain and
   to the cent with its source (ADR-0017 rule 7), and drops today's `≈`:
   - in the window: `550 g · $1.80 at Aldi`;
   - an older receipt carries its month, because it is not the window's:
     `$2.42 at TJ's, Jun`;
   - a base price naming a store: `$2.42 at Aldi, Sep`;
   - a base price naming none: `$2.42 · base price, Sep`;
   - unpriced: `no price yet`, under today's rule (only once something on
     the trip has a price).

   The trip on the sync line sums the same figures the rows show. It prints
   `≈ $51 at the cheapest` when whole, and `at least $51 at the cheapest · 1
   row unpriced` as a floor (ADR-0017 rule 8).
3. **Data.**
   - `PriceRepository` gains `watchShopPrices({required DateTime since})`,
     implemented in `price_repository_impl.dart`. It stays the one file that
     reads receipt lines for a price.
   - A keep-alive `shopPriceMapProvider` is keyed by today.
   - `shopTripCostProvider` and the row's `itemSecondaryWithCost` read it.
   - `shoppingItemCostCents` and `tripCostCents` are unchanged: they take an
     `IngredientPricing`, now fed from the Shop's map.
   - The recipe page, the Week's band, Ask's figures and the ingredient page
     stay on `costPriceMap`.
4. **The structural test.** `test/structure/cost_reads_one_price_test.dart`
   becomes *two rules, each chosen in one place*. It allows `shopPriceOf(`
   in the price repository and `cost_price.dart` alone, and it fails if the
   Shop's map reaches any cost but the Shop's.
5. **Tests:**
   - `cost_price_test.dart` holds:
     - day 90 is in the window and day 91 is out;
     - per-100 beats pack cents, a count line divides, and a discount
       counts;
     - a different basis is skipped;
     - a tie goes to the newest;
     - each fallback step, and the store or month each prints with.
   - `shopping_cost_test.dart` holds that the trip equals the sum of the
     rows' figures, and that a part-have is priced on what is left (0055,
     unchanged).
   - `shopping_format_test.dart` holds the four row words.
   - A test pins that `recipe_cost` and the Week's figure still read the
     latest price.

### Wide

The wide row already draws no inline breakdown, so **R2 is phone-only**.
R1's headline, R3's sub-line, R4's field (at the top of the 640 walk), R5's
toggle (the pane becomes the amount editor while `At home?` is on, as it does
in the pass now), R6's header icon, the folds and the notes line all apply
unchanged. The change is the phone's change in the same measure, so no wide
frame is drawn. The board's status line carries one clause instead.

### Docs, with the code

- **ADR amendments owed at build time.** The ADRs are not edited now.
  - [ADR-0016](../../decisions/0016-a-measure-that-weighs-a-piece-is-its-word.md)
    point 4: the shop prints `3 lime, whole` over `need 2½ · 167.5 g`. The
    measure's word is unchanged. (Phase A.)
  - [ADR-0017](../../decisions/0017-a-cost-is-a-unit-price-never-an-allocation.md)
    rule 1: the Shop reads the cheapest price in 90 days, with the fallbacks
    above. Every other cost reads the latest. Rule 7 gains the row's `at
    <store>` reading. Rule 8's floor wording takes `at the cheapest`.
    (Phase D.)
- Product spec §4 *Shopping list*: the row's print shape, the folded
  breakdown, adding from the field, and the Shop's price rule.
- `features/shopping/README.md`: *Rules* (the R1 shape, the folds, the
  toggle, adding, cost) and *Doors to receipts*.
- `features/receipts/README.md`: the ledger's action.
- The board: the `proposed` frames become the frames, the frames they replace
  are deleted, and the index status lines follow.

## Acceptance criteria

- [ ] A rounded row leads with what is bought and says the need under it; an
      unrounded row reads as today.
- [ ] On a phone a row is one or two lines until its amount is tapped; the row
      tap still ticks.
- [ ] Basket, *At home* and the plan's notes are one line each until opened.
- [ ] The foot holds no door; the caption is gone.
- [ ] One field at the top adds an ingredient (through the quantity sheet, at
      its usual amount) or a non-food item.
- [ ] `To buy · At home?` enters and leaves the at-home pass; the pass is
      otherwise unchanged.
- [ ] The receipts icon is always in the Shop's header; the ledger scans.
- [ ] Each priced row shows the cheapest price in 90 days with its store, or
      its fallback with its month; the sync line sums the same figures; the
      recipe page, the Week and Ask are unchanged.
- [ ] Tests above; `flutter analyze`, `custom_lint` and `flutter test` pass;
      `make docs-check` passes.
- [ ] ADR-0016 and ADR-0017 amended, docs above updated in the same commits.

## Decision log

- 2026-10-25: Rulings R1–R6 and the rejections above, taken with the owner
  interactively after a critical review of the phone Shop.
- 2026-10-25, design: the toggle replaces the pass's band, and `To buy` is
  **Done**. A rounded row is any row that prints `→ buy N` today, with the `≈`
  kept on the need. A row figure read off one named price drops its `≈`
  (ADR-0017 rule 7). With no receipt in 90 days, the Shop falls back to the
  price every other cost reads, which keeps ADR-0017 rule 1's order.

## Open questions

For the owner, before Phase D (questions 1–4) and Phase B (question 5):

1. **The fallback past 90 days.** As drawn, a row with no receipt in the
   window reads the price the rest of the app reads (the newest receipt, else
   the base price), printed with its month. The alternative is to print *no
   price yet* on the Shop past 90 days, so every figure on it is
   window-honest, and the trip becomes a floor sooner.
2. **The trip's words when rows fell back.** `≈ $51 at the cheapest` is loose
   when some rows read an older or base price. Keep the words, since each row
   says which it read, or count them: `· 2 rows older`?
3. **A sale price.** A discounted line is what was paid, so as drawn it can be
   the cheapest seen for 90 days. Is that the price you want to chase, or
   should a printed discount be left out of *cheapest*?
4. **Ask's trip figure.** Ask's `cost` with `trip` is described as *the Shop's
   estimate*. Under R3 as worded, Ask keeps the latest price, so its trip
   answer would differ from the sync line. Keep it at the latest, or let that
   one answer read the Shop's figure?
5. **The `add "…"` row.** As drawn, it is offered only when nothing is spelled
   right, which is the ruling's *matches none*. Should it also stand as the
   last row under real results, so a non-food word that brushes an
   ingredient is never trapped?

## Step-done checklist

- [ ] Roadmap row updated: status flipped, one line on what shipped and what
      was deliberately deferred.
- [ ] `ARCHITECTURE.md`'s standing table matches reality for Shop.
- [ ] `app/AGENTS.md` "Current focus" and command list still true.
- [ ] `make test-sim` run once on a booted simulator, and the result recorded
      here.
- [ ] Tech-debt rows added for corners knowingly cut, and retired or narrowed
      for debt this plan paid off.
- [ ] `make ci` green.
