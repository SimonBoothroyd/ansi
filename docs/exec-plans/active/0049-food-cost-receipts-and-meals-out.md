# Exec plan: Food cost, receipts, and a meal eaten out

- **Status:** active — design signed off on the board; phase one next
- **Owner:** Simon (design and rulings), agents in lanes
- **Roadmap step:** Next 1 — the first ideas off the backlog
- **Created:** 2026-09-16

## Goal

Three things the app cannot say today, each a backlog row, each drawn in
[the board's hatch](../../product-specs/board/not-built.html):

1. **What a recipe costs.** A price is a row fact with history — cents paid
   for a stated pack, at a store, on a date — and a recipe, a week and a
   basket read what their lines cost at the latest price. An unpriced line
   is named, never zeroed.
2. **What the shop cost.** A photographed receipt reads through the recipe
   import's own pipeline, is matched line by line in review, and is kept
   whole, so spend per week and per store reads off the receipts themselves
   and every line on one writes the price fact above.
3. **A meal eaten out.** A third kind of planned meal — a label, its eaters,
   optional per-portion macros — that fills a slot, is neither cooked nor
   bought, and counts in the day only when stated.

## Acceptance criteria

Phase one — prices and cost:

- [ ] Migration `0044_receipts.sql`: `receipt` and `receipt_line`, household
      RLS in the measures' shape, soft delete, PowerSync rules in both the
      docker and the cloud streams file. A hand-typed price is a one-line
      receipt with `source = 'manual'`.
- [ ] The price sheet on the ingredient page: paid, for a pack in a unit the
      row admits (its measures leading the chip row), at a store chip; the
      dock states the per-basis figure before Done and refuses a volume pack
      on a g-basis row with no density.
- [ ] The **Price** group on the ingredient page, read posture: the latest as
      one line, earlier prices kept as paid, the unpriced state as one door.
- [ ] Cost summation in pure Dart beside the macro summation: per line, in
      the basis, through the same conversions; imprecise and optional lines
      out by the macro rule; a line with no price or no path to the basis is
      **unpriced**, named, and takes the recipe's cost cell with it.
- [ ] The recipe panel flips between `Macros | Cost` (seg chips, session
      posture); Cost reads *a serving · the recipe · prices from <month>*
      with `UNPRICED`, `OLDEST` and `NOT COUNTED` rows. The ⋯ item becomes
      **Show line figures** and prints whichever the panel reads.
- [ ] The week band reads `≈ $71 to cook · 3 lines unpriced` under the macro
      line; the shop's sync line carries the trip estimate and each row its
      own under the grams, `no price yet` where there is none.
- [ ] ADR-0017 written: cost is a unit price, never an allocation.

Phase two — receipts and spend:

- [ ] `import-receipt` edge function (or a receipt mode of `import-recipe`,
      whichever keeps the adapters and the SSE stages shared): the same
      Haiku 4.5 pin, transcribe then structure, native JSON schema; output
      is store as printed, date and time as printed, printed subtotal / tax
      / total, and lines each with printed text, cents, an attached discount,
      printed weight and rate where present, and a kind (`item · not_food ·
      tax · fee`). No vocabulary in the prompt (ADR-0004).
- [ ] Multi-photo joins **by position**: consecutive segments of one strip,
      the seam the longest run of identical consecutive lines shared by the
      end of one and the start of the next. Never by item identity.
- [ ] The review: store chip over the paper's words, the receipt's own date,
      printed totals, and the join card holding the lines' sum against the
      subtotal — a flag, not a refusal. Line cards with money first; a
      by-weight line prices itself from the printed rate; **Say what the
      pack is** on a matched row with no pack, with *keep as a measure*;
      **Not food** moves a line under the fold. Save writes one `receipt`
      and its lines; every matched item line with a pack is a price.
- [ ] **No alias is learned from a receipt.** The server match runs afresh
      each time; the pack kept as a measure is what carries over.
- [ ] The Receipts ledger, by week (the household's week start) and store,
      spent against planned per week, a month line on top; opened from the
      band's *spent* line and the shop's **scan a receipt** door.
- [ ] The band shows `spent` only when a receipt is dated inside the week.

Phase three — a meal eaten out:

- [ ] Migration `0045_plan_entry_out.sql`: `label text` and `macros jsonb`
      on `plan_entry`; the entry XOR becomes three-way (recipe · ingredient
      · label), checked in the constraint.
- [ ] `PlanEntry.isIngredient` becomes a `kind` enum (`recipe · ingredient ·
      out`); `MealTarget` gains a third sealed case; a seam test asserts
      every derivation branches on the kind.
- [ ] The picker's third answer when the typed words match nothing: *note it
      — "Office lunch" · not cooked, not bought*. The confirm sheet keeps
      slot, eaters and portions and adds the optional macros fold on the
      existing macro keypad.
- [ ] The week row at a third weight: plain italic, an `out` tag where the
      cook marker sits, its figures beside it when stated; the day's scope
      line names `office lunch not counted` otherwise. Cook and Shop never
      see it. Copy last week carries it, figures and all. The default-slot
      rule treats the slot as filled.
- [ ] Tests mirror every new domain rule; the board's hatch frames move
      into their screen files as built; roadmap and ARCHITECTURE rows.

## Approach

Three worktrees off `origin/main`, landed in the order below. The cost
lanes share `core/units` and the macro summation's per-line record; the
receipt lanes share the price fact; the meal-out lane touches planning only
and can run beside phase one.

1. **P1 — the fact.** Migration 0044, sync rules (`--force-recreate` from
   this checkout), the repository, the price sheet and the Price group.
   Domain first: `PriceObservation` in the ingredients domain, per-basis
   derivation as a pure function with the density gate.
2. **P2 — the reading.** `costPerLine` beside the macro summation, the
   flipping panel, `Show line figures`, the week band line, the shop lines.
   A structural test that no money type reaches the macro record and no
   macro type reaches the cost record.
3. **P3 — the meal out.** Migration 0045, the kind enum, the seam test, the
   picker's third answer, the confirm fold, the week row, the copy carry.
4. **R1 — the server.** Receipt schema and prompt, the positional join, the
   reconcile figure, five to ten of the owner's receipts as **local-only**
   fixtures (the repo is public; a receipt carries a card's last four and a
   loyalty number).
5. **R2 — the review and the ledger.** The scan door on the shop, the
   camera's overlap line, the review screens, Save, the ledger, the band's
   *spent* line.

## Decision log

- 2026-09-16 — **Cost is a unit price, never an allocation.** Assigning a
  receipt's lines to a week's recipes was the first framing and was set
  aside: leftovers, last week's shop and a quarter's olive oil all make it an
  inventory problem, and ADR-0007 deliberately keeps no inventory. A recipe
  costs its lines at the latest price per basis unit; the gap between planned
  and spent is the pantry, shown on the band and never reconciled.
- 2026-09-16 — **The owner enters the pack.** Package weight, volume or
  size is typed once per row, in a unit the row admits; the receipt never
  prints it. Kept as a measure by the owner's tap in review — the import
  mints no measure, as before.
- 2026-09-16 — **Receipts are the price table.** No separate observation
  table: an ingredient's price is its latest `receipt_line` with a pack
  amount; a hand-typed price is a one-line manual receipt. One fact, one
  ledger.
- 2026-09-16 — **No alias learning from receipts** (owner). A receipt's
  words are one store's abbreviations; confirming one teaches the
  vocabulary nothing, and a whole-line alias scoped to a store was weighed
  and refused.
- 2026-09-16 — **The pipeline is reused as is.** Haiku 4.5 through the
  existing adapter, two calls, no benchmark lane; the receipt is a smaller
  and more regular document than a recipe page. Web pricing refused: TJ's
  has no API and Whole Foods' prices live inside Amazon.
- 2026-09-16 — **Store is a chip word, USD cents only.** No store table, no
  currency column, no sale flag or average: latest wins. Prices are dated by
  the receipt, not the scan.
- 2026-09-16 — **Where a recipe's cost lives.** Under the macro strip was
  rejected by the owner; a third page tab was argued against (a second copy
  of the list). The strip flips between two readings of the same lines, and
  the line toggle follows it. Signed off on the board.
- 2026-09-16 — **The meal out rides this plan** (owner). The 0046 brainstorm
  stands as the design: three-way XOR, a kind enum so a null recipe can never
  again mean "skip", every derivation naming what it does with the kind. Its
  two open questions are ruled minimally: **no recurrence** (copy last week
  is the repeat) and **no vocabulary row** (a meal out is a label and its
  figures, not a thing the household owns). Either can be reopened by the
  owner before P3 builds.

## Notes / open questions

- The `OLDEST` row names the oldest priced line whenever its month differs
  from the newest's; a finer rule waits on real receipts.
- A tall thermal receipt downscaled to 1,568 px on its long edge may be
  illegible; the overlap guidance is the first answer, server-side slicing
  of a tall image the second, built only if the first fails in the field.
- A discount printed under an item folds into that item's cents; a discount
  the model cannot attach becomes its own `fee` line with negative cents so
  the reconcile still closes.
- Receipt fixtures never enter the repo; the eval corpus already has the
  local-only pattern.
- Whether the shop's per-row estimate should also print on the basket's
  ticked rows; drawn on the open rows only.

## Step-done checklist

- [ ] Roadmap: the Next list names this plan; the row moves to *On main,
      not yet tagged* as each phase lands.
- [ ] `ARCHITECTURE.md` standing table: ingredients (price fact), recipes
      (cost reading), planning (the third kind), import (receipts), shopping.
- [ ] Backlog: the three rows retire as their phase ships.
- [ ] Board: hatch frames move into `ingredient-detail`, `recipe-page`,
      `week`, `cook-shop`, `import-review`, `recipe-picker-confirm` as
      built; a new `receipts` view file with its status row.
- [ ] ADR-0017 (cost is a unit price) written at P2's landing.
- [ ] `make ci` green; `make test-sim` on one simulator, serially, when the
      owner says go.
- [ ] `deploy-supabase` run by hand for R1; sync rules recreated for 0044
      and 0045.
