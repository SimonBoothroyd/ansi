# Exec plan: Leftovers, remembered

- **Status:** shipped in `v0.40.0` (2026-11-14) — migration `0061` on cloud, the full sim suite green on CI; the owner's look on a phone owed
- **Owner:** Simon (rulings), agents in lanes
- **Roadmap step:** 11 (anti-waste); reworks the model under [plan 0061](./0061-leftovers-by-the-ticks.md), whose screens and rules stay
- **Created:** 2026-11-09

## Goal

The app **remembers** each cooking instead of re-deriving it. A cooking is a
saved record with a fixed id. Meals link to it. Ticks, corrections and freezes
are small facts that sum to what is left. Nothing reads past weeks to work out
the present, so no screen can disagree with another and no chain of weeks
exists.

Plan 0061 (unreleased, on main) derives everything on the fly:

- **It clusters up to eight weeks.** It folds a freezable dish's next-week
  meal into this week's cooking, and cuts that chain at a fixed four-week
  calendar point.
- **A batch has no fixed identity.** Its id is its first covered meal, so
  moving or deleting that meal silently cuts every stored row and pick that
  pointed at it.
- **The amount made follows the plan after cooking.** Deleting a later meal
  makes real food vanish, and raising one grows the pot. The sim review saw
  the second case: raising Saturday's portions dropped next Thursday back to
  a fresh cook, with no sign.

The owner: "we've made something that should be trivial very hard"; "we
either have something in the fridge or we don't".

## Rulings

All of plan 0061's rulings stand (no tick means you didn't eat it; the cook day
is the earliest ticked day; dates; the screens), except where this list
replaces them. Taken with the owner on 2026-11-09, after two design rounds
between the orchestrator and an Opus reviewer.

- **A cooking is remembered.** It is born at the first tick on any of its
  meals, or at the first pick from it. Its id is fixed.
- **Meals link to it with one column**, `plan_entry.cooking`. A cooking's own
  meals and meals picked from it later are the same kind of link.
- **The amount made is fixed at the first tick.** Before that it is the live
  sum of its linked meals' portions. After it, deleting a meal or cutting
  portions leaves that food in the fridge.
- **The cook day and "cooked" stay derived from the ticks.** Unticking
  needs no write. Untick everything and the cooking reads not cooked: "cook
  <next meal>" if one is still to come, otherwise never cooked, nothing left.
- **No automatic cross-week sharing.** A meal shares a cooking only when
  someone picks it. Picking from a cooking that isn't cooked yet adds the
  meal's portions to what it makes. So *Ragù Sat* picked for next Thursday
  buys once and cooks it all on Saturday. The fold, its four-week cut and
  its copy go.
- **One choice whenever there is a pot to eat from.** Adding a dish that has
  one (fridge, freezer, or planned but not cooked yet) asks **From leftovers ·
  Cook fresh**, with neither picked. This replaces *Frozen · Cook fresh*.
  Adding the dish again from the recipe list after cooking is therefore a
  choice, never a silent new cook.
- **A tick counts as a portion eaten** even if that person is later taken off
  the meal. Each person still ticks only for themselves.
- **Remove gone off is final.** A later untick does not bring the row back.
- **A recipe with no fridge life keeps 7 days**, for its date and for grouping
  its meals into one cooking.
- **Two phones changing one count offline at once both apply.** For example,
  3 left, both set it to 1, and it reads 0. That is rare, visible and fixable.
- **Nothing visible is lost on update.** Every leftover today's page can show
  (28 days) carries over, with any old *binned / eaten* answers.

Added after the third sim review, 2026-11-10:

- **Removing a meal somebody ate keeps its leftovers.** A removed meal with
  a live tick does not un-cook its pot: its ticks still count toward cooked,
  the cook day and what it takes. Undo puts the meal back, and the count
  does not move.
- **You can't plan more from leftovers than is there; a shortfall later only
  warns.** Picking *From leftovers* keeps Add disabled with `only 1 portion
  left`. A shortfall that comes afterwards (a tick, a correction, portions
  raised) reads `not enough left` on the Week's tag and `Tue needs 3` beside
  the row's `N left`; the plan is never edited.
- **A pot not cooked yet takes a meal added beside it.** While nobody has
  ticked a cooking, a new unlinked meal of the same recipe in the cooking's
  own week that the shelf-life grouping puts with it joins it; *made* is
  still the live sum. After the first tick, a meal added to the week is a
  choice (*From leftovers · Cook fresh*).
- **Made is what was planned and bought.** Choosing Cook's *×1 whole batch*
  makes the whole batch: it is bought, and its spare is left over.

Added after the fourth sim review, 2026-11-10:

- **Count all of a dish.** A meal planned from leftovers takes from its own
  linked cooking first. Any shortfall then comes from the household's other
  cookings of the same dish, soonest to go off first (fridge before freezer),
  and only those good on the meal's day. It warns only when the household as
  a whole has not got enough. The giving row says the share (`2 for next
  Tue`), and rows of one dish say their cooked day (`cooked Sun`) so they can
  be told apart.

## Design

### Data

- **`cooking`** (new):
  - `id`
  - `household_id`
  - `recipe_id` xor `label`
  - `made numeric null` (null = still the live sum)
  - for one added by hand: `place` and `since`
  - `gone_at`
  - timestamps and `deleted_at`

  RLS by household.
- **`cooking_change`** (new): `id`, `household_id`, `cooking_id`, `fridge
  numeric default 0`, `freezer numeric default 0`, `created_at`,
  `deleted_at`.
  - A stepper commit writes one row with the difference.
  - Freeze or Froze it writes one row (−n, +n).
  - Undo soft-deletes the row.
  - A table, not a column: a PowerSync PATCH sends the whole value, so a
    jsonb column would lose one phone's edit (the reason `meal_eaten` is a
    table).
- **`plan_entry.cooking uuid null references cooking(id)`.**
- **`leftover`, `leftover_of`, `from_leftover` and `batch_leftover` stay
  read-only for one release.** They are dropped later with the owner's OK.
  Moving `from_leftover`'s foreign key would wedge an old build's upload
  queue.

### Rules

- **Before birth,** a week's unlinked meals of a recipe group into one
  cooking by the shelf-life clustering. This uses one week only, days 0..6,
  with fridge life `keeps_for_days ?? 7`.
- **A cooking not cooked yet** (no live tick on any linked meal, removed
  ones included; not said by hand or gone) is grouped with its buy week's
  unlinked meals of the recipe the same way. One that lands in its group
  joins it: every reader counts it, and the cooking's next write (a tick,
  read before the tick lands, or a pick) links it. A *made* already fixed
  (unticked into nothing since) grows by the joiner's portions as it links.
- **Birth** (first tick or first pick on a group):
  - Reuse a cooking already linked to any meal in the group, or one whose id
    is a group meal's id.
  - Otherwise create one whose id is the group's earliest meal (the anchor).
    Two phones compute the same id; the upload is an upsert, so it is
    idempotent.
  - Then link the whole group.
- **Made, whole batch.** A cooking whose cook chose the whole batch rounds
  made (fixed or live) up to whole batches of its recipe. The choice is one
  `cooking_change` row with a fixed id that moves no portions.
- **Cooked** = a linked meal has a live tick, a removed one's too.
  - **Cook day** = the earliest day with a live tick.
  - A hand-added cooking uses `since`.
- **What a meal takes:**
  - a day behind today takes its ticked shares, capped at its portions;
  - today or later takes its planned portions in full ("spoken for");
  - a meal removed after it was ticked takes its ticked shares, whatever
    its day, and is spoken for no more.
- **Where it takes from:**
  - on or before the fridge date (cook day + `keeps_for_days ?? 7`), the
    fridge;
  - after it, the freezer, if the dish freezes and is within freezer life
    (the assumed freeze, of only what the fridge has: `min(planned,
    available)`; the rest warns);
  - otherwise the fridge, with `past its date`.
- **Counts:**
  - fridge = made + Σ fridge changes − portions of freezer meals − fridge
    takes;
  - freezer = Σ freezer changes + portions of freezer meals − freezer
    takes.

  Shown clamped at 0, kept unclamped, so an untick reverses exactly. Free =
  box − spoken for.
- **Shop and cost:**
  - A cooking is bought, and costed, in the week of its earliest linked
    meal, for `made` (or the live sum while null).
  - A linked meal in any other week buys nothing.
  - Week W's shop = W's unlinked meals clustered, plus the cookings bought in
    W. This is a one-week read.
- **A recipe swap** on a linked meal clears its link.
- **Leftovers page and picker** read live cookings (no `gone_at`) with their
  linked meals, ticks and changes. This is one flat query, with no horizon
  walk.

### Edge cases (the design's answers)

1. **Untick the only tick on a past meal:** never cooked, 0 left, its picks
   warn.
2. **Untick the only tick with meals still to come:** "cook <next>"; made
   keeps its snapshot.
3. **Untick the earliest tick:** the cook day and dates move later.
4. **Ticks backfilled Sat, Fri, Wed:** the first tick births the cooking.
   The cook day walks earlier, and the end state doesn't depend on order.
5. **Set to 1, untick Fri, tick again:** 1 → 3 → 1. The correction is a
   delta.
6. **Both phones tick offline:** the same id, upserted twice; the duplicate
   ticks merge on read.
7. **Both phones correct offline:** both deltas apply (a ruling).
8. **One phone unticks while the other corrects:** said + untick.
9. **Two phones with different plans both make a first tick:** at worst two
   cookings and a visible over-count, which the stepper fixes.
10. **A meal removed or moved before cooking:** it regroups, and nothing
    points at it.
11. **An own meal removed after cooking:** made is unchanged, so its
    portions are freed into the fridge.
12. **An own meal moved after cooking,** even into another week: it stays
    linked, and past the fridge date it is a freezer meal or warns.
13. **The anchor removed before cooking, with a pick on it:** the cooking
    keeps its id. Its made is the picks; the pick cooks.
14. **Portions raised on a later meal after cooking:** it warns `Sat needs 3
    · 2 left`, and the pot doesn't grow. This is the sim break, fixed.
15. **Portions lowered after cooking:** portions are freed.
16. **An eater taken off after ticking:** the tick still counts (a ruling).
17. **A skipped first meal:** the cook day is the next ticked day, and the
    skipped meal's portions are left.
18. **A pick from Saturday before it is cooked:** Thursday's portions add
    to made, bought once in Saturday's week.
19. **A pick after Saturday's first tick:** it takes from the spare, or warns
    `not enough left`.
20. **The source unticked into nothing after a pick:** it reads "cook Thu",
    with made still Saturday's snapshot.
21. **Cook fresh instead,** on any linked meal: it clears the link, frees the
    portions, and the meal is bought in its own week.
22. **Freeze 2, then untick Friday:** the freezer keeps 2, and the fridge
    gains Friday's portions.
23. **Freeze by:** it reads `freeze by Mon for Wed` until Mon, then
    Wednesday is a freezer meal. No write is needed.
24. **Undo of Freeze, Froze it or Remove gone off:** it soft-deletes the
    change or clears `gone_at`.
25. **Remove gone off, then a late untick:** it stays gone (a ruling).
26. **Typed leftovers:** a cooking with a label; the fridge keeps 7 days, the
    freezer shows an age; it isn't offered in the picker.
27. **The same dish every week:** one cooking a week; sharing only by pick.
    No chain, and no skipped week.
28. **A dish twice in one week, beyond its fridge life:** two groups, two
    cookings.
29. **Week start changed:** there is no stored week. The buy week follows
    the linked meals.
30. **Recipe fridge or freezer days edited:** dates read live.
31. **Remove a meal both ate** (curry Sun, both tick, 2 left): still 2 left,
    dated Sunday; Undo, still 2 left (a ruling).
32. **Ragù Sat picked for next Thu, then Fri added in the same week:** one
    pot, cooked Fri, covering Fri, Sat and next Thu; Friday's first tick
    links it and fixes made at all three.
33. **The same, after Saturday's first tick:** Friday is its own cook unless
    picked *From leftovers*.
34. **The assumed freeze with 1 in the fridge and 3 planned:** the freezer
    reads 1, never 3, and Tue warns. After *Freeze*, the fridge row at 0
    goes, with its *Freeze*, and the warning is the freezer row's.
35. **Whole batch:** curry serves 4, planned for 2, ×1 whole batch, both
    tick: 2 left. The shop buys the whole batch.
36. **Count all of a dish:** Hamburger Helper fridge 1 (Sunday's) and
    freezer 2 (last week's); Tuesday for 3 planned from Sunday's. No
    warning: it takes 1 + 2, and the freezer row reads `2 for Tue`. Next
    Tuesday instead (past Sunday's fridge date): the fridge row reads `❄
    freeze by Wed for next Tue` and the freezer row `2 for next Tue`.
37. **The same with fridge 1 and freezer 1:** Tuesday warns `not enough
    left`, short by 1; both rows give what they have.
38. **A pot not cooked yet gives nothing to another cooking's meal**, and
    a shelf past its date on the meal's day gives nothing either.
39. **A meal added to a day behind us:** the choice is asked as for any
    day, judged on that day; a pot good then is offered.

## Approach

One release, with a migration. The migration deploys to cloud first, then the
build, and both phones update the same day. Back up cloud before the deploy.

### Phase 1 — schema

1. **Migration `0061_cooking.sql`:**
   - `cooking`, `cooking_change` and `plan_entry.cooking`, with RLS and
     pgTAP.
   - **SQL conversion:**
     - each 0060 `leftover` row becomes a cooking with the same id;
     - `from_leftover` is copied into `plan_entry.cooking`;
     - a meal whose `leftover_of` is X links to the cooking whose row names
       X as its batch, or to a new cooking with id X (made null).
2. Both PowerSync stream files, the local schema, and `db-schema.md`.
   Recreate the local PowerSync container from this checkout (the mount
   trap).

### Phase 2 — the model

3. **Domain (pure):** birth and reuse, made, the cook day, takes, places,
   counts, warnings, and the buy week, with tests for every edge case above.
4. **Repository:** the cooking reader (one flat query), the tick path
   (births a cooking on the first tick), the pick path, Cook fresh instead,
   the change rows (stepper, Freeze, Froze it, Undo), and Remove gone off.
   Use real-DB repository tests. Local tables are views, so never UPSERT: a
   birth checks for the id first, or relies on the upload's upsert.
5. **The client pass:** once per launch, for this release only. It births
   cookings for groups ticked within the last 28 days that no cooking covers
   yet, and carries old `batch_leftover` answers over as zeroing changes. Ids
   are deterministic, so it is idempotent on both phones.
6. **Delete:**
   - the fold (`_foldNextWeek` and its helpers, the 7..13 offsets, the
     four-week cut);
   - the eight-week and multi-week reads;
   - `kLeftoverHorizon` and its walk;
   - `TickSpan`, `_sessionAsOf` and the time-based correction model;
   - the stored-versus-derived merge;
   - `leftoverKey` as an identity.

### Phase 3 — screens

7. **The confirm sheet:** **From leftovers · Cook fresh**, neither picked,
   whenever the dish has a pot to eat from (fridge, freezer, or not cooked
   yet). An uncooked pot is offered in the picker's Leftovers section too.
8. **Re-point the screens to the cooking reader:** Leftovers, Cook, Week
   tags and warnings, the meal sheet and Undo. The copy is plan 0061's;
   the fold's copy goes.
9. **The board:** frames for the choice sheet. Flip plan 0061's fold frames
   to removed.

## Acceptance criteria

- [ ] The edge cases above each have a test.
- [ ] No read in the app spans more than one week, apart from the cooking
      reader's flat query.
- [ ] Ragù Sat picked for next Thu: bought once, in Saturday's week; Cook
      says cook it all, freeze 2.
- [ ] Raising a later meal's portions after cooking warns. It never drops a
      link or changes what's bought.
- [ ] Every leftover visible on `0e486821`'s page (28 days) is still visible
      after the update, with the same count, or one the decision log
      explains.
- [ ] Two phones: a tick, a correction and an untick made offline on both
      converge after sync (repository test with two databases, as the
      dropped-write tests do).
- [x] Docs: product spec, `db-schema.md`, the cook_plan and planning
      READMEs, `ARCHITECTURE.md`, and the board.
- [x] The sim reviews' checks are simulator smokes: `leftovers_ticks`
      (backfilled ticks, a hand count following ticks, removing a meal both
      ate, Freeze / Froze it / Remove gone off with Undo), `leftovers_choice`
      (the choice sheet, a cross-week pick bought once, a double-tapped Add)
      and `leftovers_batch` (whole batch, a recipe opened at its amount).
- [x] The three `leftovers_*` smokes green on the iPhone 17 simulator
      (2026-11-11), each twice in a row:
      - `leftovers_ticks`: 4/4 scenarios (1, 2, 3, 4).
      - `leftovers_choice`: 3/3 scenarios (5, 8, 6).
      - `leftovers_batch`: 2/2 scenarios (7, 9).
- [ ] `make test-sim` green (the whole suite), then a fresh hands-on sim
      review.

## Decision log

Append-only.

- 2026-11-09 — Plan written. The design came from two rounds between the
  orchestrator and an Opus reviewer:
  - **Round 1** named derived identity as the root of drift and found 51
    edge cases.
  - **Round 2** cut it down to one link column, a two-column change row,
    one buy-week rule and an SQL-first conversion.

  The owner ruled every open question interactively.

- 2026-11-09 — Phases 1 and 2 built (one lane). Migration `0061_cooking.sql`
  proven on an isolated stack (`ansiproof`): 62 migrations from zero, 31
  pgTAP files / 676 tests, and the upgrade path replayed over 0060-shaped
  rows. Decided in the lane:
  - **A cooking is up to two rows**, a fridge shelf and a freezer shelf
    (`Leftover`, keyed by cooking id and shelf). A correction names its
    shelf: the stepper writes the difference from the unclamped box.
  - **A meal takes from its date's shelf first, then the other's spare.**
    So after Freeze (which moves the whole fridge box), a meal still within
    the fridge date eats from the freezer instead of warning. A freezer meal
    is covered by the freezer's spare first and moves only the rest.
  - **The assumed freeze is shown on its day.** Until the fridge date passes,
    a freezer meal's portions read in the fridge (`freeze by Mon for Wed`),
    as plan 0061 drew it; the counts are the same either way.
  - **Today's meal is spoken for**, as the rule says, even once ticked: on
    the cook day `N left` still holds that night's portions.
  - **Warnings:** `not enough left` only on meals from today on, plus every
    meal of a cooking never cooked. A cooking's own meals and picks warn
    alike (edge 14), so the old `own` flag is gone.
  - **Remove gone off** sets `gone_at` only when every shelf of the cooking
    is in the list; a fridge part gone off beside a good freezer part is
    counted to nothing by a change instead (not final).
  - **The connector uploads a `cooking` or `cooking_change` PUT as an insert
    that leaves an existing row alone** (`insertOnceTables`): two births of
    one id keep the first, and a late offline birth cannot undo a
    `gone_at`.
  - **The first pick from a pot not born yet births it** (`cookingForPick`):
    `addEntry(cooking:)` takes a cooking id or a meal of the group.
  - **A meal with no fridge life stated groups by 7 days** before birth, so
    one week never splits (it never split before either).
  - **The carry-over** waits for the launch's first finished download, so
    the server's converted cookings are local before any birth. An old row
    naming a batch became a cooking said by hand (its count, place and
    date); linking its batch's meals adds one change so it still reads what
    was said, and later ticks move it. Against `0e486821`'s page, counts
    differ only where 0061's unreleased adjustment model had moved a row by
    ticks since it was said, and where a past pick nobody ticked now stays
    in the box (no tick means you didn't eat it).
  - **The week's cost** costs each cooking once, at what it made, in the
    household's figure; under a lens its meals are the member's shares, as
    any meal. Ask's cost reads the cook plan for this.
  - **No recipe swap exists** on a planned meal (Ask removes and adds), so
    the swap rule needs no code yet.
  - **Removed with the fold:** next week's Cook no longer lists meals eaten
    from an earlier pot (`foldedMealLines`); phase 3 decides whether a line
    comes back. `cookedDaysOf` now counts every planned day of the dish.
  - **Not done here:** phase 3, the product spec, `ARCHITECTURE.md`, the
    board, `make test-sim` (no simulator in this lane), and recreating the
    local PowerSync container from this checkout.

- 2026-11-09 — Phase 3 built (one lane): the screens, with the owner's
  rulings of that day (the choice sheet, pots not cooked yet in the picker,
  next week's Cook line, the host meal's sheet, Remove gone off final, the
  second sim review's fixes). The product spec, `ARCHITECTURE.md`, the
  READMEs, the board and a tech-debt row for the old columns. Decided in the
  lane:
  - **A pot is what the picker would offer for the day.** The confirm sheet
    asks **From leftovers · Cook fresh** when `leftoversGoodOn` offers the
    dish, and links to the first offer (fridge before freezer, soonest to go
    off first). A pot not cooked yet caps nothing and has no `N left`: its
    choice and card say `cooks Sat`, and the card *Cooked with it, bought
    once*.
  - **Two kinds of pot not cooked yet.** A cooking nobody has ticked (born by
    a pick) is a row like any other, flagged `Leftover.cooked` false, and
    offered once whatever shelf it reads on, even in its own week. Planned
    meals no cooking holds yet are `LeftoverShelves.pots`, grouped as a birth
    would group them under their first meal's id; they are offered only to a
    later week than their own, because a meal in the same week already shares
    the batch when it fits, and *Cook fresh* there would be the same pot.
  - **The unborn read is a second flat query** (`loadUnbornMeals`): planned
    recipe meals from today on with no cooking, by date. It walks no weeks,
    but it is the one read beside the cooking reader that spans more than a
    week.
  - **Remove gone off:** `gone_at` (now the household's clock, not the
    wall's) puts the fridge part away for good, and the freezer part too
    unless it is still in date that day. No change row is written for a
    fridge part any more, so an untick cannot refill it. The line is drawn
    by the freezer date alone, which an untick moves by days against a life
    of months; a fridge-past-date test would have flipped when an untick
    moved the cook day. A cooking said gone off is read while its recipe
    freezes (or it was said into the freezer), so the read keeps those for
    good. Undo puts back the `gone_at` it had before, so removing twice and
    undoing once leaves the first. A freezer part gone off beside a fridge
    part in date (a freezer life shorter than the fridge's) is still counted
    to nothing by a change, not final.
  - **Next week's Cook** lists a meal eaten from an earlier cooking as one
    line (`earlierMealsOf`), placed after the cards, in the shelf's ink, no
    icon (a snowflake never goes before a dish's name); `cook it` once nobody
    ticked the earlier meals and the meal has become the cook day. The host
    meal's sheet already said `cook it all · freeze 2 for next Thu` from the
    link; a test holds it.
  - **The meal's sheet** dates its pot by the cooking's id, not by which row
    lists the meal, and says `cooks Sat` until it is cooked. A meal before
    its batch's cook day (by the ticks) gets no caption.
  - **Dates:** one formatter. `till` reads a weekday within six days, else a
    date from the fridge and a month from the freezer (a freezer row within
    six days says its weekday). `cooked` reads the week by the household's
    week shape: `cooked Sat`, `cooked last Sat`, then a date.
  - **Undo toasts** stay 10 s. The fall-through was the stack: Forui paints an
    older toast peeking above a newer one, and that strip takes no tap (its
    hit test is at the toast's laid-out place, not its painted one). A newer
    Undo now replaces the one on screen; a test holds that a tap on a lone
    toast's words or padding never reaches what is under it.
  - **The default slot is not broken.** The picker opened on Saturday,
    whose card was empty: the first unfilled default of an empty day is
    Breakfast, by the rule.
  - **The slot label** stands level with its dish's first line and never
    wraps, so a wrapped name's second line no longer reads beside it.
  - **Not done here:** `make test-sim` and a hands-on sim review (no
    simulator in this lane). A meal of an earlier cooking that has become
    its cook day (`cook it`) draws no strip on its sheet: its batch is in the
    week before.

- 2026-11-10 — Sim review 3 (one lane). A hands-on simulator review found a
  crash and five model bugs; the owner ruled two points (Rulings, *Added
  after the third sim review*). No migration. Decided in the lane:
  - **A double-tapped Add popped twice** and go_router asserted on its last
    page. Add is single-shot (disabled while saving), and every save that
    pops after an await goes through `popIfCurrent`, which pops only a route
    still mounted and on top. Swept: *Add a leftover* (single-shot too), at
    home, top-up, price, label photo and the sub-recipe picker.
    `test/structure/pop_after_save_test.dart` holds it.
  - **Joining is read, then written.** Every reader (Cook, the shop and cost,
    the Leftovers read, the picker's pots) counts a joiner in the pot; the
    link is written at the pot's next write, a tick (read before the tick
    lands, so the first tick still sees an uncooked pot) or a pick. A
    joiner is no pot of its own in the picker. The confirm sheet's batch
    strip counts the pot's meals too. A writer groups against that cooking
    alone, a reader against every uncooked cooking of the week: they differ
    only with two uncooked pots of one dish in one week.
  - **A removed meal's ticks still read**; removal keeps the link and writes
    nothing. The cooking read takes a removed meal's ticked shares and gives
    it no tag. Cook and the shop still read live meals only, so a cooking
    whose meals are all removed has no session there.
  - **The assumed freeze moves `min(planned, available)`.** Before the
    fridge date the shortfall is the fridge row's (`1 left · Tue needs 3`);
    after it, or once *Freeze* has emptied the fridge, the freezer row's. A
    fridge row with nothing in it offers no *Freeze*.
  - **The whole-batch choice was not stored**: it was a per-session
    display toggle, reset on scroll. It is now one `cooking_change` row per
    cooking with a fixed id (`wholeBatchChangeId`) that moves no portions;
    choosing it on a group not in a cooking births one. Made's snapshot stays
    the planned sum and the rounding is read on top, so going back to exact
    is clean. The shop and the cost follow it (*planned and bought*), and a
    cooked batch shows no switch. The tech-debt row narrows to the cook day.
  - **Cook's order** is by day across kinds; its header counts the week's own
    meals (days 0..6), not what a pot made or a later week eats.
  - **The strip:** a batch not cooked yet tints its keep days only until the
    dish's next cook; a cooked batch's window is what its leftovers really
    keep, so it stands.
  - **The picker's *Already this week*** is one chip per dish naming every
    day (`Fri + Sat`).
  - **A single-meal cook wears its marker once cooked** (`cooked Sun`). Plan
    0061's rule (*a single-meal cook gets none*) was about the uncooked
    plan, where `cooks Sun · batch of 2` is noise; it still holds there.
  - **The not-enough copy was already consistent** (`only 1 portion left` at
    the pick, `not enough left` on the tag, `Tue needs 3` beside `N left`);
    no string changed.
  - **Not done here:** `make test-sim` and a fresh hands-on sim review (no
    simulator in this lane), and the release.

- 2026-11-10 — **A recipe opened from a cooking opens at its amount**
  (owner's ask). Cook's titles (phone card, desk row, component card) and the
  Week dish row's title — the existing doors, none added — carry
  `?servings=N` beside `?week=`; the page seeds its servings provider once
  on arrival, and the stepper and Ask move it as before.
  - **From Cook, the batch the title names:** the first session not cooked
    yet, else the last. A split recipe has one title over two batches, and
    the one still to cook is the one being cooked.
  - **The amount is `totalPortions`**, so the stored whole-batch choice opens
    whole; a component batch opens at batches × its servings.
  - **From the Week, the pot is the cook plan's session** (a cooking, or the
    week's grouping before one is born, or a pot bought in an earlier week),
    not only `plan_entry.cooking`: the pot is cooked before anyone ticks.
    A meal no session covers opens at its own `demandPortions`.
  - Library, search and back-links send no amount and open at the recipe's
    own servings.

- 2026-11-10 — Sim review 4 (one lane). A fourth hands-on review found nine
  issues; the owner ruled *Count all of a dish* (Rulings). No migration.
  Decided in the lane:
  - **The dish-wide read is two passes** (`readDishes`): each cooking alone,
    then each meal's shortfall drawn, in day order, from the other cookings
    of its recipe: cooked ones only, by the page's order (fridge first,
    soonest to go off), each only from a shelf whose date covers the meal's
    day as it stands (a fridge row past its date then is not frozen for
    another pot's meal), and only what that shelf has free once its own
    meals are served. The two cookings are read again with the shares in.
    A share given to a meal behind us leaves the giver's box; one ahead is
    spoken for. Every write reads the cooking with its whole dish
    (`readCookingIn`), so the stepper measures against the box as drawn.
  - **The pick may plan the dish as a whole:** *From leftovers* caps at what
    every pot of the dish good on the day has free, links to the first, and
    names that pot by its cooked day (`1 left · cooked Sun`) when more than
    one could serve. Its count is that pot's own.
  - **One day rule** (`weekdayFrom`, `leftoverDay`): `today`; a day of the
    reference week by its weekday; `next Tue`; `last Sat`; else `17 Nov`.
    Leftover lines read from today's week; Cook and the meal sheet's batch
    lines from the week on screen. So Saturday's card now reads `freeze 2
    by next Tue for next Thu` (it read `by Tue`). The freezer's `till Jan`
    past six days stays a month.
  - **A past day** is judged on that day: the picker's Leftovers and the
    choice sheet offer a pot good then. A meal that became its own cook by
    mistake is fixed with no new button: remove it and add it again, and
    the choice is asked (the meal sheet has *Cook fresh instead*, and no
    door the other way).
  - **The whole-batch switch was stale** because `watchCookPlan` did not
    read `cooking_change`; it joins it now, and so does the shop's watch
    (which read no cooking at all), each selecting a column.
  - **Cook fresh instead's Undo** writes and the sheet follows it live (a
    widget test drives both ways); the review's no-op was not reproduced,
    so it is taken as the 10 s window running out between scripted taps.
  - **Small:** Freeze closes the stepper, so Undo brings its row back
    closed; a typed freezer row's age reads `added today`; the Removed and
    Froze toasts name the cooked day when two rows share a name; Cook orders
    one day's cards and lines by slot; next week's Cook line says `not
    enough left` as the tag does; a week of meals that need nothing bought
    says `nothing to buy`, with no door.
  - **Not done here:** `make test-sim` and a fresh hands-on review (no
    simulator in this lane), and the release.
- 2026-11-10 — **The sim reviews' checks became smokes** (one lane, no
  simulator: written, analyzed and `make ci` green, never run). Three
  self-provisioning files, nine scenarios. Decided in the lane:
  - **Jun's ticks are written as Jun over HTTP**
    (`SmokeStack.tickAsPartner`): the server lets a member tick only for
    themselves. That write is the `meal_eaten` row alone, so a scenario
    ticks for Ada first and her tick births the cooking.
  - **Past meals sit in last week**, wholly behind us on any weekday; meals
    still to come sit on today, or later this week (today on a Sunday).
    Every expected date is said by the app's own formatter.
  - **Ticks go through the meal sheet where they are the subject** (backfill,
    a count following ticks, the whole batch) and through the planning
    repository, the sheet's own write, where they are setup.
  - **The choice sheet's pot is food said by hand** (*Add a leftover*, one
    portion, today), so its count does not hang on the day.
  - **No widget keys were added**: rows are found by the Leftovers page's
    own `cooking:shelf` keys, the public `MealEatenRow`, `EaterAvatarStack`,
    `LeftoversDoor` and `WeekSwitcher`, and the copy.
- 2026-11-11 — **The leftovers smokes ran on the simulator**, green twice
  each. One app bug, three test bugs:
  - **App: the sync-health watcher queried a closed database.** Its tick
    and status stream kept calling `getUploadQueueStats` after the
    database closed (a smoke's teardown; sign-out does the same), which
    threw `ClosedException` as an uncaught async error. It now checks
    `db.closed`, catches `ClosedException`, and stops; a unit test closes
    the database under a live watcher.
  - **Test: the gone-off soup kept one fridge day**, so its Saturday meal
    (a dish that cannot freeze, past Thursday's date) clustered as a cook of
    its own and nothing was left. It keeps two days now.
  - **Test: one cooking's Shop line is the title alone.** `· cook <day>`
    names a dish split into more than one session; the cross-week pick is
    one cooking.
  - **Test: the whole batch reads `4 left` on its cook day**, as today's
    meal is spoken for even once ticked; the spare shows as 2 free to plan.

## Notes / open questions

- **Drop `leftover`, `leftover_of`, `from_leftover` and `batch_leftover`**
  one release later, with the owner's OK.
- **Ask Ansi's moves** must carry `plan_entry.cooking`, as they now carry
  the two old pointers.

## Step-done checklist

The code landing is not the step landing. Tick these before setting Status to
done and moving this file to `completed/`.

- [ ] Roadmap row updated: status flipped, one line on what shipped and what was
      deliberately deferred.
- [x] `ARCHITECTURE.md`'s standing table matches reality for every area touched.
- [ ] `app/AGENTS.md` "Current focus" and command list still true.
- [ ] Feature steps: `make test-sim` run on a booted simulator (the UI paths CI
      can't reach), and the result recorded here. The `leftovers_ticks`,
      `leftovers_choice` and `leftovers_batch` smokes exist and have not run
      on a simulator yet.
- [x] Tech-debt rows **added** for corners knowingly cut, and **retired** (or
      narrowed) for debt this step paid off.
- [ ] New migrations or seed changes? Say in the roadmap row whether they have
      reached **cloud** yet, and append a `docs/cloud-setup.md` ledger entry
      when they do. A "pending cloud push" note nobody clears becomes a false
      claim the moment the push happens.
- [ ] `make ci` green.
