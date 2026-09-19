# ADR-0016 — A measure that weighs a piece is the row's word for one

- **Status:** accepted (2026-09-12, Simon — owner-ruled)
- **Amends:** [ADR-0015](./0015-piece-weight-is-a-row-fact.md) §Decision
  rule 4, where it reads "nothing arrives on a measure", and rule 2's leg
  "Nothing is named after the row … and no measure is pointed at by the row".
  Both now read as below. Everything else in ADR-0015 stands: the piece weight
  is the row fact that admits `piece`, the import enters no weight, a
  `piece` default with no weight is stranded and refuses Save, and the macro
  engine converts a `piece` line through the piece weight.

## Context

ADR-0015 gave a count one honest meaning — the row's piece weight — and, to
keep the review from deciding what a count *meant*, ruled that a counted line
never arrives on a measure. The first family week showed the cost. Lime's row
weighs a piece at 67 g, borrowed from its one measure, `lime, whole` = 67 g.
The import's extraction prints counted produce as `piece`, and the review
admitted it on the weighed row without a flag; a person typing the same lime
in the editor met a chip row offering `piece (67 g)` and `lime, whole (67 g)`
side by side and reasonably picked the one with the fruit's name on it. One
fruit, two words, and the shop summed only one of them.

The audit's first reading called that a shop bug and proposed a print rule.
The owner, on that draft:

> *"we're currently by default picking the 'worse quantity' on import that a
> human likely wouldn't pick if they had the choice between piece and lime.
> You're phrasing this as a presentation issue on just the shopping list,
> rather than a consistency and clarity issue."*

and, on what to do: *"change anything using piece in our recipes to the
proper measure where applicable"*, *"figure out what import should do"*.
The defect is at the doors, not the print: two doors hand out two words for
one thing, and the import's word is the one nobody would choose.

## Decision

**A measure that weighs what the row says a piece weighs is the row's word
for one, and every door says it.** Such a measure is the row's **whole
measure**, and it is *found*, never stored:

1. **One reading.** `wholeMeasureOf(ingredient, measures)`
   (`ingredients/domain/allowed_units.dart`) is the single place the question
   is answered: the live measure whose amount is within **1 %** of
   `piece_basis_amount`; when two qualify, the lowest `sort_order` wins, then
   the label; null when the row states no weight, when no measure weighs a
   piece, or when the only candidate merely names a volume unit. The seed's
   own rule is the same sentence: a size measure that weighs a piece is the
   row's word for one.
2. **The chip row leads with it and the sheet opens on it.** Wherever an
   amount is entered — the editor, the review's amount door, the snack sheet,
   the top-up sheet — the whole measure is the first chip and the choice a
   caller who names none opens on; `piece (67 g)` stays offered after it. A
   line being edited opens on its own stored choice.
3. **The review lands a counted line on it.** A printed `piece`, or a number
   with no unit word, on a row with a whole measure becomes that measure's
   label at the moment the match resolves — on arrival and on a re-match,
   which takes the machine's earlier word back before handing out the next —
   unflagged, exactly as if the person had tapped the chip, and committed to
   the same `measure_id`. A weighed row with no whole measure keeps `piece`;
   an unweighed row keeps the unsupported-unit gate; a unit somebody chose or
   a word the page printed is never overruled. The server's extraction still
   prints `piece`; the review decides.
4. **The shop's named-measure count rounds up** — `2½ lime, whole · 167.5 g
   → buy 3` — the shape the piece count already had.
5. **Existing lines are re-pointed once**, by the owner, after the app change
   ships: every `piece` line and planned snack on a row with a whole measure
   moves to that measure's id, so no phone sees a word its sheet cannot yet
   print. The SQL is in plan 0046.

The recipe page prints the measure's own words — `1 lime, whole` — and no
measure is renamed.

## Consequences

- **A row with a single measure opens on that measure, never on `piece`**
  (owner: *a named measure is almost always better than generic piece*). It
  needs no rule of its own — the chip order puts a row's own words in front of
  the whole catalogue, and a surface with nothing stored opens on the first
  chip offered (`firstOfferedChoice`) — but it is why that ordering is worth
  holding as one thing: whatever the household called the thing is a better
  answer than a count the app would then have to weigh.
- **What still says `piece`.** A row that weighs a piece but names no size —
  Avocado, Chicken thigh, a tin — has no whole measure, and every door still
  says `piece (201 g)`. The word does not leave the app; it stops being
  handed out where the household already has a better one.
- **ADR-0015's objection to a pointer holds.** Nothing is stored: the whole
  measure is two numbers agreeing, read the same on every device and in the
  server's SQL. Change the piece weight or the measure's amount and the
  reading changes with it, visibly, on the row that changed — a saved line
  keeps its `measure_id` either way, so nothing re-aims it.
- **Onion still carries 110 g twice**, and now one of the two is *read* off
  the other: `onion, medium` = 110 g on a 110 g piece is the row's word for
  one onion, so a counted onion arrives as `2 onion, medium`. The nuance
  ADR-0015 traded away — "which size did a piece mean?" — comes back as a
  household choice: a size that is *not* the piece weight (`onion, small`) is
  never picked for a line on its own.
- **A re-match can move a word the machine gave.** A line the review landed
  on `pepper, medium` and then re-pointed at Lime reads `lime, whole`, and at
  Avocado reads `piece` again. A word the person chose — `g`, `clove`, a size
  they tapped — moves with the line and is flagged there if the new row cannot
  say it, as before.
- **The landing is best-effort at the doors, never at the commit.** A local
  read that fails while a payload arrives leaves its lines as they were (a
  `piece` on a weighed row is valid and one chip from the word), and the same
  read failing is what the review's *Couldn't check the lines* says, with its
  retry. A billed extraction is never thrown away over a lookup.
- **The import gets no stricter.** Nothing that committed before stops
  committing; the only change is which word a counted line carries.

## Rejected alternatives

- **The shop print rule (model B).** Leave the doors alone and print a bare
  count on the shop as the recipe page already does — `2½`, with the grams
  and the round-up under it — so the word `piece` is never printed beside a
  name. Drawn, and rejected by the owner in the sentence above: it leaves the
  recipe page, the editor and the review saying `piece` where the household's
  own word exists, and a print rule on one screen is not consistency.
- **A stored pointer** — bring back `default_measure_id`, aimed at the whole
  measure. It is the column ADR-0015 retired, for a reason that has not
  changed: a pointer re-aimed later changes what a saved line means, needs an
  own-measure trigger, a soft-delete clear and a by-label carry, and states a
  fact the two numbers already state.
- **Renaming measures** — call the whole measure `piece`, or the row's own
  name, so the words agree by construction. The household named `lime, whole`
  and `onion, medium`; the app's job is to say those words, not to overwrite
  them, and a measure labelled after its row puts the name in two places.
- **Land on the whole measure at validation rather than at the match.** The
  validation seam is a derived, read-only view of the resolutions; writing a
  line's unit from inside it would make the Save gate depend on a side effect
  of its own computation. The match is the moment the row is known, so the
  match is where the word is handed out.
