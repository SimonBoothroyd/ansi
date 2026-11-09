# Exec plan: Leftovers, remembered

- **Status:** phases 1–2 built on 2026-11-09 (one lane), unreleased; phase 3 (screens), the docs beyond the READMEs, `make test-sim` and the release owed
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
- **Birth** (first tick or first pick on a group):
  - Reuse a cooking already linked to any meal in the group, or one whose id
    is a group meal's id.
  - Otherwise create one whose id is the group's earliest meal (the anchor).
    Two phones compute the same id; the upload is an upsert, so it is
    idempotent.
  - Then link the whole group.
- **Cooked** = a linked meal has a live tick.
  - **Cook day** = the earliest day with a live tick.
  - A hand-added cooking uses `since`.
- **What a meal takes:**
  - a day behind today takes its ticked shares, capped at its portions;
  - today or later takes its planned portions in full ("spoken for").
- **Where it takes from:**
  - on or before the fridge date (cook day + `keeps_for_days ?? 7`), the
    fridge;
  - after it, the freezer, if the dish freezes and is within freezer life
    (the assumed freeze);
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
- [ ] Docs: product spec, `db-schema.md`, the cook_plan and planning
      READMEs, `ARCHITECTURE.md`, and the board.
- [ ] `make test-sim` green, then a fresh hands-on sim review.

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
