# Exec plan: Food cost, receipts, and a meal eaten out

- **Status:** active — phases one and three shipped as `v0.19.0`, phase two as `v0.20.0`; open: the owner's review, then the feedback pass and the desk's three-column receipt review
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

- [x] Migration `0044_receipts.sql`: `receipt` and `receipt_line`, household
      RLS in the measures' shape, soft delete, PowerSync rules in both the
      docker and the cloud streams file. A hand-typed price is a one-line
      receipt with `source = 'manual'`.
- [x] The price sheet on the ingredient page: paid, for a pack in a unit the
      row admits (its measures leading the chip row), at a store chip; the
      dock states the per-basis figure before Done and refuses a volume pack
      on a g-basis row with no density. The pack is kept **as entered** as
      well as in the basis (0046), and the same sheet, opened on a stored
      line, edits or deletes it.
- [x] The **Price** group on the ingredient page, read posture: the latest as
      one line, earlier prices kept as paid, the unpriced state as one door.
- [x] Cost summation in pure Dart beside the macro summation: per line, in
      the basis, through the same conversions; imprecise and optional lines
      out by the macro rule; a line with no price or no path to the basis is
      **unpriced**, named, and takes the recipe's cost cell with it. A planned
      bare ingredient is costed the same way, from its own row's latest price.
- [x] The recipe panel flips between `Macros | Cost` (seg chips, session
      posture); Cost reads *a serving · the recipe · prices from <month>*
      with `UNPRICED`, `OLDEST` and `NOT COUNTED` rows. The ⋯ item becomes
      **Show line figures** and prints whichever the panel reads.
- [x] The week band reads `≈ $71 to cook · 3 lines unpriced` under the macro
      line; the shop's sync line carries the trip estimate and each row its
      own under the grams, `no price yet` where there is none. The **wide**
      Week has no home for the band yet (tracker row), so its cost line is
      drawn on the phone only.
- [x] ADR-0017 written: cost is a unit price, never an allocation.

Phase two — receipts and spend:

- [x] `import-receipt` edge function (or a receipt mode of `import-recipe`,
      whichever keeps the adapters and the SSE stages shared): the same
      Haiku 4.5 pin, transcribe then structure, native JSON schema; output
      is store as printed, date and time as printed, printed subtotal / tax
      / total, and lines each with printed text, cents, an attached discount,
      printed weight and rate where present, and a kind (`item · not_food ·
      tax · fee`). No vocabulary in the prompt (ADR-0004).
- [x] Multi-photo joins **by position**: consecutive segments of one strip,
      the seam the longest run of identical consecutive lines shared by the
      end of one and the start of the next. Never by item identity.
- [x] The review: store chip over the paper's words, the receipt's own date,
      printed totals, and the join card holding the lines' sum against the
      subtotal — a flag, not a refusal. Line cards with money first; a
      by-weight line prices itself from the printed rate; **Say what the
      pack is** on a matched row with no pack, with *keep as a measure*;
      **Not food** moves a line under the fold. Save writes one `receipt`
      and its lines; every matched item line with a pack is a price.
- [x] **No alias is learned from a receipt.** The server match runs afresh
      each time; the pack kept as a measure is what carries over. *(The server
      half landed with R1 and is held structurally, not by prose:
      `import-receipt/no_alias.test.ts` runs the spine over the real
      Postgres-backed matcher with a spying executor and asserts every
      statement the function issues is a `SELECT`. The pack's carry-over is
      R2's.)*
- [x] The Receipts ledger, by week (the household's week start) and store,
      spent against planned per week, a month line on top; opened from the
      band's *spent* line and the shop's **scan a receipt** door.
- [x] The band shows `spent` only when a receipt is dated inside the week.

Phase three — a meal eaten out:

- [x] Migration `0045_plan_entry_out.sql`: `label text` and `macros jsonb`
      on `plan_entry`; the entry XOR becomes three-way (recipe · ingredient
      · label), checked in the constraint.
- [x] `PlanEntry.isIngredient` becomes a `kind` enum (`recipe · ingredient ·
      out`); `MealTarget` gains a third sealed case; a seam test asserts
      every derivation branches on the kind.
- [x] The picker's third answer when the typed words match nothing: *note it
      — "Office lunch" · not cooked, not bought*. The confirm sheet keeps
      slot, eaters and portions and adds the optional macros fold on the
      existing macro keypad.
- [x] The week row at a third weight: plain italic, an `out` tag where the
      cook marker sits, its figures beside it when stated; the day's scope
      line names `office lunch not counted` otherwise. Cook and Shop never
      see it. Copy last week carries it, figures and all. The default-slot
      rule treats the slot as filled.
- [x] Tests mirror every new domain rule; the board's hatch frames move
      into their screen files as built; roadmap and ARCHITECTURE rows.
      A wide frame is drawn beside them: the agenda's run marks the meal with
      a hollow dot, the day pane draws the phone's row, and the picker and
      confirm sheet are unchanged dialogs from 640.

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

- 2026-09-16 — **Cost is a unit price, never an allocation** — written up
  as [ADR-0017](../../decisions/0017-a-cost-is-a-unit-price-never-an-allocation.md)
  at P2's landing. Assigning a
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

- 2026-09-17 — **A price keeps the unit it was entered in** (owner). The
  ledger stored the pack in the row's basis, so a pound read back as `454 g`.
  Migration 0046 adds `pack_amount` + `pack_unit` beside it: `pack_unit` is a
  units.dart catalog id, or null where the pack was tapped as one of the row's
  own measures, in which case `pack_amount` is the COUNT of it and the
  measure's label is the word. `pack_basis_amount` STAYS what a price is
  derived from, so a measure re-weighed later cannot re-price a shop that
  already happened; existing lines are backfilled with the pack the database
  actually knew — the basis figure, in the basis unit.
- 2026-09-17 — **An edit and a delete door for a stored price** (owner).
  There was no way to fix a mistyped price. The Price group's *Latest* line and
  every row under *Before* are taps onto the same sheet, opened on that line;
  Done writes an UPDATE and keeps the day the price was paid on (a correction
  is not a second shop), and a **Delete** under it tombstones the line behind
  the app's shared destructive confirm. The line's receipt moves with it only
  when it is this app's one-line `manual` kind — a photographed receipt is a
  piece of paper, so its printed figures stay and it is never deleted here.
- 2026-09-17 — **A planned snack is costed when its row has a price**
  (owner: *"it should be costed if that ingredient has a price"*). It is
  weighed the way `ingredientPortionMacros` weighs it — the entry's own amount,
  unit or measure carried to the row's basis through the same conversion —
  times the latest price per unit of that basis. It is named unpriced only when
  the row truly has no price or nothing carries its amount to the basis, with
  the recipe cost's own reasons. A meal eaten out stays passed over.

- 2026-09-17 — **A second function, not a receipt mode** (R1). The plan left it
  open. A mode flag would have made one payload type two and one door's tests
  cover neither, which is how a client ends up decoding a default. What was
  genuinely shared was moved DOWN instead: `_shared/auth.ts` (one allowlist —
  a household allowed to photograph a recipe is the same household allowed to
  photograph its receipt), `_shared/http_edge.ts` (the photo cost caps, the SSE
  frame, CORS), `_shared/failures.ts` (three shapes, one subject word apiece),
  and the Haiku pin, imported rather than re-declared so a receipt can never
  drift onto a different model than a recipe.

- 2026-09-17 — **Transcription returns one string PER PHOTO** (R1). Still ONE
  vision call: the prompt asks for a `[PHOTO BREAK]` between segments and the
  server splits on it. A model handed all the photos and asked for one document
  would have to decide whether a repeated line is an overlap or a second
  banana — and it would be believed. The join stays ours, positional and
  unit-tested; a replay fixture holds the photos unjoined for the same reason.

- 2026-09-17 — **The model splits the line; it still never matches** (R1). Each
  line comes back twice: `printed_text` verbatim, and `name_printed`, the same
  characters with the money, weight and rate taken off. Only the second reaches
  the cascade, because `TJ ORG BANANAS 3.49` trigram-compared against the
  vocabulary is a price being matched. It is not a match and not a guess at our
  catalogue, and `name_printed` does not appear in the payload at all.

- 2026-09-17 — **An unreadable figure counts as nothing, loudly** (R1). The
  contract has nowhere to put "unreadable" on a line's `cents`, so such a line
  lands at 0 with `low_confidence` set and a note naming it — three signals a
  review stops on. What it never does is quietly contribute a plausible figure
  to a sum. Money is parsed from digits, never through a float: `parseFloat`
  makes 3.49 into 348.99999999999994, and money that rounds stops adding up
  against the printed subtotal.

- 2026-09-17 — **Tax is out of the reconcile; a tax line is still a line**
  (R1). A subtotal is the figure before tax, so `lines_sum_cents` excludes
  `kind = 'tax'` — but the line is returned, because the review draws it under
  the fold and the paper's total has to be checkable against it. A slashed
  date is read month-first and a two-digit year as 20YY, both because the
  household shops in the US and a receipt from 1926 is in nobody's drawer; the
  review's *change ›* door is the answer where a paper means otherwise.

- 2026-09-16 — **One vocabulary for the refusal.** The brainstorm drew a
  day scope line reading `office lunch not counted` beside a denominator of
  `2 meals`. Built, the week says the same thing in the words it already
  uses for a stub ingredient: the denominator moves to `1 of 2 meals` and the
  day names `left out: Office lunch · macros not stated`. Two spellings of one
  refusal would be a second vocabulary for the week to drift within, and the
  mandatory denominator is D4's teeth. The frames on the board are drawn as
  the code prints it.

- 2026-09-17 — **The pack carries over, not the word** (R2). The board's
  frame promised that entering a pack once means "the next receipt lands on
  *bottle (482 g)* and asks nothing", and the obvious reading — mint a measure
  and match on it — needed a rule for which measure is *the pack*. There is a
  simpler fact already in the ledger: the row's **latest price** knows what
  the household last bought it in. So a matched item line with no printed
  weight opens on that pack, in both denominations, with the stored basis
  figure rather than a re-derivation — a measure re-weighed since cannot
  re-price a shop that already happened. *Keep as a measure* stays, and is now
  a genuinely separate gain: a word the household can also say in a recipe.
- 2026-09-17 — **An unreadable figure is flagged, never a free line** (R1's
  contract, ruled at R2). `cents: 0` with the reader's own doubt beside it is
  not a discovery that the food was free: it holds Save, drags the join open
  and carries a **Set the amount** door that reads the figure off the paper.
  The alternative — passing a zero through as "honestly unpriced" — would have
  made a receipt quietly add up short.
- 2026-09-17 — **Deleting a price on a photographed receipt keeps the line**
  (owner). Phase one's delete tombstoned the line; on a piece of paper that is
  wrong, because the cents were paid and the receipt has to go on adding up.
  It now clears only the line's **price facts** — `pack_basis_amount`,
  `pack_amount`, `pack_unit`, `measure_id` — and leaves `ingredient_id`,
  because what was bought is not in doubt; only what the pack was. A hand-typed
  one-liner still tombstones line and receipt together, having nothing left to
  be. The confirm says which of the two is about to happen.
- 2026-09-17 — **The ledger rides the scan door's row** (R2). The brief left
  the choice open between a second small door on the Shop and a long-press on
  the first. Neither: a third dashed box is a third thing to read past on every
  walk, and a long-press is a door nobody can find. A quiet `receipts ›` sits
  at the end of the scan door's own row, and only once the household has kept
  a receipt — a door onto an empty page is furniture.
- 2026-09-17 — **A receipt's date is wall time** (R2). `purchased_at` is
  stored with the paper's own clock components and a `Z`, not converted: a
  Sunday 17:42 shop read back on a phone seven hours west would otherwise file
  into Monday's week. The zone the shop happened in is not a fact this
  household needs; the date on the paper is.
- 2026-09-17 — **Bought is read-only, for now** (R2). The frame drew a
  `change ›` beside the receipt's date. The app has no date control to open,
  and a receipt's date is the paper's fact rather than an answer somebody
  gives — so the review prints what was read with the printed words under it,
  and says which it is. A receipt the reader could not date opens on the day of
  the scan and says so. The door is cheap to add the first time a real receipt
  is misread.
- 2026-09-19 — **The first real receipt was misread, so the doors went in**
  (owner's phone review of v0.20.0, a 29-line Trader Joe's strip). Three
  faults and three missing doors, one pass:
  - `09-12-2026` did not parse — the month-first pattern took `/` and `.` but
    not the dash TJ's prints. It does now.
  - The join card ticked green beside `$96.62` under a printed total of
    `$91.54`, because the strip prints no subtotal and "nothing to disagree
    with" was read as agreement. With no subtotal the lines are held against
    **total less tax**, and the card says that is the figure it used.
  - An unmatched card was titled with the whole printed line, price and all.
    `name_printed` now rides the wire (additive) and titles the card.
  - **Bought is a door** (supersedes the entry above): a calendar sheet, the
    day moves and the clock stays, no day after today.
  - **PRICE is a chip on every open card**, not only on a line whose figure
    read as zero.
  - **One screen for a receipt** (owner: "the edit receipt and import receipt
    review are basically the same view"). `/receipts/:id` opens the review on
    the rows; Save rewrites them in place (`updateReceipt` — kept lines by id,
    new ones inserted, dropped ones tombstoned; the printed totals and printed
    words never move) and *delete this receipt* sits under it. This retires
    "a price on a receipt line is edited on the ingredient's page": that was
    one door for a price when a receipt was read-only, and it is two once a
    receipt is not. The ingredient page's price sheet still edits the same
    row from the other side.
- 2026-09-17 — **The desk's three columns are not built** (R2). The phone
  review works at the 640 measure on a wide window, and the width would buy one
  thing: the printed line standing beside the card that claims to read it. It
  is drawn, it is in the hatch, and it has its own backlog row rather than
  holding this phase open.

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

- [x] Roadmap: the Next list names this plan; phases one and three sit under
      *On main, not yet tagged*; phase two joins them when it lands.
- [x] `ARCHITECTURE.md` standing table: ingredients (price fact), recipes
      (cost reading), planning (the third kind), shopping. *(import waits on
      receipts.)*
- [x] Backlog: the price row, the meal-out row and the receipt row have all
      retired; one narrower row replaces the last of them — the desk's
      three-column receipt review, drawn and unbuilt.
- [x] Board: hatch frames move into `ingredient-detail`, `recipe-page`,
      `week`, `cook-shop`, `import-review`, `recipe-picker-confirm` as
      built; a new `receipts` view file with its status row. *(the one frame
      still in the hatch is the desk's three-column receipt review, which
      has a backlog row of its own.)*
- [x] ADR-0017 (cost is a unit price) written at P2's landing.
- [ ] `make ci` green on every landing so far; `make test-sim` on one
      simulator, serially, when the owner says go.
- [ ] `deploy-supabase` run by hand for R1 — the workflow now deploys
      `import-receipt` by name beside `import-recipe`, and the two share the
      `ANTHROPIC_API_KEY` / `IMPORT_ALLOWED_HOUSEHOLDS` secrets, so nothing new
      is set by hand; sync rules recreated for 0044 and 0045. **0046 needs no sync-rule edit** — both receipt rules are
      `select *`, so the two new columns arrive with the migration — but the
      local container still has to be recreated from the checkout that holds
      it before a device sees them.
