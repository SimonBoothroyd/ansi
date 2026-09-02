# ADR-0010 — `piece` is an admission fact, curated by hand

- **Status:** accepted (2026-09-02, Simon + agent — exec plan 0022
  `piece-curation`, owner-ruled)
- **Refines:** [ADR-0008](./0008-unit-admission-model.md) §4 (allowed units are
  an explicit per-ingredient attribute) and
  [ADR-0009](./0009-density-unlocks-both-families.md) — neither is reversed.
  ADR-0009's rule 3 (a backfill unions, never removes) and its D4b removal leg
  both stand; this ADR adds the second, and only other, removal leg.

## Context

A field-test import of an avocado kale salad committed "1 large ripe avocado"
as a bare `piece` with no measure linked, so the macro engine honestly excluded
the line — while the household's vocabulary held an `avocado` measure at 201 g
the whole time. Garlic worked in the same import only by accident: extraction
emits the token `clove`, which happens to string-match the measure's label.

The first design answered with a **runtime resolution cascade** — read the size
word out of the raw line ("1 **large**" → the large measure), fall back to
`medium` when unsized, auto-link a sole measure at commit, mark the result
`inferred` with a revert affordance. The owner rejected it as drawn:

> *"if a suitable alternative exists e.g. clove, medium, etc that is MUCH
> clearer than piece and piece should not be available in those cases,
> otherwise we have to arbitrarily guess what piece means (is it a clove, is it
> medium?). Piece is the fallback when no appropriate measure is available.
> **This isn't rule-based.** we need to manually decide for seeded, and then
> the user needs to decide for new ingredients."*

Every layer of the cascade was the machine deciding what a `piece` meant, and
each added another place to be confidently wrong.

## Decision

**`piece` means "a whole one of these, and we have nothing better to call it".
Where an ingredient carries an appropriate piece-type measure, `piece` is not
in its `allowed_units` and is never offered.**

It is an **admission fact** in the explicit list ADR-0008 §4 already
established — no new column, no runtime cascade, no size-word guessing, no
`inferred` mark, no auto-link. Nothing downstream ever has to decide what a
`piece` meant, because on those rows a `piece` cannot be said in the first
place.

Four consequences follow directly, and no new machinery is needed for any:

1. **The derived default is unchanged.** `default_allowed_units()` (migration
   0012/0014) and its `defaultAllowedUnitSet` Dart mirror still give a count
   row `piece`, and must: a row with no measures has nothing clearer to say,
   and the default function has no business knowing the measure table.
2. **The seeded vocabulary is curated by hand.** All 142 seeded ingredients
   that carry a measure were read and ruled on row by row, and each landed as
   one `{"kind": "allowed_units", …, "remove": ["piece"]}` line, with its
   reason, in `supabase/seed/curation_overrides.jsonl` — the committed file
   that already holds this class of non-derivable per-row override (ADR-0009
   rule 2). Rollout is a **reseed**, never a migration.
3. **A household decides its own rows, once, when the answer is obvious.** The
   measures editor asks on the row's FIRST piece-type measure — "You added
   'clove'. Still offer 'piece' for Garlic?" — defaulting to removing it. The
   flesh-out form's admission chips are where anyone changes their mind, in
   either direction, forever.
4. **An arriving `piece` on such a row is an ordinary not-allowed unit.** The
   import review flags `unitNotAllowed`, shows the row's measures as
   did-you-mean chips, and gates Save. One measure pre-selects (there is
   nothing else the line could have meant); **two or more pre-select nothing**
   and the user picks.

**A stored line is never rewritten.** A line already saying a bare `piece` on a
now-measured row keeps saying it, offered last and marked "not in filter" — the
same call ADR-0009 made for a `cup` line whose density was deleted. The macro
panel names it as "1 line needs a weight" rather than folding it into
"unconvertible": nothing failed to convert, nothing was ever weighed.

## Consequences

- **The seeded template admits `piece` nowhere.** Every one of its 76
  count-default rows turned out to carry a measure, so after the pass the
  fallback exists only for ingredients a household creates itself. That is the
  ruling landing, not an accident, and a pgTAP assertion pins it
  (`supabase/tests/unit_admission.sql`) so a regenerated seed cannot quietly
  put it back.
- **Counted produce now asks for a tap it used to skip.** "1 avocado" is
  flagged where it used to pass silently. This is the cost, and it is the
  honest one: the line's macros were being dropped either way, and now the
  screen says so at the moment it can be fixed.
- **A second removal leg exists in the admission model**, beside ADR-0009's
  density deletion: the household's answer to the add-a-measure question. Both
  are user acts on a user-owned list. Neither is a backfill, and ADR-0009 rule
  3 still forbids a backfill from removing anything.
- **The curation file is the decision record.** A future reader can see, per
  row, why `piece` came out — and revise it. A rule would have to be re-derived
  (and re-argued) every time the USDA generator relabels a portion.

## Rejected alternatives

- *A runtime resolution cascade* (size-word matching from `raw_amount`, a
  `medium` tie-break, auto-linking a sole measure at commit, an `inferred`
  mark) — the owner's rejection above. "We would be guessing."
- *Derive it at seed time* ("drop `piece` wherever a self-named measure
  exists") — the same cascade wearing a seed-time hat. It would put `piece`
  back on broccoli (whose `spear` and `crown` are not "a broccoli") and take it
  off ginger, and it would re-decide the whole list on every generator run.
- *A new per-ingredient column for "count style"* — a second stored copy of a
  fact `allowed_units` already holds, which is what ADR-0008 spends its length
  refusing for density.
- *Demote `piece` below the measures but keep offering it* — the first draft's
  answer. An offered `piece` beside a `clove` is an invitation to store the
  ambiguous one.
- *Remove `piece` silently when a measure is added* — right direction, wrong
  manners. `allowed_units` is user-owned from creation (ADR-0008 §4); taking an
  admission away without saying so is the same class of move as rewriting a
  stored line.
- *Ask nothing and let people curate in the flesh-out form* — technically
  sufficient, realistically never done. The add-a-measure moment is the only
  moment the answer is obvious.
