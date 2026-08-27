# Exec plan: Week planning

- **Status:** done
- **Owner:** Simon (+ agent)
- **Roadmap step:** Step 4 — week planning
- **Created:** 2026-08-27

## Goal

A second core screen: the **Week**. A single active week (the one containing
today, Monday-first) rendered as a seven-day grid. Under each day you add
meals — pick a recipe, a meal slot (Breakfast/Lunch/Dinner, or type your own),
and which household members are eating. Multiple entries per (day, slot) are
allowed. An empty week offers **Copy last week**, which clones the most recent
prior week's meals. This is the *input* to the derived cook-plan/shopping
pipeline (steps 5–6) — no batch/leftover thinking here. **Still local-only** —
no `.connect()` (sync is step 7).

## Acceptance criteria

- [x] `week_plan` + `plan_entry` tables (`0005_planning.sql`) with RLS / grants /
      publication mirroring 0004; `plan_entry` carries `eaters` (JSON array of
      member ids), `day_of_week`, free-text `meal_slot`, `sort_order`.
- [x] `schema.dart` mirrors 0005 (two synced tables) and adds `household_member`
      as a **local-only** table (bootstrap-seeded now; flips to synced in step 7,
      exactly like `ingredient`).
- [x] Planning domain is pure Dart (invariant 2): `Member`, `PlanEntry`,
      `WeekPlan`, `mondayOf`, meal-slot ordering.
- [x] Week screen: seven-day grid of day cards; each entry shows slot · recipe ·
      eater avatars; add a meal (day + slot + eaters + recipe); remove a meal;
      edit who's eating; empty-week state with "Copy last week" + last-week
      reference (design board).
- [x] Two household members auto-seeded on first run (idempotent), so eaters
      default to the whole household.
- [x] Reachable via a bottom nav (Library · Week · Cook · Shop) — see the
      decision-log revision below; replaced the first cut's top-right icon.
- [x] Tests: repository CRUD + copy-last-week + `mondayOf`; widget tests for the
      grid, empty state, and copy affordance. Add-meal driven end-to-end on the
      simulator (recorded below).
- [x] Docs updated: roadmap, planning README, QUALITY, this log. `make ci` green.

## Approach

Dependency order, mirroring the step-2/3 slice structure:

1. **Migration `0005_planning.sql`** — `week_plan`, `plan_entry` (+ indexes, RLS,
   grants, publication). `household_member` already exists (0001).
2. **`schema.dart`** — `week_plan` + `plan_entry` synced tables; `household_member`
   local-only.
3. **Planning domain** — entities + `PlanningRepository` interface + pure helpers
   (`mondayOf`, `mealSlotRank`).
4. **Planning data** — `SqlitePlanningRepository` (reactive `watchWeek` join;
   targeted view-safe writes; `copyLastWeek`; `ensureMembers`); providers.
5. **Presentation** — `WeekView` + view models; add-meal sheet; eater avatars.
6. **Wiring** — `/week` route; Library header entry point; `ensureMembers()` in
   `bootstrap.dart`.
7. **Docs.**

## Decision log

- 2026-08-27 — **Eaters stored as a JSON array column on `plan_entry`** (like
  `recipe.steps`), not a join table. Demand = `|eaters|`. Two trusted users, and
  spec §3 explicitly allows last-write-wins on field edits; a per-entry eater
  set is a field, not an independently-unioned row. Revisit only if multi-user
  concurrent eater edits become real.
- 2026-08-27 — **`household_member` is local-only in `schema.dart`, seeded in
  bootstrap** (two members: "Ada", "Jun" from the design board). The 0001 table
  has `auth_user_id NOT NULL → auth.users`, so it cannot be server-seeded before
  auth exists; local rows carry no auth id and never upload. Step 7 flips it to
  synced (real members) and drops the seeder — the exact `ingredient` playbook.
- 2026-08-27 — **Members live in the planning feature** (its only consumer).
  Not worth a `household` feature folder before step 7 restructures auth.
- 2026-08-27 — **Active week = the week containing today, Monday-first**
  (`mondayOf(now)`); no calendar/week-picker. Past weeks are just older
  `week_plan` rows, reachable only through "Copy last week". Matches spec §4
  ("one active week; past weeks archived → copy last week").
- 2026-08-27 — **Meal slots are free text** with three offered defaults
  (Breakfast/Lunch/Dinner). Entries within a day sort by slot rank (known slots
  first, in meal order) then `sort_order`. Honours spec's "user-definable, not an
  enum".
- 2026-08-27 — **Entry point via the Library header, not a bottom nav.** The
  design board's Library/Week/Cook/Shop bottom nav needs Cook + Shop to exist;
  the nav shell lands with step 6. Until then Week is a pushed route.
- 2026-08-27 — **Revised on review: shipped the bottom nav now.** Simon asked
  for the design board's bottom bar rather than a top-right icon. Added a shared
  `shared/mise_bottom_nav.dart` (`MiseBottomNav`) used as the `FScaffold.footer`
  on both Library and Week; Cook/Shop render but are dimmed and inert until
  steps 5–6 (`onChange` ignores them). Tabs switch with `context.go` so roots
  replace rather than stack. Week is a tab now, so its header dropped the back
  button; "copy last week" moved to a header `⋯` menu (shown only when an
  earlier week exists). Labels are uppercase (LIBRARY/WEEK/COOK/SHOP) — matches
  the board and avoids colliding with the Library title in a widget test.
- 2026-08-27 — **Restyled the Week to the design board on review.** First cut
  was plain white rows with black serif names; the board has day *cards* (paper
  fill, hairline dividers), meal names in **herb-green semibold sans**, uppercase
  mono slot labels, and *overlapping* eater avatars coloured by roster position
  (Ada herb, Jun ink) with a white ring. Reworked `week_widgets.dart`
  (`EaterAvatarStack`, `memberColor`) and the day/entry rows accordingly.
- 2026-08-27 — **Verified end-to-end on the iOS Simulator** (real PowerSync
  views): members auto-seeded (Ada/Jun), add a meal (Thursday · Dinner · both
  eaters), live edit-eaters (dropped Jun → avatar cluster updated without a
  reload), bottom-nav tab switching (Library ↔ Week), and cold-relaunch
  persistence. This is the only layer exercising the view-only write path
  ([[mise-powersync-views-no-upsert]]) and provider lifecycle across the
  picker's async gaps ([[mise-riverpod-notifier-ref-after-async]]).
- 2026-08-27 — **Add-flow redesign to Simon's mockup (second review).** Simon
  supplied a three-panel mockup: week grid → recipe picker → confirm & place.
  Reworked the flow:
  - **Two steps, not one.** A day's dashed "+ Add a meal" opens a recipe picker
    sheet (`recipe_picker_sheet.dart`: search, Recent/Books tabs, book·section
    subtitles from `libraryProvider`, a placeholder thumbnail since photos need
    Storage, "+ new recipe" → the editor), then a confirm sheet
    (`confirm_meal_sheet.dart`: slot pills, who's-eating, portions stepper,
    "Add to <Day>"). `week_view.dart` orchestrates the two.
  - **Portions.** Added `plan_entry.portions` (nullable) + `schema.dart` mirror,
    resolving spec §8's `portions_override`: null tracks |eaters|, a number
    overrides. `PlanEntry.portionsOrDefault` is the single read point.
  - **Slot grouping.** Same-slot dishes on a day sit under one slot label,
    grouped from the already-slot-sorted list.
  - **Shared/Per-person lens** (previously deferred, now built): a toggle + eater
    chips filter the week to one person; shared meals (>1 eater) show a "⇄
    shared" tag instead of the avatar cluster. `WeekView` became a
    `HookConsumerWidget` for the screen-local lens state.
  - **Dashed add buttons.** Extracted the Library's dashed box to
    `shared/dashed_border_box.dart`; reused for "+ Add a meal".
  - **"Already this week" surfacing** (the cheap half of batch-awareness) is in;
    the shelf-life chips + the "same batch" hint were **scoped to step 5** on
    Simon's call (they need shelf-life inputs + cook-plan clustering).
- 2026-08-27 — **Verified the redesigned flow on the sim** (real PowerSync
  views): picker → confirm → Wednesday · Dinner · Curry with an A+J cluster and
  a bumped 3-portion override; the Per-person lens filtered Ada-only Thursday out
  of Jun's view and tagged the shared Wednesday meal.

## Notes / open questions

- `portions_override` (spec §8) is **resolved** — `plan_entry.portions` (null
  tracks |eaters|). Per-person lens is **built** (was deferred, then requested).
- The mockup's **batch-awareness** (shelf-life "keeps N d" chips + the "same
  batch" hint) is scoped to **step 5** — it needs recipe shelf-life inputs
  (deferred there) and the cook-plan clustering rule.

## Step-done checklist

- [x] Roadmap row updated: status flipped, one line on what shipped + deferred.
- [x] `docs/QUALITY.md` grade for planning updated.
- [x] `app/AGENTS.md` still true (no "current focus" block to update).
- [x] Simulator run recorded (see the decision log). `app_test.dart` now smokes
      the two-step add flow end-to-end (Week tab → picker → confirm → portions →
      grid row + a `plan_entry` DB assert); it caught a global-`router` test-
      isolation bug (a stale recipe route bled into the next test). Per-person
      lens / edit-eaters / copy-last-week stay sim-manual (tech-debt row).
- [x] Tech-debt rows added for corners cut.
- [x] `make ci` green.
