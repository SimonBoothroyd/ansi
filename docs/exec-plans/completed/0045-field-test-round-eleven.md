# Exec plan: field test round eleven — the honest import slot, notes on a line, and a household's first day of the week

- **Status:** done — landed on main, 0043 on cloud, shipped as `v0.15.0`
- **Owner:** agent (lanes: `import-slot`, `line-card`, `week-server`, `week-app`)
- **Roadmap step:** — (owner's first joint field test on `v0.14.0`)
- **Created:** 2026-09-12

## Goal

Three things the owner and his partner hit in the first hour of using the app
together.

**An import amount that is not resolved must not look resolved.** "1 whole
lime" and "1 can chopped tomatoes" arrive with a unit word the matched
ingredient cannot carry. The review card printed "1 whole" / "1 can" in the
amount slot, so the line read as filled while the `Pick a supported unit`
flag under it held Save. Owner: *"because we have the source text, I think we
need to leave it blank and give the usual warning"*; on cans, *"it lists can
but doesn't auto pick one of our measured 'cans'. I'd rather it just be empty
and prompt us."*

**A note can be set on a recipe line.** Owner: *"how do I set a note on an
ingredient through the ingredient editor? it just opens the ingredient
picker... maybe we need to swap to the import style editor?"* Verified: the
editor's line had two invisible doors (amount → quantity sheet, identity →
picker) and its notifier had no note setter; notes only ever entered through
import.

**The week starts on the day the household shops.** Owner: *"can we start
the week on Sunday?"* and, on the reason: *"it needs to be for shopping... we
usually food shop and plan on Sunday."* Under a Monday-start week a Sunday's
meals belong to the week that is ending, so the Sunday shop for "next week"
never covered that night's dinner.

## Acceptance criteria

Lane `import-slot` — `features/import/presentation`:

- [x] A matched line carrying `LineIssue.unitNotAllowed` prints an EMPTY
      amount slot (`—` on the row, `set amount` on the card chip); the flag is
      the only prompt. The source line is visible on the flagged line in both
      compact and expanded states. The parsed number stays on the resolution,
      so the sheet opens on it and one chip tap resolves the line.
- [x] Lines without the flag are unchanged: an unpicked range still prints
      `2–3 cloves`, an imprecise amount still prints `pinch`.
- [x] Unit tests on the slot label; a widget test on "1 whole lime" in both
      states; the two board frames that printed a flagged amount redrawn.

Lane `line-card` — `features/recipes/presentation`, `features/import/presentation`:

- [x] The editor's line is the review's expanding card: bare row at rest,
      anywhere on it opens the card (identity with `change ›`, the optional
      flag row, the AMOUNT chip, the inline NOTES field, `used in N steps`
      under the head, the bin in the head). The grip is on collapsed rows only
      and a drag collapses every open card.
- [x] `RecipeEditor.setLineItemNote` exists, routes through `_mapItem` (never
      the identity path, so it cannot relabel chips), blank clears, and the
      note round-trips through save.
- [x] The editor's quantity sheet no longer shows the optional switch (the
      card's flag row owns it); every other caller keeps it.
- [x] One function prints a line's note on the editor row, the review row and
      the recipe page: name ` · ` muted-italic note. A test holds the rule.
- [x] The shared widget is `features/recipes/presentation/line_card.dart`;
      import keeps its cascade, `from source:`, flags, Save gate and dropped
      state; its card tests pass, changed only where a ruling changes what
      prints.
- [x] Board `recipe-editor.html` flipped from proposed to built; spec §5 and
      the recipes README describe the line as current state.

Lane `week-server` — `supabase/`:

- [x] Migration `0043_household_week_start.sql`: `household.week_starts_on
      smallint not null default 1 check (between 1 and 7)` (ISO weekday), and
      `set_household_week_start(household_id, starts_on)` — sets the column
      and re-homes every week whose key residue disagrees, in one
      transaction, idempotent, symmetric, never violating
      `unique (household_id, week_start_date)`.
- [x] pgTAP: the Mon→Sun flip of a two-week household (Mon/Wed/Sun meals, a
      Sunday-only recipe with an override, ticks with and without a week)
      lands every row at its new address with nothing lost; twice is a
      no-op; Sun→Mon restores; an orphan week written under the old residue
      is repaired by a re-run; a second household is untouched.
- [x] `db-schema.md` regenerated; `cloud-setup.md` notes the migration as
      pending cloud push until it is pushed.

Lane `week-app` — `app/`:

- [x] A pure-Dart `WeekShape(startsOn)` owns `weekStartOf`, `keyOf`,
      `offsetOf`, `dateFor` and the day labels; `mondayOf`/`weekKeyOf` and the
      14 direct weekday-table index sites retire; a structural test forbids
      them coming back.
- [x] The first reader of `household`: a repository exposing the shape
      (Monday until the row arrives); planning, cook_plan, shopping, recipes
      and shared read it. A Monday-start household produces byte-identical
      output to today; a Sunday-start household puts a Sunday meal at offset
      0 under the Sunday's key.
- [x] Account → Household: `Week starts on` chip row (Sunday · Monday) under
      the roster, a plain-words confirm, online-only with one line saying why
      when offline, `moving your weeks…` while the RPC runs, an amber retry
      line on failure. The column is written only by the RPC.
- [x] The ~24 test files that encode Monday follow the shape; integration
      tests updated but not run (sim on hold).
- [x] Board `week.html` / `account.html` flipped to built; spec §4 and the
      shopping section, the planning/cook_plan/shopping READMEs and
      `words.dart` say "the household's first day", never Monday.
- [x] Tech-debt `cook_plan` row narrowed: the Sunday-batch case is gone, the
      per-session override store is still unbuilt.

Landing:

- [x] `make ci` green per lane and on the assembled branch; `make db-reset`
      and pgTAP green for the migration.
- [x] Migration 0043 pushed to cloud (deploy 34711560878) and the ledger
      entry written.
- [x] Smoke (`make test-sim`) on `recipe_editor`, `week` and `week_variant`,
      one at a time on the booted simulator: all three green.

## Approach

1. Design lanes first (done): the line card and the week start were drawn as
   proposals in the screen's own board file, with D-numbered options and one
   recommendation each, and put to the owner in one message.
2. Build lanes in worktrees, one conventional commit per slice, no merges;
   `line-card` builds on top of `import-slot`'s commit because both touch the
   review card; `week-app` and `week-server` are split at the RPC name and the
   column, so they run in parallel and meet at landing.
3. Land by pushing each branch to `main` in order — import-slot, line-card,
   week-server, week-app — rerunning the gate at each step; expect the
   board's `index.html` to conflict between lanes and resolve by keeping every
   status-date bump.

## Decision log

- 2026-09-12 — **A flagged amount prints empty.** The card's slot had two
  honest rules (round-2 #3: prefer the printed original while it reads as an
  amount) and one dishonest outcome: a number beside a word the ingredient
  cannot carry reads as done. The owner's words are the rule; the source line
  is what makes blank safe. The number is kept so resolving is still one tap.
- 2026-09-12 — **The editor's line is the review card.** Owner's lean,
  confirmed with the rulings: bare rows at rest (twelve bordered boxes make a
  finished list look unfinished); one gesture to open, two taps for an amount
  accepted (*"yes"*); the bin off the row (*"yes"*); optional owned by the
  card's flag row, leaving the editor's sheet; `used in N steps` on the card;
  the widget under `recipes`, imported by import (the direction the dependency
  already runs).
- 2026-09-12 — **The middle dot stays.** Plan 0044 dropped it on the page;
  the editor and review kept it; the owner chose *"dot"*. One function prints
  the note on all three surfaces so they cannot drift again.
- 2026-09-12 — **The optional toggle takes the tag's geometry**, not the
  review's pill: off = outline and empty ring, on = herbSoft fill and the
  word; filled herb with a check stays week mode's `included`. Agent's call
  on the owner's *"you decide"*.
- 2026-09-12 — **The first day of the week is a household fact**, a synced
  column, because it decides the key rows are written under: two devices
  disagreeing would not disagree about a view, they would write meals into
  two different weeks.
- 2026-09-12 — **Re-key, not a derived window.** The stored week start
  becomes the window's actual first day and `day_of_week` stays what the code
  already computes — the offset from the key. The three repositories keep
  binding one string, copy-last-week and the variants ride along. A window
  derived over two stored weeks breaks shelf-life gap arithmetic and gives a
  tick two possible weeks; keying forward without re-homing draws Monday's
  meals under Sunday silently. Both rejected.
- 2026-09-12 — **The flip is an online-only server transaction.** One rare
  setting breaks "everything works offline" so that no device can ever see
  the new start with old keys, and so that a meal queued offline across the
  flip is repaired by re-running it. Owner: *"sg."*
- 2026-09-12 — **A shopping tick moves with its week.** It is a state about a
  trip, not a meal, and it is the one row whose meaning rather than address
  changes; ruled explicitly. Owner: *"sg."*
- 2026-09-12 — **No "and don't move my old weeks" option.** Offering the
  silent-corruption path as a choice is offering a wrong answer. Owner:
  *"nah."*
- 2026-09-12 — **A week and a tick re-key by their midpoint.** The first
  cut moved a key only downwards, which made the flip back take the long way
  round: a Sunday week keyed 6 Sep slid to Monday 31 Aug, stranding its
  ticks in the previous week and leaving an emptied row behind. A week keyed
  K covers K..K+6, so it is re-homed to the new-residue window holding its
  midpoint, `week_key_for(K + 3)`. Meals still go by their own date. The
  round trip is exactly lossless (a full state snapshot is asserted equal
  after Monday → Sunday → Monday) and the unique index needs no ordering
  argument: every off-residue key moves by at most three days and only ever
  collides with a genuine duplicate window, the offline orphan.
- 2026-09-12 — **The component batch sheet keeps its optional switch.** The
  ruling named the quantity sheet, whose switch was a one-argument removal;
  the component sheet returns a non-null flag through four callers. Both
  doors write the same fact. Recorded as the one `differs:` line on the
  editor's component frame.
- 2026-09-12 — **The cook plan's derivation is unchanged.** The cook day is
  the earliest covered offset of the window; under a Sunday-first week a
  Sunday meal can head a batch instead of always being Monday's tail, which
  removes the case that made the tech-debt row's default wrong most often.

## Notes / open questions

- The optional toggle's geometry is the detail most likely to want the
  owner's eye on the real screen rather than the board.
- Pruning a long ingredient list is now open-then-bin per line; if that bites
  in the field, the cheap answer is a bin on the row in a tidying posture,
  not two bins now.
- The re-home carries a Sunday-only recipe's variant to its new week; a
  recipe with meals on both sides of the boundary legitimately ends with a
  variant in each.
- Three integration files were edited for the new line and the shape
  (`recipe_editor_test.dart`, `week_test.dart`, `week_variant_test.dart`) and
  not run: the simulator is on hold while the owner tests.

## Step-done checklist

- [x] Roadmap row updated.
- [x] `ARCHITECTURE.md`'s standing table checked for the areas touched.
- [x] `app/AGENTS.md` "Current focus" and command list still true.
- [x] `make test-sim`: the three edited scenarios green, recorded above.
- [x] Tech-debt: the cook_plan row narrowed by the week-app lane; no corner
      cut without a row.
- [x] Migration 0043 on cloud; `docs/cloud-setup.md` ledger entry written.
- [x] `make ci` green on the assembled branch; origin's app run on main was
      red for a pre-existing reason (tests reading the local-only corpus),
      fixed in two follow-up commits.
