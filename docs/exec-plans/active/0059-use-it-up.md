# Exec plan: Use it up

- **Status:** active — phases 1–4 on main, migration `0059` on cloud (deploy 41308689885), the simulator run green; the owner's look on a phone, then a tag
- **Owner:** Simon (design and rulings), agents in lanes
- **Roadmap step:** 11 (anti-waste); continues [plan 0054](./0054-eaten-vs-planned.md)'s leftover question
- **Created:** 2026-11-01

## Goal

When you plan next week, the picker offers what last week left behind
before anything else: cooked leftovers that are still good, and recipes
that use up last week's spare fresh food, ranked so the food you would
mind wasting comes first. The shop offers that spare food as already at
home, and Cook asks once what became of a leftover that ran out of time.
These are suggestions to eat, not a waste-tracking app: no new screens,
no new questions beyond the one Cook already asks.

Today a batch's leftover is counted on Cook and then forgotten. Nothing
brings it back when you plan, nothing takes it off the next shop, and
food bought for a meal that was never cooked is invisible.

## Rulings

Taken with the owner, 2026-10-31/11-01, against a clickable canvas
([Use it up](https://claude.ai/artifact/YHLGrzJJmRwCVvTgukA9Fp)). The
canvas is the source for the board frames.

- **The ticks say what was cooked.** A batch (one cook session, as Cook
  shows it) with at least one meal ticked by anyone was cooked. A batch
  nobody ticked was never cooked. The household ticks reliably, so a
  cooked batch with no tick at all is rare enough to accept a wrong
  suggestion.
- **A cooked batch's leftover is its planned portions less what was
  ticked** — the derivation plan 0054 already has (`uneatenPortions`), less
  what its answer already accounts for and less any meal planned from it.
  The household cooks the size Cook suggests, never smaller, so there is no
  whole-recipe setting and the planned portions are what was cooked.
- **Each batch has its own use-by:** its cook day plus the recipe's
  `keeps_for_days`. Curry cooked Monday and again Thursday is two
  leftovers with two dates: Monday's can be past while Thursday's is
  still offered.
- **An uncooked batch is spare ingredients, not a leftover.** It has no
  date and is never asked about; its ingredients join last week's spare
  (below), so its own recipe tends to top the suggestions.
- **Leftovers come first in the planning picker**, in a *Use up* block
  above the tabs, each with its portions and `good until` day, and only for
  a slot on or before that day.
- **Planning a leftover is a meal *from* that batch** — not cooked again,
  not bought, and not costed this week (it was bought last week). Its
  portions are capped by what is left, and the confirm sheet says what is
  still left after it. Ticks, macros and Health Connect treat it as any
  recipe meal.
- **Spare food is last week's bought less last week's needed**, for fresh
  categories only (produce, dairy, proteins), from the week just gone and
  never older. Bought is the receipt's pack × count where a receipt covers
  the line; otherwise the shop's own whole count (4 onions for 3½) and the
  pack its price states (a 500 g bag for 200 g). Needed counts only cooked
  batches and bare items, so an uncooked batch's ingredients are spare.
- **Spare food is a suggestion, never tracked.** No dates, no question,
  nothing stored about it.
- **A recipe scores by what the amounts it would use cost:** for each spare
  ingredient, `min(the recipe's amount, what is spare) × its unit price`
  ([ADR-0017](../../decisions/0017-a-cost-is-a-unit-price-never-an-allocation.md)),
  summed. Not the pack price paid — a 500 g garlic jar adds pennies because
  a recipe uses 10 g of it — and not the recipe's own cost. Cheap and
  long-keeping things fall away on their own.
- **Show up to three recipes, each scoring at least half the top one.** The
  row names the spare it uses as chips (`spinach 300 g · feta 150 g`).
- **A *what's left ›* link** beside the heading opens one pane: the spare
  food with how it was worked out (`500 g bag · used 200 g`), then the
  ranking with the cut drawn. It is the one place the reasoning is visible;
  there is no other door to it.
- **The shop offers spare as at home, never silently.** A row whose
  ingredient has spare from last week carries `300 g left from last week?`
  with **Use it**, which writes plan 0055's at-home amount; one **Use all**
  above the list does every row. A guest or a missed tick would otherwise
  leave you short.
- **Cook asks one question, later and smaller.** Only when a cooked
  leftover passes its use-by without being planned or ticked:
  **Binned · We ate it**. *Kept* is gone — keeping is what happens until the
  date. Spare food is never asked about.

### Rejected

- **A *keeps fine* flag per ingredient** (onions, garlic, potatoes). It puts
  the work on the household; costing what a recipe would use makes them
  negligible without it.
- **Ranking by share of the total spare.** One bulk jar in the total makes
  every recipe look like it uses nothing.
- **Weighting by the pack price paid.** The garlic jar would top every
  ranking.
- **A *we cook whole recipes* setting.** The household cooks the size Cook
  suggests.
- **A *did you cook it?* question, or a correction checkbox.** The ticks
  answer it; *We ate it* on Cook covers a forgotten tick.
- **Removing Cook's question altogether.** The owner still wants to be
  asked when a leftover runs out of time.
- **Suggestion cards on the Week screen, a standalone fridge or pantry
  list, a warning before something goes off.** Not for now: the picker and
  the one question carry it.
- **Shelf-life tiers per ingredient, pack-size inference, waste scoring,
  multi-step cooked → eaten / binned chains, who ate it on Cook.**
- **Deducting spare from the shop without asking.**
- **A freshness window for raw protein from an uncooked meal.** The
  household is vegan, and spare food is offered for one week only.

## Approach

Phases land in order; each is shippable alone.

### Phase 0 — the board

1. Draw the frames as `proposed` in their own screen files
   ([board README](../../product-specs/board/README.md)): the *Use up* block,
   the leftover confirm sheet and the *what's left* pane in
   `recipe-picker-confirm.html`; the shop row's offer and *Use all*, and
   the new question, in `cook-shop.html`. The canvas linked above is the
   source.

### Phase 1 — leftovers across weeks

2. **Domain (`cook_plan/domain`, pure):** per session, `cooked` (any covered
   meal ticked), `useBy` (the cook day's date + `keeps_for_days`), and the
   portions still left (uneaten less answered less planned from it). A
   household's leftovers are the cooked sessions of this week and last with
   portions left and a use-by not yet passed. Tests on the cook plan's own
   fixtures, including two batches of one dish with different dates.
3. **Migration `0059_plan_entry_leftover_of.sql`:** `plan_entry.leftover_of
   uuid null references plan_entry(id)` — the batch's key entry, the same
   key `batch_leftover` uses — on a recipe entry only. Both PowerSync stream
   files and the local schema.
4. **One choke point, as for `instead_of`:** the cook plan and the shop pass
   over an entry with `leftover_of` (their SQL reads `leftover_of is null`),
   and the week's cost does too; macros, ticks and Health Connect count it.
   A test per derivation.
5. **Picker:** the *Use up* block with its *Leftovers* rows, and the confirm
   sheet's `leftover` pill, *Not cooked again, not bought*, and a portions
   stepper capped at what is left.

### Phase 2 — the one question

6. Cook's leftover card asks only once a cooked leftover's use-by has
   passed, with **Binned · We ate it**, written to `batch_leftover` as today
   (`binned` or `eaten`; `kept` stays 0 — no migration). The Week band's
   line keeps its shape.

### Phase 3 — spare food and the suggestions

7. **Domain (pure):** last week's spare per ingredient — bought (receipt
   lines filed to that week, else the shop's whole count and its price's
   pack) less needed (cooked sessions and bare items, after what was
   already at home) — for the fresh categories, as a constant beside
   `kImpreciseCategoryGates`. A stub that cannot convert between the pack
   and the recipe's unit is left out, never guessed (invariant 3).
8. **Ranking (pure):** the score above, the top three at half the top or
   better, scaled to the slot's eaters. An unpriced ingredient adds nothing
   to a score and is still named as a chip.
9. **Picker:** the *Uses last week's shop* rows and the *what's left* pane.

### Phase 4 — the shop

10. Next week's rows offer last week's spare (*Use it*, *Use all*), writing
    the at-home amount plan 0055 already stores; the offer is drawn only on
    the week straight after.

## Acceptance criteria

- [ ] A batch with any tick is cooked; one with none is spare ingredients
      and never asked about.
- [ ] Two batches of one dish carry two use-by dates; the picker offers
      only the one still good for the slot's day.
- [ ] A meal planned from a leftover appears in nobody's cook plan, shop or
      week cost (one test per derivation), and counts in macros and ticks.
- [ ] A leftover's portions fall by what is planned from it; the confirm
      sheet cannot plan more than is left.
- [ ] Cook asks only after a leftover's use-by, never about spare food,
      and offers no *Kept*.
- [ ] Spare food is from last week only, fresh categories only, and never
      from a stub that cannot convert.
- [ ] Suggestions follow the score: the garlic-jar and half-onion fixtures
      score near zero; a recipe under half the top is not shown.
- [ ] The shop never changes an at-home amount without a tap.
- [ ] Tests cover the new logic in `cook_plan/domain`, the spare and
      ranking domain, and the choke point.
- [ ] Docs updated: product spec (*Meal plan* data model, *Batch cook plan*,
      the picker, *Shopping list*), `docs/generated/db-schema.md`, the board
      frames from proposed to built, `ARCHITECTURE.md`'s standing table.

## Decision log

Append-only.

- 2026-11-01 — Plan written from the design rounds above. It replaces two
  of plan 0054's leftover rulings once built: *Kept* stops being an answer,
  and the question waits for the use-by rather than the batch's last day.
  Plan 0054's *Not in v1* (a kept portion offered back in the picker, and
  one taking a meal off the next shop) is this plan's phases 1 and 4.

- 2026-11-01 — Phases 1–4 built in one pass, the board frames after rather
  than before (the canvas linked above stood in for them). What the build
  settled that the plan left open:
  - **The question's place.** A batch's card asks on its own week; the week
    containing today also asks, in a `FROM LAST WEEK` card, about last
    week's batches that ran out of time unplanned, so a question is not
    missed for being filed under a week nobody is looking at.
  - **Before the use-by** the batch's card says the leftover in one quiet
    line, `1 portion left · good until Mon`, rather than nothing.
  - **An old `kept` answer** reads as unanswered; only binned or eaten is
    an answer.
  - **An unknown fridge life** is good until the batch's last meal, so such
    a batch is asked about as soon as its days are over and never offered.
  - **A batch still to come is not spare.** Planning next week mid-week,
    this week's later batches are not yet ticked; only a batch whose days
    are all behind us and that nobody ticked counts as never cooked.
  - **Spare is `need − toBuy + bought − usedCooked`** per ingredient in the
    row's basis unit: what was at home, plus what was bought (the week's
    receipt packs where a receipt carries the row, else the shop's whole
    count, else whole packs of the size its price states), less what the
    cooked meals and bare items used — the list derived a second time
    without the never-cooked batches' meals.
  - **The suggestions are scored for everyone's usual meal** (Σ portion
    factors), since the picker does not know the eaters until the confirm
    sheet; a recipe's optional lines and its components' lines are not
    counted.
  - **The shop's offer is in grams or millilitres** (the row's basis unit),
    taken off a counted row through its piece weight; a row that will not
    weigh is offered nothing.
  - **Receipt packs are read in the price repository** (`loadBoughtPacks`),
    the one file that owns what a receipt line means.

- 2026-11-01 — Three corners from the first pass, put right on the
  owner's reading of them:
  - **Spare food is said in the row's own words.** The Shop's offer was in
    grams (`75 g left from last week?` on an onion row); it is now a count
    of the row's measure or of pieces, else the total's unit (`½ onion,
    medium left from last week?`), stored that way, a count coming down to
    the quarter below. The picker's chips and the pane say a count where
    the row states a piece weight, amount first (`½ yellow onion`).
  - **A recipe's use counts its sub-recipes**, scaled by the batches of
    each a line asks for (`perBatchUse`), as the shop buys the dish.
    Optional lines still count only where a week ticks them in.
  - **The wide layouts ask and offer too**: the schedule sheet asks under
    each batch's words, and the wide Shop walk carries the offer and *Use
    all*. Only the at-home pass does not offer.

## Notes / open questions

- **The *what's left* pane** stays behind its link; drop it if it goes
  unused in the field.
- **A substitute from a leftover** (plan 0054's open question: ate Monday's
  spare curry instead of the ragù) — *Had instead* could offer the same
  *Leftovers* rows. Not in this plan.
- **Ask Ansi** reads the week's entries; whether it should say *from
  leftovers* is its own follow-up.
- **A frozen batch** (freezer merging) is not a fridge leftover; this plan
  offers fridge leftovers only.

## Step-done checklist

The code landing is not the step landing. Tick these before setting Status to
done and moving this file to `completed/`.

- [ ] Roadmap row updated: status flipped, one line on what shipped and what was
      deliberately deferred.
- [ ] `ARCHITECTURE.md`'s standing table matches reality for every area touched.
- [ ] `app/AGENTS.md` "Current focus" and command list still true.
- [x] Feature steps: `make test-sim` run on a booted simulator (the UI paths CI
      can't reach), and the result recorded here. All nine files green on
      the Android emulator (`sim` dispatch, run 41306323147, on `c8985e8`).
- [ ] Tech-debt rows **added** for corners knowingly cut, and **retired** (or
      narrowed) for debt this step paid off.
- [x] New migrations or seed changes? Say in the roadmap row whether they have
      reached **cloud** yet, and append a `docs/cloud-setup.md` ledger entry
      when they do. `0059` reached cloud in deploy 41308689885; ledger entry
      2026-11-01. A "pending cloud push" note nobody clears becomes a false
      claim the moment the push happens.
- [ ] `make ci` green.
