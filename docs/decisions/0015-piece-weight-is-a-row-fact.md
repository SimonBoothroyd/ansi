# ADR-0015 — A piece weight is a row fact, exactly as a density is

- **Status:** accepted (2026-09-08, Simon — owner-ruled)
- **Supersedes:** [ADR-0010](./0010-piece-is-an-admission-fact.md) **entirely**
  (`piece` is no longer curated off a row by hand; it is unlocked by a number),
  and the **"Counts as" seam** of [plan 0024](../exec-plans/completed/0024-field-test-round-two.md)
  seam D1 / migration `0023` (`ingredient.default_measure_id`), which said what
  a bare count *meant* by pointing at a measure.
- **Amends:** [ADR-0014](./0014-all-to-all-admission.md) §Decision leg 3. Where
  it reads "`piece` on a count-default row. ADR-0010 unchanged", it now reads
  **`piece` on a count-default row that has a piece weight**. Everything else in
  ADR-0014 stands, as does [ADR-0008](./0008-unit-admission-model.md) (units are
  admitted per ingredient, via an explicit mapping into the basis) and
  [ADR-0009](./0009-density-unlocks-both-families.md) (a density unlocks the
  other family whatever the default unit is, and deleting it strips what it
  granted).

## Context

ADR-0010 answered "what does a `piece` mean?" by refusing to let a row say
`piece` at all wherever a clearer word existed. Plan 0024 then answered "what
does a bare count mean?" a second time, with `default_measure_id` — a pointer
from the row to one of its own measures, drawn on the form as **Counts as** and
spent, once and visibly, on the import review's card.

Two answers to one question is one answer too many. A household reading the
form saw an onion whose sizes were measures, whose bare count pointed at one of
them, and whose `piece` had been curated away by a line in a file it will never
open. The owner, on the dragon-fruit walk-through:

> *"we're duplicating info / making a slightly too messy mental model"*

and then, on the three screens where it shows:

> *"i think something shouldn't be saveable without a weight"*
>
> *"piece would should only show if default unit is piece"*
>
> *"why is piece weight allowed on recipe import… it's a property the
> ingredient must define!!"*

The model those three sentences describe is the one the app already has for
volume. A density is a number on the row that says what a volume of this
weighs, and its presence is what admits the volume family. Nothing curates
`cup` off a row; the number does. There was no reason for a count to work any
other way, and every difference between the two was machinery.

## Decision

**A piece weight is a row fact, exactly as a density is.**
`ingredient.piece_basis_amount` says what **one** of this ingredient weighs, in
the row's basis unit (g or ml). `ingredient.piece_source` says where the number
came from — `manual`, or *borrowed from &lt;measure label&gt;* where the seed
copied it from a curated size (onion borrows `onion, medium` = 110 g).

Density says what a volume of this weighs and unlocks the volume family; a
piece weight says what one of this weighs and unlocks `piece`. Six rules follow,
and five of them are the density rules re-read for a count:

1. **`piece` is admitted iff the row's default unit is `piece` AND the row has
   a piece weight.** It is never offered on a row with any other default unit,
   and the piece-weight field appears on the form only while the default unit is
   `piece`. Setting the weight unions `piece` into `allowed_units` in the same
   write; clearing it strips `piece` back out — ADR-0009's D4b removal leg, on
   the other number.

2. **Measures are unchanged, and are now the *only* thing they were ever for**:
   the words for sizes, fragments and containers — `onion, small` · `clove` ·
   `can (400 ml)`. Nothing is named after the row, no measure is auto-created,
   and no measure is pointed at by the row.

3. **A `piece` default with no weight is a stranded default**, in the same class
   as a `cup` default with no density (the D4c rule). The form draws the flag
   with its one-tap fix — *piece needs a weight on this row — enter one below,
   or switch to g* — and **refuses Save**. A row is not saveable as
   `piece`-default without a weight.

4. **The import review never enters a piece weight.** It is the ingredient's
   property, not the line's. A counted line on a row that does not admit `piece`
   is the ordinary `unitNotAllowed` gate ("Pick a supported unit"); the fix is
   the row's own form — the chosen-ingredient row on the card opens it — or
   picking another unit or measure chip. A counted line with **no printed unit**
   is validated as `piece`, so it is gated by the same rule rather than by a
   rule of its own.

5. **The macro engine converts a `piece` line through the piece weight like any
   other unit.** There is no read-through rule and no "counted as" note. A
   legacy bare-count line on a row with no weight reads **needs a piece weight**,
   and that marker opens the *ingredient's* form rather than the recipe editor:
   one number fixes every bare count of that ingredient in every recipe, the way
   a density fixes every `cup` line.

6. **Nothing is curated.** `piece` comes off garlic because garlic has no piece
   weight, not because a line in `curation_overrides.jsonl` says so. The 143
   `remove: ["piece"]` overrides become `piece_weight` rulings that borrow the
   curated size, and the seed states a number where it used to state an absence.

### What is retired

Removed from the app in the same change: **Counts as** (the column
`ingredient.default_measure_id` stays in Postgres for one release, unread by
every client), the *"You added X. Still offer piece?"* question,
`stopOfferingPiece`, `arrivalMeasure` / `unitFromDefault` and the review card's
`counts as pepper, medium · 119 g` line, the seed's 143 `remove: ["piece"]`
curation overrides, and `0023`'s backfill.

## Consequences

- **Onion carries 110 g twice** — as its piece weight and as the measure
  `onion, medium`. That is the cost, and it is two honest statements rather than
  one fact stored twice: *an unsized onion weighs 110 g* and *a medium onion is
  110 g*, the first sourced from the second and free to diverge the moment a
  household disagrees. The thing ADR-0010 feared was an **unweighed** `piece`
  sitting beside a weighed `clove`, where nothing downstream could say what the
  line meant. A weighed one beside a size is not ambiguous.
- **"Ask me each time" is gone.** Broccoli's `whole` / `spear` / `crown` were
  three different things and none of them was "a broccoli", so plan 0024 let the
  row answer *null* and kept flagging every counted line. A count-default row now
  weighs a piece or defaults to a mass or volume unit: broccoli takes `whole`'s
  weight as its piece, and `spear` and `crown` stay measures. The nuance the null
  carried is real and is deliberately traded for one model.
- **Pre-existing rows can be stranded, and only pre-existing ones.** A row
  created before this lands may sit on a `piece` default with no weight; the form
  and the import both refuse to create a new one. That legacy state reads as the
  sibling of *needs a density*, which is what it now is, and it clears one row at
  a time as somebody types a number.
- **`piece` becomes reachable again on rows that carry a measure.** ADR-0010's
  headline consequence — the seeded template admitted `piece` nowhere — is
  reversed: after the reseed a count-default row admits `piece` exactly when it
  states a weight, measures or no measures. The pgTAP assertion that pinned "zero
  rows admit `piece`" is retired with the ruling it pinned.
- **One fewer stored pointer, one more stored number.** `default_measure_id`
  needed an own-measure trigger, a soft-delete clear, a by-label carry in
  `ensure_onboarded` and a frozen backfill list, because it referenced a row.
  `piece_basis_amount` is a scalar in the basis unit and needs none of them: it
  clones with the ingredient like `density_g_per_ml` does.
- **The import gets stricter, in the direction the owner asked for.** "2 dragon
  fruit" on a fresh stub used to commit silently as a bare count and then
  contribute nothing to any total. It now stops at the review as an ordinary
  unsupported unit, with the row's form one tap away.

## Rejected alternatives

- **The first mockup's answer: auto-name a measure after the row, and keep a
  Counts as pointer at it.** Creating a `dragon fruit` measure labelled after
  its own ingredient puts the row's name in two places and invents vocabulary
  nobody asked for — and it keeps the pointer, which is the duplication the
  owner named. A weight is a number about the row; it belongs on the row.
- **Leave the sum reading Counts as** — let the macro engine follow
  `default_measure_id` when a line says a bare count. It is the read-through
  rule this ADR deletes: it makes the meaning of a stored line depend on a
  pointer that can be re-aimed later, so the same saved recipe silently weighs
  something different next month. The piece weight can change too, but it changes
  *the row's stated weight of a piece*, which is what the line always said.
- **Enter the weight on the import card.** Drawn, and rejected by the owner in
  the sentence above: it is the ingredient's property, and a review card is
  where a *line* is fixed. Putting the field there also means the same number
  can be typed on two screens with nothing to say which one won.
- **Keep ADR-0010's curation as well, as belt-and-braces** — a row would then
  need both a weight and the absence of a removal line to say `piece`, which is
  two gates on one fact and the exact shape ADR-0008 spends its length refusing
  for density.
