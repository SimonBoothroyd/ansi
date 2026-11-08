# Exec plan: Leftovers — fridge and freezer

- **Status:** active — phases 1–5 built; phases 1–2 ship in a release before 3–5; not yet tagged
- **Owner:** Simon (design and rulings), agents in lanes
- **Roadmap step:** 11 (anti-waste); replaces part of [plan 0059](./0059-use-it-up.md)
- **Created:** 2026-11-07

## Goal

The household can see and correct what cooked food is in the fridge and
the freezer, from one page, whenever they happen to look. Nothing has to
be said on a particular day. A frozen dish is offered when you plan,
including the week after it was cooked, and is not cooked or bought
again.

Today, planning on a Saturday for the week ahead:

- a batch's leftover drops off once its fridge use-by passes, and the
  freezer is never part of it, so a frozen Hamburger Helper is never
  offered next week and is bought and cooked again;
- the count is planned portions less ticks, and cannot be corrected;
- leftovers are visible only inside the picker, one slot at a time;
- Cook asks *Binned · We ate it* only after the use-by, when freezing is
  already too late.

## Rulings

Taken with the owner on 2026-11-07, against the canvas
[Leftovers](https://claude.ai/artifact/QJ3jfdFmcjvwJ2geM242By). The
canvas is the source for the board frames.

- **One page: Leftovers**, two sections, **Fridge** and **Freezer**. Each
  row: the dish, its portions, and its date: `until Sun` in the fridge,
  its age (`2 wk`) in the freezer.
- **One door**: a fridge icon in the Week header, where the Shop has
  Receipts, beside Ask and drawn at Ask's size and weight. A dot on it
  when any row is past its date. No line on the Week's foot, no tab.
- **On the Week, a meal from either shelf reads `leftover`**, where a
  cook marker would be: the fridge's tag colours, or the freezer's blue.
  Nothing else on the row (it replaces `leftover · not cooked again`).
- **Nothing clears itself.** A row past its date reads `past its date`
  and stays until someone taps it. Fridge rows offer **Froze it** (a
  freezable recipe only) and **Gone**; freezer rows offer **Gone**. The
  Fridge heading carries **Clear all**, which marks every past-its-date
  fridge row gone.
- **A fridge row starts from the ticks** (plan 0059's derivation: planned
  portions less what was ticked, less meals planned from it) and is
  corrected with a stepper on the row. A correction wins from then on.
- **Freeze** moves a fridge row to the freezer, dated today. **Froze it**
  on a past-its-date row dates it at its fridge use-by, the latest it can
  have gone in.
- **＋ in the page's bar** opens *Add a leftover*: a recipe or the
  household's own words, Fridge or Freezer, portions, and when (*This
  week · Last week · Earlier*). It covers food the app never saw: a pot
  cooked unplanned, a batch frozen without a word, food given to you.
- **A row's date**: in the fridge, its cook day plus the recipe's
  `keeps_for_days`; in the freezer, the day it went in plus
  `freezer_days` (null = no limit). A row in words has no date, only its
  age, and is never past its date.
- **Freezing extra on purpose needs nothing new.** Raise a meal's
  portions; the batch is cooked and bought at that size, and the spare
  is a fridge row to freeze.
- **The picker's *Use up* lists both shelves**, fridge first, then
  freezer, above *Uses last week's shop*. A fridge row is offered only for
  a day on or before its date; a freezer row for any day.
- **Planning a dish that is in the freezer asks once**, on the confirm
  sheet: **Frozen (2 left) · Cook fresh**, Frozen first. Frozen is a
  meal from that row: not cooked, bought or costed again, and portions
  capped at what is left.
- **Cook stops asking.** The leftover question and the `FROM LAST WEEK`
  card go; a batch's card keeps its one line (`1 portion left · until
  Fri`) and it opens Leftovers. The Week band's `binned · left` line goes.
- **Words stay short**: `1¾ · until Mon`, `2 · 2 wk`, `past its date`.
  No captions explaining the page.

### Rejected

- **A fifth tab**, and **a shelf of leftovers on the Week**. One page
  behind one icon.
- **A fridge row that clears itself at its use-by.** The household does
  not look on the day; a row that vanishes is food the app forgot.
- **A *Maybe in the freezer?* section of suggestions.** A past-its-date
  row with **Froze it** does the same job in place.
- **A question on the day** (*Keep · Freeze* on *Had instead*, *Froze
  it* on the last fridge day). Every answer can be given late, on the
  page.
- **A history of what was binned or eaten.** It invites a waste-tracking
  app.
- **Raw food in the freezer** (the tofu from a meal never cooked). Spare
  ingredients stay plan 0059's untracked suggestion.

## Approach

Phases land in order. Phase 2 ships in a release on its own before the
writers in phases 3–5, so a phone on an older build never cooks or buys a
meal planned from the freezer.

### Phase 0 — the board

1. Frames as `proposed`: a new `leftovers.html` (the page, the page a
   month later, *Add a leftover*); the header door in `week.html`; *Use
   up* with both shelves and the *Frozen · Cook fresh* confirm in
   `recipe-picker-confirm.html`. A status row in `index.html`.

### Phase 1 — the stored row

2. **Migration `0060_leftover.sql`:** a `leftover` table — `household_id`,
   `place` (`fridge` | `freezer`), exactly one of `recipe_id` or `label`,
   `portions` (numeric, ≥ 0), `since` (date: cooked or frozen), `batch`
   (the batch key a derived row came from, null for one added by hand),
   `gone_at`, the usual timestamps and `deleted_at`. RLS by household, as
   `batch_leftover`. No unique index: offline duplicates resolve on read,
   newest `updated_at` per `batch` canonical.
3. **`plan_entry.from_leftover uuid null references leftover(id)`**, on a
   recipe entry only. `leftover_of` stays and is still read, for meals
   planned from a derived fridge row before this plan.
4. Both PowerSync stream files and the local schema; `db-schema.md`.

### Phase 2 — readers (ships first)

5. **One choke point, as for `leftover_of`:** the cook plan, the shop and
   the week's cost pass over an entry with `from_leftover`; macros, ticks
   and Health Connect count it. A test per derivation.
6. **One seam (`cook_plan/domain/leftovers.dart`, pure):** the household's
   leftovers are the cooked batches of the last four weeks (derived)
   merged with the stored rows: a stored row with a `batch` replaces that
   batch's derived row; a row is shown until `gone_at`. Each row's
   portions fall by the meals planned from it (`leftover_of` or
   `from_leftover`). `pastItsDate(today)`. A batch with an old
   `batch_leftover` answer (binned or eaten) reads as gone. Tests on the
   cook plan's fixtures: a correction, a freeze, a late *Froze it*, words
   with no date, two batches of one dish.

### Phase 3 — the page

7. The Week header's fridge icon and its dot (phone and wide); the
   Leftovers page; a row's stepper, **Freeze**, **Froze it**, **Gone**,
   **Clear all**; *Add a leftover*. A first touch on a derived row writes
   its stored row.

### Phase 4 — planning

8. *Use up* lists both shelves; a pick of either opens the confirm sheet's
   leftover card (plan 0059's, capped at what is left), writing
   `from_leftover` (a derived row is stored first).
9. The confirm sheet's **Frozen · Cook fresh** when a recipe picked from
   Recent, Books or Favorites has a freezer row.

### Phase 5 — retire the question

10. Remove Cook's leftover question, the `FROM LAST WEEK` card, the wide
    schedule sheet's question and the Week band's leftover line. The
    batch card's line opens Leftovers. `batch_leftover` takes no new
    writes and is not dropped.

## Acceptance criteria

- [ ] A frozen dish is offered in the picker the week after it was
      cooked, and a meal from it is in nobody's cook plan, shop or week
      cost (one test per derivation).
- [ ] A fridge row past its date stays until Gone, Froze it or Clear all.
- [ ] A corrected count survives later ticks and is what the picker
      offers.
- [ ] *Add a leftover* writes a row in words or for a recipe, in either
      place, dated by the chip.
- [ ] Planning a recipe that has a freezer row asks Frozen or Cook fresh;
      Frozen cannot take more than is left.
- [ ] Cook asks nothing; the header dot shows only while a row is past its
      date.
- [ ] Phase 2 shipped in a release before the writers.
- [ ] Tests cover the seam, the choke point and the migration (pgTAP).
- [ ] Docs updated: product spec (*Batch cook plan*, *Meal plan*, the
      picker, a *Leftovers* section), `db-schema.md`, the board frames from
      proposed to built, `ARCHITECTURE.md`'s standing table, plan 0059's
      decision log (its question and fridge-only leftovers replaced here).

## Decision log

Append-only.

- 2026-11-07 — Plan written from the design rounds above. It replaces
  three of plan 0059's rulings: Cook's question, a leftover offered only
  until its fridge use-by, and fridge leftovers only.
- 2026-11-07 — Phases 1–2 built (the readers' lane). Decided in the lane:
  - A stored row's `portions` are **before** the meals planned from it
    (`from_leftover`), which come off on read. The stepper (phase 3) stores
    the count it is set to plus what is planned from the row.
  - A stored row with a `batch` replaces the derived row **even when gone**,
    and wins over an old `batch_leftover` answer (answers apply to derived
    rows only). Duplicates per batch: newest `updated_at`, ties by id; meals
    planned from a losing duplicate still come off the winner.
  - A stored **fridge** row for a recipe with no `keeps_for_days` has **no
    date** (never past its date); derived rows keep `useByOf`, whose unknown
    fridge life is the last meal's day. Owner may want them to agree.
  - A row with nothing left (meals planned from it ≥ its portions) is not
    shown, as for derived rows; a stored row whose recipe is deleted is not
    shown either.
  - The horizon is by **cook day**: a derived batch cooked more than 28 days
    before today is not read (`kLeftoverHorizon`); `leftoverWeekStarts`
    names the five weeks a reader loads.
  - A move (Ask's `PlanMove`) now keeps `leftover_of` and `from_leftover`;
    it had been dropping `leftover_of`, re-cooking the meal.
  - No repository read for the seam yet: nothing in this build would call it
    (the picker keeps `batchLeftovers`). The page's lane adds the watch, and
    a dropped-write subject for the `leftover` table with its first write.

- 2026-11-07 — Phases 3–5 built (the writers' lane). Decided in the lane:
  - **A pick from *Use up* keeps `leftover_of` for a batch nobody has
    touched** and writes `from_leftover` for a stored row. Storing the
    derived row first would split one tap across two repositories; the seam
    already reads both pointers. A meal planned from a derived batch does
    not come off a stored row that later replaces it (the seam's rule).
  - **Frozen · Cook fresh** offers the **oldest** freezer row of the dish
    (the seam's order), capped at that row, not the dish's freezer rows
    summed.
  - **A row prints the meals still to come from it**: `2 · 2 planned`
    (`Leftover.planned`, from the seam). The count is what is left to plan,
    which is what the stepper sets; without the planned part a household
    counting the box would over-correct. The board's `4 · 2 planned` is
    redrawn as `2 · 2 planned`.
  - **The stepper steps whole portions**; a part portion steps to the whole
    on either side (`1¾` → `1` or `2`) and it never reaches nothing (that is
    Gone).
  - **Freeze and Froze it** are offered on a freezable recipe's row and on a
    row in words (the household knows its own food); never on a recipe
    marked not freezable.
  - ***Add a leftover*'s When chips** date the row today, 7 and 14 days
    back. Portions start at 2.
  - **A row in words is not offered in *Use up***: a meal names a recipe.
  - **A freezer row past its `freezer_days`** reads `past its date` and is
    still offered in *Use up* (the ruling: a freezer row for any day);
    **Clear all** clears the fridge only.
  - **The Leftovers read** loads five weeks' meal batches without their
    sub-recipes (`loadCookPlan(components: false)`) on any change to a plan,
    a tick, a recipe, a stored row or an old answer.
  - **The confirm sheet now settles its eaters before reading them**, so the
    leftover cap holds on the sheet's first frame; it had let one Add through
    over the cap.
  - **Retired with their callers:** the cook-plan repository's answers,
    batch-leftover reads and `setLeftover`; `BatchLeftover.isGoodOn` and
    `isDueOn`; `batchLeftovers`' `answers` (the seam reads old answers as
    gone itself); the Week band's leftover line.
  - Not run: `make test-sim` (no simulator in this lane) and `make ci-full`
    (no schema change here).

## Notes / open questions

- **The four-week horizon** for derived batches bounds the read; an
  untouched batch older than that is not shown. Whether that is long
  enough is the owner's call after a month of use.
- ***Had instead* offering freezer rows** (a takeaway night becomes the
  chili from October) is plan 0054's open question; not in this plan.
- **Ask Ansi** reading Leftovers is its own follow-up.

## Step-done checklist

The code landing is not the step landing. Tick these before setting Status to
done and moving this file to `completed/`.

- [ ] Roadmap row updated: status flipped, one line on what shipped and what was
      deliberately deferred.
- [ ] `ARCHITECTURE.md`'s standing table matches reality for every area touched.
- [ ] `app/AGENTS.md` "Current focus" and command list still true.
- [ ] Feature steps: `make test-sim` run on a booted simulator (the UI paths CI
      can't reach), and the result recorded here.
- [ ] Tech-debt rows **added** for corners knowingly cut, and **retired** (or
      narrowed) for debt this step paid off.
- [ ] New migrations or seed changes? Say in the roadmap row whether they have
      reached **cloud** yet, and append a `docs/cloud-setup.md` ledger entry
      when they do. A "pending cloud push" note nobody clears becomes a false
      claim the moment the push happens.
- [ ] `make ci` green.
