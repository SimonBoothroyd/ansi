# Exec plan: Leftovers by the ticks

- **Status:** built — phases 1–4 on 2026-11-08, unreleased; `make test-sim` and the release owed
- **Owner:** Simon (design and rulings), agents in lanes
- **Roadmap step:** 11 (anti-waste); follows [plan 0060](./0060-leftovers-fridge-and-freezer.md)
- **Created:** 2026-11-08

## Goal

When a dish was cooked, what's left of it, and what you can plan from it
all follow from one rule the household can say out loud: **no tick means
you didn't eat it.** Ticks can come late and in any order. A dish that
freezes is cooked once for two weeks and bought once. Every count can be
put right on the Leftovers page, at any time.

Today (`v0.39.0`):

- a batch's cook day is its first *planned* day, so a skipped Wednesday
  still dates Hamburger Helper from Wednesday;
- a fridge row's date stretches to the batch's last planned meal, however
  far past the recipe's fridge life that is;
- nothing is shared across the week edge: a freezable dish planned for
  Saturday and the next Thursday is cooked and bought twice;
- the picker offers a fridge row only while it is still in date, so a
  dish that would keep if frozen is never offered for next week.

## Rulings

Taken with the owner on 2026-11-08, against two pages:
[How Ansi counts leftovers](https://claude.ai/artifact/PxrGsCTzmApxDsE59GRf8B)
(the rules, as decision trees) and
[Leftovers, the screens](https://claude.ai/artifact/PFLqQXPNZm3JEqWNhMUsrA)
(the five changed screens, board style). The screens page is the source
for the board frames.

### Counting

- **No tick means you didn't eat it.** Each person ticks *Ate this* for
  themselves, as today. *Something else* counts the same as no tick for
  leftovers. There is no "not ticked" flag.
- **The cook day is the earliest calendar day anyone ticked** a meal from
  the batch. Tick order is irrelevant; an untick works it out again. There
  is no *Cooked on* override.
- **A batch nobody has ticked** is not cooked yet while any of its meals
  is still to come. Its cook day reads as its next meal (`Cook Fri`). Once
  all its days are over it was never cooked, and nothing is left over.
- **Made is what was planned and bought for**, even when a meal is
  skipped. A tick takes out that person's portion size.
- **What's left** = made, less ticked portions, less meals planned from
  it, as set on the page.

### Dates

- **Good till the cook day plus the recipe's fridge days, that day
  included** (`till Mon`). It does not stretch to cover later meals; a
  meal planned past it gets a warning instead. **A recipe with no fridge
  life is taken to keep one week**, derived and stored rows alike.
- **Freezer dates count from the cook day**, for *Freeze*, *Froze it* and
  a *freeze by* pick alike.
- **A row past its date** stays listed so it can be seen and corrected,
  and is never offered in the picker, from either shelf. A freezable one
  offers **Froze it** (*I froze it on the night and didn't say*).

### Planning

- **The picker judges freshness on the day of the meal being planned**,
  not today.
- **Freeze by.** When a fridge row will be past its date by then but the
  dish freezes and would be in date frozen, it is offered under Freezer as
  `2 left · ❄ freeze by Mon`. Picking it plans the meal from the row and
  **assumes the freeze is done**. Until Mon the Leftovers row reads
  `freeze by Mon for Wed`. After Mon those portions are in the freezer,
  dated from the cook day.
- **A dish that freezes shares one cooking across the week edge.** If one
  whole recipe covers Saturday this week and Thursday next week (within
  its freezer life), Saturday cooks it all (`freeze 2 by Tue for Thu`) and
  it is bought once. If Saturday is never ticked, the next meal becomes the
  cook day and nothing is bought again.
- **The `leftover` tag** goes on every meal eaten from already-cooked
  food, whether planned up front or picked later. It is green from the
  fridge, blue with a snowflake from the freezer.
- **Warnings, never edits.** A leftover meal that no longer adds up keeps
  its tag colour and adds `not enough left` or `past its date` in amber.
  The app never changes the plan.

### The screens

- **Leftovers page**:
  - Rows go soonest to go off first, past-date rows last.
  - Counts are tappable `N left` chips that open the stepper. Later ticks
    still come off a set count, and a count never goes below 0.
  - A row says what is planned from it (`1 left · for Sun`,
    `❄ freeze by Mon for Wed`).
  - **Freeze** sits on in-date rows of a dish that freezes; **Froze it**
    on past-date ones. **Gone** goes: set the count to 0.
  - **Clear all** becomes **Remove gone off**, and clears past-date rows
    from both the Fridge and the Freezer.
- **Cook**: a check marks a cooked batch (`✓ Cooked Fri`). `×1` shows only
  when the scale isn't 1. One line says what's left (`2 left · freeze by
  Mon for Wed`). The day strip stays as it is.
- **Picker**: the section is called **Leftovers** (was *Use up*), Fridge
  then Freezer, soonest to go off first, and an empty subhead hides. The
  `frozen` chip goes.
- **Snowflake**: an icon on freezer subheads and blue tags, never before a
  dish's name.
- **A meal's sheet** offers **Cook fresh instead** before the meal's day,
  and *Ate this* / *Something else* from its day on, never together.
  **Cook fresh instead** puts the meal on the shopping list and frees its
  portions.
- **Kept**: the Week's `−`, the bare `＋` on Leftovers, the eater avatars,
  and the fridge icon's dot while anything is past its date.

### Rejected

- **Silence means you ate it** (assume the plan). The owner's rule is the
  opposite. An app that assumes meals were eaten under-counts the fridge
  invisibly.
- **A *Cooked on* date, a "not ticked" flag, or *Something else* meaning
  something for leftovers.** Each is one more word to learn.
- **"We both ate" ticking.** Each person ticks for themselves.
- **A thaw reminder** (`take out Tue`), and `freeze by` on the Week's
  tag. The freeze lives on the Leftovers row and the meal sheet.
- **One list in the picker ordered across both shelves.** Fridge then
  Freezer stays.

## Approach

There is no migration. Every change is in derivation and screens, so it
ships as **one release**. Both phones need it together: an older build
would plan and buy next week's share of a cross-week cooking again.

### Phase 0 — the board

1. The screens page's five frames as `proposed`:
   - Cook and the Shop's page: `cook-shop.html`;
   - the Week's tags and warnings: `week.html`;
   - the picker's Leftovers: `recipe-picker-confirm.html`;
   - the Leftovers page: `leftovers.html`;
   - the leftover meal's sheet: `week.html`.

   Add a status row in `index.html`, and redraw 0060's frames that these
   replace.

### Phase 1 — the cook day and the date (pure)

2. **`cook_plan/domain`:**
   - The cook day of a cooked batch is the earliest day with an eaten
     portion. A batch with no tick takes the first of its meals not
     yet behind us; once every meal is behind us it has no cook day.
   - `useByOf` becomes the cook day plus `keeps_for_days`, with no
     stretch to the last meal.
   - Freezer dating comes from the cook day.
   - The seam (`leftovers.dart`) reads all of the above.
3. **Warnings:** `Leftover`/`PlanEntry` reads give each meal planned from a
   row `notEnoughLeft` or `pastItsDate` for its own day.
4. **Tests** on the cook plan's fixtures:
   - ticks in reverse order;
   - an untick that moves the cook day;
   - a batch nobody ticked, before and after its days;
   - a skipped first meal (Wednesday's walnut pasta);
   - a short or past-date meal planned from a row.

### Phase 2 — one cooking across the week edge

5. **Clustering** for a freezable recipe reads the next week's meals of the
   same recipe. One that falls within `freezer_days` of the cook day and
   is covered by one whole recipe folds in as a frozen share of this
   week's batch.
6. **The choke point:** next week's cook plan, shop and week cost pass
   over a meal folded into the week before. If the batch is never ticked,
   the folded meal becomes its cook day, still with nothing bought.
7. **Cook** writes `freeze 2 by Tue for Thu`. Next week's meal reads as a
   blue `leftover`.
8. **Tests:** the fold, the uncovered case (two cooks), the never-ticked
   Saturday, and the shop of both weeks.

### Phase 3 — planning

9. **The picker** judges each row on the target day. The `freeze by` row
   (under Freezer) plans the meal from the row: `leftover_of` for an
   untouched batch, `from_leftover` for a stored row, as today. A row
   whose portions are all planned past its fridge date reads as frozen
   from then on.
10. **The Week** puts `leftover` on every meal eaten from a cooked batch,
    replacing `from Mon` once its batch is cooked, with the amber
    warnings of step 3.

### Phase 4 — the screens

11. **Leftovers page:**
    - sort, `N left` chips, what's planned from a row, `freeze by … for …`;
    - **Freeze** back on in-date freezable rows; **Gone** removed;
    - **Remove gone off**.
12. **Cook:** the check, `×1` hidden at 1, and the one line.
13. **Picker:** Leftovers, the snowflake subhead, no `frozen` chip, and
    empty subheads hidden.
14. **The meal sheet:** Cook fresh instead before its day only.
15. **The snowflake** icon (`FLucideIcons.snowflake`) on freezer subheads
    and blue tags.

## Acceptance criteria

- [ ] Ticking Sat, then Fri, then unticking Fri gives cook day Sat. Ticking
      in any order gives the same counts.
- [ ] A batch with Wednesday unticked and Friday ticked is cooked Fri, good
      till Mon, and Wednesday's portions are left.
- [ ] A batch nobody ticked shows nothing left once its days are over.
- [ ] A fridge row's date never stretches past cook day + fridge days. A
      meal planned past it warns `past its date`.
- [ ] Planning next Wed on Saturday offers a freezable dish good till Mon
      as `freeze by Mon`, and the row reads `freeze by Mon for Wed` until
      Mon.
- [ ] A freezable dish planned Sat and next Thu is cooked and bought once.
      If Sat is never ticked, Thu cooks it with nothing re-bought.
- [ ] Past-date rows are never offered, from either shelf.
- [ ] The app never edits the plan: shortages only warn.
- [ ] Tests cover the cook day, the date, the fold, the warnings and the
      picker's day.
- [ ] Docs updated: the product spec (*Batch cook plan*, *Meal plan*, the
      picker, *Leftovers*), `cook_plan/README.md`, the board frames from
      proposed to built, and `ARCHITECTURE.md`'s standing table.
- [ ] `make test-sim` green, with a smoke file that ticks out of order.

## Decision log

Append-only.

- 2026-11-08 — Plan written. The rules came from three rounds of design
  with the owner. In each round a fresh subagent played the owner and
  pushed back, and fresh cold readers took a scenario quiz on the drawn
  page. The owner ruled every assumption interactively.

  These change plan 0060's lane decisions:
  - `Freeze` dates from the cook day, not today.
  - A freezer row past its date is no longer offered.
  - **Gone** is gone.
  - **Clear all** is **Remove gone off**, and it clears the freezer too.
  - The fridge date no longer stretches to the last meal.
  - A recipe with no fridge life keeps one week. Before, a derived row was
    dated to its last meal, and a stored row had no date.

- 2026-11-08 — Phases 1–3 built (one lane). Decided in the lane:
  - **"Covered by one whole recipe"** is: the batch's planned portions plus
    the folded meals' are at most the recipe's `servings_base`, a scale of ×1
    or less. Only the week's last batch of a freezable dish folds, taking the
    next week's meals in day order while each is within `freezer_days` of the
    batch's planned cook day, and stopping at the first that fails either
    test. A meal within the fridge window folds as a fridge share.
  - **A fold never chains.** A dish the week before also plans folds nothing
    forward, so each week is read from two weeks back and one ahead. A dish
    planned every week is cooked every week, as before.
  - **One choke point:** the cook plan and the shop read the week's meals
    through one loader (`loadPlannedWeek`), which drops a meal the week before
    cooks and adds the next week's folded meals. The shop no longer has its
    own query, so the seam's structural test now expects one clause, not two.
  - **The week's cost** passes over a folded meal in the week it is eaten and
    adds its share to the week that buys it, at its portions (household view
    only; under a lens it is next week's meal).
  - **A cooked batch's later meals are on its derived row as spoken for**
    (`planned`), so Friday night reads 2 left beside 2 for Saturday, as the
    rules page draws it. A stored row (a correction) does not carry them;
    how later ticks come off a set count is phase 4's.
  - **A row shows while it has portions left or meals still to come.** That is
    what lets `freeze by Mon for Wed` show with nothing else left. The picker
    never offers a row with nothing left.
  - **A batch not cooked yet** with a skipped meal behind it is a row dated
    from its next meal: the picker offers it from then (*not cooked yet? it
    judges from its next meal*). The Leftovers page and Cook's line hide it
    until its cook day.
  - **The assumed freeze moves the whole row.** Once the fridge date is behind
    us, a row with any meal from it past that date reads as a freezer row,
    dated from the cook day. The rest of the box is taken to have gone in too.
  - **Warnings, in day order.** Each meal from a row takes its portions from
    what is left. The first that asks more, and every one after, reads
    `notEnoughLeft`, as does a meal before the cook day and a meal from a row
    gone or never cooked. A day past every date the row can reach reads
    `pastItsDate`. A batch's own later meals warn only `pastItsDate`.
  - **Freeze and Froze it keep `since`**, the cook day; the repository's
    `since` argument is gone. Freezer rows stored before keep the date they
    were given.
  - **The Week** reads the cook day by the ticks. A meal before it shows no
    marker, and a later meal of a cooked batch wears `leftover`, blue past the
    fridge date. A meal the week before cooks wears `leftover` from the start
    (blue past the fridge date), unless it has become that batch's cook day
    (`cooks Thu · batch of 4`). A never-cooked past week keeps its planned
    markers.
  - **Cook's batch line** reads `freeze 2 by Tue for Thu` until the freeze is
    due, for an in-week freezer share too, then the row's line as before. The
    final copy is phase 4's.
  - **The confirm sheet's Frozen · Cook fresh** offers a freezer row only when
    it is in date on the meal's day.
  - **Not done here:** phase 4, the board, the product spec, `ARCHITECTURE.md`,
    and `make test-sim` (no simulator in this lane).

- 2026-11-08 — Phase 4 built (one lane): the screens, the board flipped to
  built, the product spec, `ARCHITECTURE.md` and the READMEs. Decided in the lane:
  - **A count set by hand keeps taking ticks, by day.** A stored row's
    `portions` are the box as said plus what comes off it on read
    (`Leftover.aside`): the planned meals already behind us and the ticks
    already on the batch's meals from today on. The batch's meals after its
    cook day and on or after the day the count was set (`updated_at`, local)
    ride on the row: still to come they are spoken for, a tick takes its
    portion out, and once behind us unticked they stay in the box. A late
    tick of a meal before that day is taken to be in the count already. No
    timestamps on ticks are read, and no migration.
  - **A stored row now carries its batch's `leftover_of` meals too**, as a
    derived row does, so a meal planned from a batch keeps its tag, its
    warnings and its place in the count once the row is corrected.
  - **Freeze and Froze it say the count again** (`portions` = the box plus
    `aside`), since they move `updated_at` and later ticks count from then.
  - **Rows stored before this release read slightly differently** where the
    batch still had meals to come or `leftover_of` meals when they were
    stored: those now come off too. Rows are a day old; nothing is rewritten.
  - **`N left` is the box on the page and Cook** (`1 left · for Sun` with
    Sunday's meal planned from it), and **what is free to plan in the
    picker** (`2 left · till Jan`). The stepper sets the box, down to 0; a
    row with an empty box and nothing to come leaves the page. `gone_at` is
    set only by *Remove gone off*.
  - **Cook's line replaces the covers line on a cooked batch**, as the board
    frame draws it, on the phone tile and the wide sheet. A batch not cooked
    yet keeps its covers line and, until its fridge date, `freeze 2 by Tue
    for Thu` under the strip. `Cook Fri` on a batch nobody ticked names its
    next meal by the ticks (`cookDayOf`), not its first planned day.
  - **The Freeze button carries no snowflake.** The ruling puts it on freezer
    subheads and blue tags only; the frame's button icon was removed.
  - **The picker keeps the fridge row's green `leftover` tag**; only the
    `frozen` chip was ruled out. A freezer row has no tag, and a freeze-by
    row has the blue `❄ freeze by Mon` tag.
  - **Cook fresh instead is new**: nothing like it existed on the meal sheet.
    It clears `leftover_of` and `from_leftover` in one write
    (`PlanningRepository.cookFreshInstead`); the confirm sheet's *Frozen ·
    Cook fresh* is unchanged. A batch's own later meal (no pointer) has no
    such door. The sheet also says where a leftover meal comes from: its
    tag, `cooked Fri`, `freeze by Mon` while due.
  - **Freezer dates read `till Jan`** four weeks out or more, `till 21 Nov`
    within the month; a row with no date keeps its age.
  - **`ARCHITECTURE.md`'s standing table** now reads the whole plan, phases
    1–3 included.
  - **Not done here:** `make test-sim` (no simulator in this lane) and the
    roadmap row.

## Notes / open questions

- **The cross-week fold looks one week ahead only.** A freezer life of
  months could reach further; one week matches how the household plans.
- **Ask Ansi** reading the new cook day is its own follow-up.

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
