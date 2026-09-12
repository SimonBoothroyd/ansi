# Exec plan: field test, round twelve — the basket, the slot as a field, a piece-weighted row bought in pieces

- **Status:** active — three lanes (`shop`, `week`, `docs`)
- **Owner:** agent
- **Roadmap step:** — (the first family week on `v0.15.0`)
- **Created:** 2026-09-12

## Goal

Four owner notes from the first week the household used the app in anger.
Sync held up on a patchy connection the whole week, which is why the
tracker's sync row narrows in this round; the notes are about the shop and
the week.

> *"We should move crossed off items on the shopping list to a new bottom
> section, so we can easily see what is and isn't grabbed yet."*

> *"There is no way to change what slot a meal is in, you have to remove and
> re-add. We also default always to dinner... instead we should default to
> the next unchosen slot of the day ordered chronologically if possible...
> fine if we for now limit to bfast, lunch, dinner, snack."*

> *"I want us to play a fun animation (co-design with me) when all shopping
> items are ticked off."*

> *"We still have some recipes using 'piece' when an appropriate measurement
> (e.g. lime) is available... which leads to annoying amounts in the
> shopping list (67g + 1½ piece) rather than n limes. Audit how this
> happened, and fix current cases at least."*

## Acceptance criteria

Lane `shop` — `features/shopping`:

- [ ] The aisles hold only unticked items; an aisle whose items are all
      ticked leaves the top of the list. Every ticked item sits in one
      section at the bottom, `IN THE BASKET · n`, in aisle order then name,
      looking exactly as a ticked row looks today. A tap unticks it and it
      returns to its aisle. Held in the domain (`ShoppingList.openGroups`,
      `basket`, `allTicked`), unit-tested, with screen tests for the move
      both ways.
- [ ] When every item is ticked the aisles' place says `everything's in the
      basket`, in the empty-list voice. That state is the one hook the
      celebration (below, co-design pending) will hang on.
- [ ] A `piece` line on a row that states a piece weight folds into the
      row's basis subtotal through that weight, exactly as a measure does
      (ADR-0015 rule 5, applied to the shop). A row with no piece weight is
      unchanged: an honest bare count.
- [ ] A row whose default unit is `piece` and that states a piece weight is
      **bought in pieces**: when everything folded to one basis total, the
      row's primary reads `2½ piece` (`≈` when a plain mass line or an
      uneven measure joined the fold) with the grams underneath and
      `→ buy 3` when fractional. `measureTotal` keeps its meaning; a new
      `pieceTotal` carries this one. Domain, format and screen tests.
- [ ] `IngredientMetaInput` carries the row's piece weight and basis; the
      repository reads them; the README's aggregation section states the
      rule; the Shop frames on the board show the basket and a piece row.

Lane `week` — `features/planning`:

- [ ] `kDefaultMealSlots` is Breakfast · Lunch · Dinner · Snack, and
      `defaultMealSlot(dayEntries)` is the first of them no meal on that day
      already uses (case-insensitive), `Dinner` when all four are taken. The
      add flow opens the picker and the confirm sheet on it. Unit-tested.
- [ ] The meal editor's first field is **Slot** — the shipped
      `MealSlotPicker`, writing through on change like its two neighbours
      (`PlanningRepository.setMealSlot`). The day is still position, moved
      by remove-and-re-add. Repository test on the real database; screen
      test that a change re-files the row under the new gutter label; the
      structural write tests stay green.
- [ ] The sentences that said "day · slot is not a field" — the editor's and
      the week view's library comments, the planning README — say the new
      rule; the board's meal-editor frame draws three fields.

Lane `docs` (this file):

- [ ] The audit below is ready for the owner to run read-only; its result
      decides whether any row needs a piece weight.
- [ ] The tracker's sync row is narrowed to what the field week did not
      verify; the backlog carries the celebration and the office-lunch idea.
- [ ] Tests cover the new logic; docs updated (feature READMEs, board, this
      plan, roadmap row).

## Approach

Three worktrees off `origin/main`, landed in the order shop → week → docs,
one `make analyze` + `make test` + `make docs-check` on the landed tree. The
lanes touch disjoint files (the shop and the week share nothing but
`viewedWeekStartProvider`, which neither changes).

1. **Shop.** Domain first — the basket getters and the piece fold are pure
   functions over `buildShoppingList`'s inputs — then the meta query, then
   the view (render `openGroups`, then the basket), then the format and the
   board.
2. **Week.** The slot list and the default rule in `planning.dart`; the
   `_addMealFlow` reads the day's entries before its first await and hands
   the slot to both sheets; the repository method; the editor's field; the
   comments and the frame.
3. **Docs.** This plan, the audit SQL, the tracker row, the backlog rows,
   the roadmap row.

## The lime, audited

**What the data says.** Lime's row is default `piece` with a piece weight of
67 g, borrowed from its one measure, `lime, whole` = 67 g. One recipe asks
for `1 lime, whole`; another asks for `1½ piece`. Both lines are honest and
weigh the same thing.

**How the two words got there.** The import's extraction prints count
produce as `piece` (`"1 red bell pepper" → unit="piece"`, and the
juice-or-fruit rule lands on `piece` when the zest is used too), and the
review admits `piece` on a weighed row without a flag — by design, ADR-0015
rule 4: nothing arrives on a measure, because what one of a thing weighs is
the row's property. A line typed by hand in the editor meets the chip row,
which offers `piece (67 g)` and `lime, whole (67 g)` side by side, and a
person reasonably picks the one with the fruit's name on it. So an imported
lime says `piece` and a hand-entered lime says `lime, whole`. Neither door
is wrong.

**Where it actually broke.** The shop's `aggregateQuantities` folds a
measure through its weight into the basis subtotal and sums `piece` as a
bare count — it never reads `piece_basis_amount`. The macro engine does
(`pieceMeasureOf`), which is why the recipe page's figures were right while
the shop printed `67 g + 1½ piece`. The fix is the shop reading the same
row fact, not a rewrite of either recipe's line; ADR-0015's consequence
"a weighed `piece` beside a size is not ambiguous" is exactly this case.

**What does need a look: `piece` lines on rows with no weight.** Those are
the stranded state ADR-0015 allowed to survive on pre-existing rows — a
bare count nothing can fold. The owner runs this read-only, linked to the
cloud (agents are permission-gated from `--linked` on purpose):

```sql
-- 1. Lines counted in `piece` on a row that states no piece weight.
--    These stay a bare count on the shop and print `needs a piece weight`
--    on the recipe page. The fix is one number on the row (the ingredient's
--    page → Edit), or re-pointing the line at a measure in the editor.
select r.title as recipe, i.canonical_name as ingredient,
       li.quantity, li.unit, i.default_unit,
       (select string_agg(m.label || ' = ' || m.basis_amount || ' ' || i.macros_basis,
                          ', ' order by m.sort_order)
          from ingredient_measure m
         where m.ingredient_id = i.id and m.deleted_at is null) as measures
  from recipe_line_item li
  join ingredient_group g on g.id = li.group_id
  join recipe r          on r.id = g.recipe_id
  join ingredient i      on i.id = li.ingredient_id
  join household h       on h.id = i.household_id
 where li.deleted_at is null and r.deleted_at is null and i.deleted_at is null
   and not h.is_template
   and li.unit = 'piece' and li.measure_id is null
   and i.piece_basis_amount is null
 order by i.canonical_name, r.title;

-- 2. The same, for a planned bare-ingredient meal (a snack in `piece`).
select wp.week_start_date, pe.day_of_week, pe.meal_slot,
       i.canonical_name as ingredient, pe.quantity, pe.unit, i.default_unit
  from plan_entry pe
  join week_plan wp on wp.id = pe.week_plan_id
  join ingredient i on i.id = pe.ingredient_id
  join household h  on h.id = i.household_id
 where pe.deleted_at is null and i.deleted_at is null
   and not h.is_template
   and pe.unit = 'piece' and pe.measure_id is null
   and i.piece_basis_amount is null
 order by wp.week_start_date desc, pe.day_of_week;

-- 3. Informational: rows asked for in `piece` by one recipe and in a measure
--    by another — the lime shape. After this round the shop sums them; the
--    list is here so the owner can see how common the two-words case is.
select i.canonical_name as ingredient, i.piece_basis_amount,
       count(*) filter (where li.unit = 'piece' and li.measure_id is null) as piece_lines,
       count(*) filter (where li.measure_id is not null)                  as measure_lines,
       string_agg(distinct r.title, ', ' order by r.title)                as recipes
  from recipe_line_item li
  join ingredient_group g on g.id = li.group_id
  join recipe r          on r.id = g.recipe_id
  join ingredient i      on i.id = li.ingredient_id
  join household h       on h.id = i.household_id
 where li.deleted_at is null and r.deleted_at is null and i.deleted_at is null
   and not h.is_template
 group by i.id, i.canonical_name, i.piece_basis_amount
having count(*) filter (where li.unit = 'piece' and li.measure_id is null) > 0
   and count(*) filter (where li.measure_id is not null) > 0
 order by i.canonical_name;
```

Queries 1 and 2 are the actionable ones; a hit is fixed in the app, never
by SQL (a piece weight typed on the row unions `piece` into
`allowed_units` in the same write, which a hand `UPDATE` would skip).

## Decision log

- 2026-09-12 — **The slot is a field of the meal editor.** Owner-ruled,
  reversing Week v3's E7 reading that a row's day · slot is position only.
  The slot IS printed — it is the group's gutter label — so it meets the
  rule "a row's controls are the facts the row prints". The day stays
  position: no day control, remove-and-re-add as before.
- 2026-09-12 — **The default slot is the first unfilled one, in meal order.**
  "The next unchosen slot of the day, ordered chronologically" is read as
  the first of Breakfast · Lunch · Dinner · Snack the day lacks — a day
  with only a dinner offers Breakfast next — not the slot after the latest
  one filled. All four taken falls back to Dinner, the old default. `Snack`
  joins the offered slots and ranks after Dinner.
- 2026-09-12 — **The basket is one section, not a per-aisle fold.** Ticked
  rows keep their aisle order so a row's position is predictable, and the
  header carries the count so "what is left" and "what is done" can both
  be read at a glance. No new gesture: a tap unticks, as it always did.
- 2026-09-12 — **The lime is a shop bug, not bad data.** The audit above:
  two honest words for one fruit, and a sum that read only one of them.
  Fixed by the shop spending the piece weight (ADR-0015 rule 5); a
  piece-default weighed row reads a count of pieces, `≈` when the fold was
  not a whole number of pieces per thing asked for. No line is rewritten.
  Nothing changes in the import: the extraction's `piece` for count produce
  and the review's refusal to arrive on a measure are both still right.
- 2026-09-12 — **The celebration waits for the owner.** The all-ticked
  state and its quiet line ship now, as the hook; the animation is drawn
  with him first (options under Notes).
- 2026-09-12 — **The sync tracker row narrows rather than retires.** A
  family week over a patchy connection is field evidence for the offline
  drain, not a test of it; the two-client session and the banner
  escalation stay unverified.

## Notes / open questions

**The celebration — three shapes to pick from, or mix:**

1. *The basket fills.* The `IN THE BASKET` header's count rolls up to the
   total, the section's rows settle with a short stagger, and one line of
   herb-green ink writes itself where the aisles were: `everything's in the
   basket — 14 of 14`. Quiet, on-brand (mono, muted → herb), no third-party
   package, about 600 ms. Recommended as the base layer.
2. *Confetti of the food itself.* A handful of small glyphs (the ingredient
   initials, or Lucide's `carrot` / `apple` / `wheat`) burst from the last
   ticked box and fall behind the list, drawn with a `CustomPainter` and
   one `AnimationController`. Louder, still in the app's two inks.
3. *The tick that ripples.* The last box's tick over-scales with a bounce,
   a ring expands from it and fades, and a light haptic fires. Smallest,
   and it happens under the thumb, where the eye already is.

Whichever is chosen, it plays once per list, only when the count crosses
from n−1 to n on this phone (never on the partner's tick arriving by sync),
and never on a list of one item.

**Meals eaten out (the office lunch) — the brainstorm, no build.** A
third kind of planned meal beside a recipe and a bare ingredient:

- *Model.* `plan_entry` gains a `label` (the words) and an optional
  per-portion `macros` jsonb; the entry XOR becomes three-way. It carries
  eaters and multiplies like any entry. Every derivation says what it does
  with the kind: the cook plan ignores it (nothing is cooked), the shop
  ignores it (nothing is bought), the week's macros weigh it from its
  stated figures and otherwise name the refusal in the row's own words —
  `Office lunch · macros not stated` — the same shape a stub ingredient
  already has.
- *UX.* The picker's one door gains a third answer when the typed words
  match nothing: `note it — "Office lunch" · not cooked, not bought`. The
  confirm sheet's shared questions stay (slot, eaters, portions) plus one
  optional fold: kcal · P · C · F per portion, on the existing macro
  keypad. On the week the row prints at a third weight (plain, italic
  `out` tag), no cook marker, its kcal chip when stated. Because it fills
  the slot, the new default-slot rule skips Lunch on office days.
- *DX.* `MealTarget` gets a third sealed case; `PlanEntry.isIngredient`
  becomes a `kind` enum so a null recipe can never again mean "skip". One
  migration (two nullable columns and the constraint), the seam test that
  every derivation branches on the kind, the copy-last-week carry.
- *Open.* Whether an office lunch recurs (a "weekdays" repeat on the
  confirm sheet, or copy-last-week is enough); whether a stated-macros
  meal should be a first-class vocabulary row instead ("Canteen chilli",
  reusable) — that is the ingredient kind with a `not bought` flag, which
  is one column but muddles what a vocabulary row is.

## Step-done checklist

- [ ] Roadmap row added under "On main, not yet tagged".
- [ ] `ARCHITECTURE.md`'s standing table still true for the shop and the
      week.
- [ ] `app/AGENTS.md` "Current focus" and command list still true.
- [ ] `make test-sim FILE=week` and the shop leg run on a booted simulator,
      the result recorded here — or the reason it was not.
- [ ] Tech-debt rows added for corners cut, retired for debt paid.
- [ ] No migrations, no seed change.
- [ ] `make ci` green.
