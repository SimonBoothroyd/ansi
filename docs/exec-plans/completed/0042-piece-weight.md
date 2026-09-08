# Exec plan: a piece weight is a row fact

- **Status:** complete — built in parallel lanes off one owner ruling and one
  approved mockup
- **Owner:** Simon (the ruling) · agent lanes (mockup, migration, seed, Dart,
  docs + board)
- **Roadmap step:** the backlog row *Piece and measurement, another pass*,
  built
- **Created:** 2026-09-08

## Goal

Say what a count means **once**. Before this, three things answered the
question: ADR-0010 curated `piece` off a row by hand, plan 0024's
`default_measure_id` pointed the row at one of its measures ("Counts as"), and
the measures editor asked the household a question the first time they named a
measure. The owner, on the dragon-fruit walk-through:

> *"we're duplicating info / making a slightly too messy mental model"*
>
> *"i think something shouldn't be saveable without a weight"*
>
> *"piece would should only show if default unit is piece"*
>
> *"why is piece weight allowed on recipe import… it's a property the
> ingredient must define!!"*

## The ruling

**A piece weight is a row fact, exactly as a density is** —
[ADR-0015](../../decisions/0015-piece-weight-is-a-row-fact.md), which
supersedes ADR-0010 entirely and the "Counts as" seam of plan 0024 / migration
`0023`, and amends ADR-0014's admission leg 3.

`ingredient.piece_basis_amount` says what one of the row weighs, in its basis
unit; `piece_source` says whether a person typed it or the seed borrowed it
from a curated size. Density unlocks the volume family; a piece weight unlocks
`piece`, and only where the default unit is `piece`. A `piece` default with no
weight is a stranded default the form flags and refuses to save. The import
never enters the number, because it is the ingredient's property. The macro
engine converts a `piece` line through it like any other unit.

## The mockup

The whole change was drawn first as a single page in the board's own classes —
the three-row fact table, the row with its weight, the stranded default, onion
borrowing `onion, medium`, the gated import card and the legacy recipe-page
marker — and approved as drawn before any code moved. Its frames are now the
board's: `ingredient-detail.html`, `quantity-measures.html`,
`import-review.html`, `recipe-page.html`.

## What shipped

| change | where |
|---|---|
| the column | `ingredient.piece_basis_amount` + `piece_source`, additive, backfilled from each row's curated default measure's `basis_amount` where one was set — a copy, stamped *borrowed from &lt;label&gt;* |
| the admission rule | `allowed_units.dart` · `default_allowed_units()` — `piece` iff a `piece` default with a weight; union on set, strip on clear, both mirrors pinned by the shared vectors |
| the stranded default | `unitSayableAsDefault` gains one clause; the flag, the two ways out and the Save refusal are the shipped `cup` ones re-worded |
| the sum | `recipe_macros.dart` · `week_macros.dart` — a `piece` line converts through the weight; the bare-count reason becomes `needs a piece weight`, and its marker opens the **ingredient's** form |
| the import | `line_validation.dart` — a counted line with no printed unit validates as `piece` and meets the ordinary `unitNotAllowed` gate; `arrivalMeasure` and the sole-measure pre-select go |
| the form | `PieceWeightEntry` beside `DensityEntry`, drawn only on a piece-default row; the quantity sheet's manage state hosts the same editor and writes on tap |
| the seed | the 143 `remove: ["piece"]` overrides become `piece_weight` rulings that borrow the curated size; the "template admits `piece` nowhere" pgTAP assertion retires with the ruling it pinned |
| removed | Counts as · the *"Still offer piece?"* question · `stopOfferingPiece` · `arrivalMeasure` / `unitFromDefault` · the card's `counts as …` line · `0023`'s backfill. `default_measure_id`, its trigger and its backfill function stay in Postgres for one release, unread by every client |

## The lanes

| lane | owned |
|---|---|
| A | the migration — the two columns, the copy-from-`default_measure` backfill, `ensure_onboarded`'s carry, pgTAP |
| B | the domain — `allowed_units.dart`, `unitSayableAsDefault`, `convert`, the shared vectors |
| C | the surfaces — the form's `PieceWeightEntry`, the quantity sheet, the recipe page's marker routing |
| D | the import — `line_validation.dart`, the review card, the commit |
| E | the docs and the design board |

## What it cost

- **Onion carries 110 g twice**, as its piece weight and as `onion, medium`.
  Two honest statements, the first sourced from the second and free to diverge.
- **"Ask me each time" is gone.** Broccoli takes `whole`'s weight as its piece;
  `spear` and `crown` stay measures. A count-default row weighs a piece or
  defaults to a mass or volume unit.
- **A legacy stranded state exists** on rows created before this landed: a
  `piece` default with no weight. It reads as the sibling of *needs a density*,
  and nothing can create a new one.
