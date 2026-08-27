# Exec plan: Batch cook plan

- **Status:** done
- **Owner:** Simon (+ agent)
- **Roadmap step:** Step 5 — batch cook plan
- **Created:** 2026-08-27

## Goal

A third core screen: **Cook**. The derived counterpart to the Week. It groups
the active week's `plan_entry` rows **by recipe**, then splits each recipe into
**cook sessions** bounded by fridge shelf life (`keeps_for_days`), using a
greedy clustering rule (spec §4). A freezable recipe whose later instance falls
past the fridge window *merges* into one session (cook once, freeze the far
share) instead of splitting. Each session shows its cook day, the meals it
covers, total portions, the honest scale factor, and a fresh→gone timeline.
This is what makes the recipe shelf-life columns (present since step 2, no UI)
**load-bearing** — so this step also adds the shelf-life **editor inputs**.

Still local-only — no `.connect()` (sync is step 7). The cook plan is **purely
derived** from the week + recipe shelf-life: no new tables, nothing persisted.

## Acceptance criteria

- [ ] Recipe editor gains **shelf-life inputs**: `keeps_for_days` (nullable
      "keeps N days"), `freezable` (toggle), `freezer_days` (nullable, shown
      when freezable). Persisted through the existing `saveRecipe` columns.
- [ ] Cook-plan domain is pure Dart (invariant 2): entities +
      `buildCookPlan` / per-recipe greedy `clusterSessions` with the freezer
      merge; scale factor = `total_portions / servings_base` (raw, honest — no
      whole-ingredient nudge this step).
- [ ] Cook-plan data: `CookPlanRepository` watches `week_plan`/`plan_entry`/
      `recipe` and assembles the derived `CookPlan` (view-safe reads only).
- [ ] Cook screen matching the mockup / design board: recipe cards → session
      cards (cook day · scale · covers · timeline), split note (past-window) and
      freezer note (freezer rescue). Empty state when the week has no meals.
- [ ] `/cook` route; the Cook tab in `MiseBottomNav` goes live.
- [ ] Planning add-flow batch chips owed from step 4: "keeps N d" on picker
      rows + a "same batch" hint in the confirm sheet when the new meal lands in
      an existing session's window.
- [ ] Tests: domain clustering (fridge split, freezer merge, portions/scale,
      null shelf life); repo assembly on a real PowerSync db; a widget/screen
      smoke. `make test-sim` recorded.
- [ ] Docs updated: roadmap, cook_plan README, QUALITY, this log. `make ci`
      green.

## Approach

Dependency order, mirroring the step-2/3/4 slice structure:

1. **Recipe editor shelf-life inputs** — notifier setters
   (`setKeepsForDays`/`setFreezable`/`setFreezerDays`) + a "SHELF LIFE" form
   section. (Domain fields + persistence already exist from step 2.)
2. **Cook-plan domain** (`cook_plan/domain/cook_plan.dart`) — `CoveredMeal`,
   `PlannedRecipe`, `CookSession`, `RecipeCookPlan`, `CookPlan`; the pure
   `clusterSessions` (greedy fridge window + freezer merge) and `buildCookPlan`.
3. **Cook-plan data** — `CookPlanRepository` interface + `SqliteCookPlanRepository`
   (reactive `watchCookPlan`; view-safe joins) + providers.
4. **Presentation** — `CookView` + widgets (recipe card, session card, timeline,
   notes) + view models.
5. **Wiring** — `/cook` route; enable the Cook tab.
6. **Planning add-flow chips** — extend the picker read model with shelf life;
   the "same batch" hint in the confirm sheet.
7. **Tests + docs + sim run.**

## Decision log

- 2026-08-27 — **No new tables / migration.** The cook plan is derived from the
  week + recipe shelf-life; cook day is the earliest covered day (display-only
  this step); freezer merge is derived. Nothing is persisted, matching spec §4
  ("cook_session (derived)"). Revisit if cook-day adjustment becomes interactive.
- 2026-08-27 — **Scope confirmed with Simon:** freezer merge **built now**
  (mockup features it); cook day **display-only** (derived earliest day, handle
  is decorative); scale factor **raw/honest** (no whole-ingredient nudge — the
  "×0.75 → ×1" mockup nudge is deferred; densities are sparse and honesty wins).
- 2026-08-27 — **Sim review (Simon), two fixes.** (1) *Bar rendering:* the
  timeline track rendered as just the handle dot — a `Row` of `Expanded`
  segments inside a `Stack` collapses to zero width. Rewrote the track as a
  `CustomPainter` (`_TrackPainter`) that fills the row and draws the green
  fresh window + amber frozen tail / hatched gone tail + the cook handle. (2)
  *Missing glyphs:* the ❄ snowflake rendered as "?" in the bundled font (⚑
  happened to be present). Swapped the note/hint symbols to Lucide icons
  (`snowflake`, `flag`, `repeat`). Considered re-adding the scale nudge on the
  first review pass; Simon confirmed **raw scale only** stands — reverted it.
- 2026-08-27 — **Timeline redesign (Simon, 2nd sim pass).** Replaced the
  per-session span with a fixed **Mon→Sun axis** (`CookTimelineSpec` now exposes
  day coords + covered days, not flex weights): a neutral week bar, the green
  fresh window from the cook day, the tail, and a weekday-initial ruler with the
  eaten days emphasised. Every eaten day is a marker — the cook day a solid
  green pin, other eaten days open rings — which also fixed the handle/bar
  overlap (clean pins with a paper ring instead of a dot hanging off the edge).
- 2026-08-27 — **Frozen tail is blue, not amber (Simon).** Added
  `MiseColors.frozen` (a light, icy blue in the freezer-note hue) for the
  freezer segment — first a heavier steel blue, then lightened to feel
  "chillier" and tie to the note bubble on review. Amber is the
  freshness scale's *aging* colour — wrong for a frozen share (freezing pauses
  aging), and it now colour-matches the blue freezer note box. Amber stays only
  where it means a warning (the split card border + split note).
- 2026-08-27 — **Verified end-to-end on the iOS Simulator** (real PowerSync
  views): added shelf-life in the editor (keeps 3 d; a freezable Ragù with the
  freezer stepper) → persisted through the recipe page chips; the picker/confirm
  show the "keeps N d · freezable" chips; planning Curry Mon+Sat (keeps 3) split
  into two sessions with the fresh→gone bars + the flag note, while Ragù Tue+Sat
  merged into one `×2` session with the green→amber bar + the snowflake freezer
  note; the confirm sheet's "same batch" hint fired on the freezable Saturday
  add and (correctly) not on the non-freezable split. Cold-relaunch persisted.

## Notes / open questions

- Whole-ingredient scaling (spec §4, roadmap step title) is **deferred** — shown
  as the raw factor for now. Lives with the stretch anti-waste work / better
  density data.
- Cook-day adjustment (roadmap step title) is **display-only** this step; making
  it interactive needs a persisted override store (the cook plan is otherwise
  purely derived) — a later refinement.

## Step-done checklist

- [x] Roadmap row updated: status flipped, one line on shipped + deferred.
- [x] `docs/QUALITY.md` grade for cook_plan (and planning/recipes) updated.
- [x] `app/AGENTS.md` still true (no "current focus" block to update).
- [x] `make test-sim` green on the booted sim (existing integration smoke); the
      full Week → Cook flow driven manually and recorded in the decision log
      (a cook scenario for `app_test.dart` is a tech-debt row).
- [x] Tech-debt rows added (whole-ingredient scaling, cook-day adjustment,
      timeline heuristic, Week→Cook integration coverage); retired the
      shelf-life-editor + batch-chip debt this step paid off.
- [x] `make ci` green.
