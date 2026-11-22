# Exec plan: optional ingredients, chosen in the recipe

- **Status:** active (built; the `sim` dispatch is the gate to main, the
  owner's look on a phone closes it)
- **Owner:** agent
- **Roadmap step:** — (owner's ask)
- **Created:** 2026-11-22

## Goal

An optional ingredient is chosen on the recipe, where its use can be read, and
from then on is an ordinary ingredient of the week. Owner: *"how we enable
optional items on recipes on the foodplan is currently opaque and kinda
hidden"*.

## Acceptance criteria

- [x] *Add to plan* has one line into the recipe and no ticks. Done returns to
      it. The picks are written with Add, and a closed sheet writes none.
- [x] On a recipe page a week owns, each optional ingredient is an ordinary
      row in its own group that quotes the steps that use it, its `optional`
      pill the switch. (First built as a pooled OPTIONAL section of cards; the
      owner, on the web, found it stood out and moved the amount, so it was
      redrawn in place and approved.)
- [x] The method greys what was not picked, with no amount.
- [x] The Shop never says optional: a picked one is an ordinary line, an
      unpicked one is absent.
- [x] Copying last week copies the ticks, the Week's copy and Ask's alike.
- [x] A pick is no edit: not on the Week, Cook, the page or the meal's sheet.
- [x] Tests cover the new logic.
- [x] Docs updated: product spec, READMEs, the board, navigation.
- [ ] The owner has looked at it on the phone.
- [ ] `make test-sim`, or the `sim` dispatch, is green on this branch.

## Approach

1. `optionalChoices` (pure) reads a week's answer per ingredient, and
   `stepUsesOf` (pure) quotes its steps off the method's chips.
2. `OptionalInRecipeDoor` opens the page with `?choose=<day>`. `OptionalPicks`
   holds the answers until Add.
3. The row's `OptionalPick` is the page's switch, `OptionalReveal` its
   scroll. `copyOptionalTicksIn` runs inside the
   copy's transaction.

No migration.

## Decision log

- 2026-11-22 — **One choice per recipe per week, off by default** (owner:
  yes). No "usually yes".
- 2026-11-22 — **Chosen in the recipe, never on a planning sheet.** Two builds
  put ticks on the sheets and the owner turned both down: *"too far from the
  recipe? how will a user know HOW that optional thing is used at a glance"*.
  The four-step drawing that followed was approved (*"That looks much
  better!"*).
- 2026-11-22 — **The Shop never says optional** (owner: *"if user selects
  them, shop shouldn't flag them as 'optional' any more"*, and of the fold,
  *"the shop still says optional?"*). No fold, no note, no provenance segment.
- 2026-11-22 — **A copy carries the ticks** (owner: *"if a user copies a plan
  from last week it should include the optional ticks in what's copied"*).
  This amends plan 0043's D8 for ticks alone: edits are still left and named.
  A meal from a pot brings the ticks it was cooked with, and what the target
  week already says of a line stands.
- 2026-11-22 — **A pick is no edit.** Only swaps, amounts, additions and
  leave-outs count as *edited for this week*.
- 2026-11-22 — **A sub-recipe's page takes the week that cooks it.** The
  Shop's row was the only door to a sub-recipe's own optional lines, so the
  parent's chip and Cook's component title now carry the week.
- 2026-11-22 — **`setLineIncluded` reads inside its write.** Ticks made
  together used to overwrite each other.

## Notes / open questions

- A line no chip in the method names shows its note and no quote.
- A dish planned and never opened buys none of its optional ingredients.
- A meal moved to another week by Ask does not take its ticks along.
- A line with an amount of its own this week is ticked and inert on the page:
  that amount is changed in the week's editor.
- The week editor's footer still counts picks in what it would drop, because
  it does drop them.
