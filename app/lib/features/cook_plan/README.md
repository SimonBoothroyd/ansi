# Feature: cook_plan

**Roadmap:** Step 5 — batch cook plan (derived) (see `docs/exec-plans/roadmap.md`,
[exec plan](../../../../docs/exec-plans/completed/0006-batch-cook-plan.md)).

The **Cook** screen: the derived counterpart to the Week. It groups the active
week's meals by recipe and splits each into **cook sessions** bounded by shelf
life (spec §4). Nothing here is planned; edit the Week and this re-derives.
Cook asks nothing: a cooked batch's card says what it left in one line and
opens **Leftovers**.

**Leftovers** (`/leftovers`) is this feature's one writing page: the
household's **fridge and freezer**, the derived batches merged with the
`leftover` rows it has stored (`householdLeftovers`, below), put right with a
stepper, Freeze, Froze it, Gone, Clear all and *Add a leftover*. Its door is
the fridge in the Week header. The planning picker's *Use up* offers its rows
back.

## Layout

```
cook_plan/
  domain/         PURE DART (no package:flutter)
    cook_plan.dart              CoveredMeal · PlannedRecipe · CookSession ·
                                RecipeCookPlan · CookPlan; clusterSessions +
                                buildCookPlan + batchHintFor
    leftovers.dart              BatchLeftover, wasCooked, useByOf,
                                batchLeftovers; StoredLeftover, Leftover,
                                householdLeftovers, leftoverWeekStarts
    cook_plan_repository.dart   the plan (read only)
    leftover_repository.dart    the shelves, and every write to them
  data/           SqliteCookPlanRepository (watch → buildCookPlan, and
                  loadCookPlan, read once); SqliteLeftoverRepository; providers
  presentation/   CookView (each session draws the compact week strip,
                  shared/week_strip.dart) + CookSheet; cook_format.dart (copy
                  + strip geometry, pure Dart); cook_view_models.dart;
                  batch_leftover_line.dart (a batch card's one line);
                  leftovers_view.dart (the page, its rows, Add a leftover,
                  and LeftoversDoor); leftovers_view_models.dart;
                  leftover_format.dart (`1¾ · until Mon`, pure Dart)
```

## The clustering rule (spec §4)

Greedy, per recipe (`clusterSessions`): sort the days a dish appears; start a
session at the first; fold each later meal in while it stays within the fridge
window (`keeps_for_days`). A meal past the window folds in anyway as a **frozen**
share when the recipe is `freezable` and the meal is within `freezer_days`
(null = no limit); otherwise it opens a new session. O(n·log n).

- The **cook day** is the earliest covered day (display-only this step).
- The **scale factor** is the raw `total_portions / servings_base` — honest, not
  rounded to a whole batch (whole-ingredient scaling is deferred); the
  session's exact-or-whole switch is display only. Since plan
  0027 `total_portions` is a double: a meal's demand is Σ of its eaters'
  portion factors (`1¾` for a 1 and a ¾ eater), the batch math was already
  fractional, and every count is printed as a fraction (`core/units/
  portions.dart`), the whole-batch switch's spare portions included.
- A recipe with no `keeps_for_days` (unknown shelf life) is never split.

`batchHintFor` reuses `clusterSessions` so the planner's "same batch" hint on the
add-a-meal flow can never disagree with the cook plan.

## The fridge and the freezer

`householdLeftovers` is the one seam (pure) that says what cooked food the
household has, on a day:

- **Derived rows** are the cooked batches of the last four weeks
  (`kLeftoverHorizon`, `leftoverWeekStarts`), each from `batchLeftovers`:
  fridge rows dated by `useByOf`. A batch an older build's Cook was told was
  binned or eaten (`batch_leftover`, which takes no new writes) reads as
  gone.
- **Stored rows** (`leftover`) are what was said: a correction, a freeze, a
  dish the app never saw. A row with a `batch` replaces that batch's derived
  row, gone or not; two rows for one batch read as the newest `updated_at`.
  A fridge row is good until `since` + `keeps_for_days`, a freezer row until
  `since` + `freezer_days` (null: no limit). A row in words, or for a recipe
  with no stated shelf life, has no date.
- **Each row's portions fall by the meals planned from it**: `leftover_of`
  for a derived batch, `from_leftover` for a stored row (summed across a
  batch's duplicates). A row with nothing left is not shown. `planned` is
  the part of those meals still to come, which the page prints beside the
  count (`2 · 2 planned`).
- **Nothing clears itself.** A row stays until `gone_at`; `pastItsDate`
  says when it is behind its date, and `isGoodOn` which days *Use up* may
  offer it for (a fridge row from its cook day to its date, a freezer row on
  any day).

### The writes

Every write names a `Leftover` as the page drew it
(`LeftoverRepository`). A derived row has no stored row yet: the first write
about it stores one at the count it showed, naming its `batch`, and a later
write finds that row (the newest live one for the batch) rather than storing
another. Local tables are views, so each is a SELECT then an INSERT or
UPDATE.

- **The stepper** stores the count it is set to **plus** the meals already
  planned from the row (`from_leftover`, across the batch's duplicates),
  because a stored row's portions are counted before them.
- **Freeze** sets `place = freezer` and `since` to today; **Froze it** to the
  row's fridge date. **Gone** and **Clear all** set `gone_at`.
- **Add a leftover** inserts a row with no `batch`: a recipe or the
  household's words, either place, `since` from the chip (today, 7 or 14
  days back).
- A refused upload names the row by its dish or words and opens
  `/leftovers` (`shared/dropped_write_subject.dart`).

A meal from either kind is never cooked again: the cook plan's query reads
`leftover_of IS NULL AND from_leftover IS NULL`, as the shop's does, and
`test/structure/leftover_meal_seam_test.dart` holds every such pass to both
columns.

## Nested recipes, for one week

A planned recipe's **component** lines derive sessions of their own, scaled in
batches (`expandComponentDemands`; the math lives in
`recipes/domain/component_math.dart`). The household's graph is read whole
(`loadComponentGraph`) and then filtered for the week on screen
(`componentGraphForWeek`): every recipe's component lines go through the
`effectiveLines` seam with that week's overrides before a single demand is
derived, so an **optional sub-recipe is cooked only when the week ticks it in**,
one the week excluded is not cooked at all, and a replaced line is cooked at the
week's amount. The shop runs the same filter over the same graph, and the watch
query joins `week_recipe_line_override` so ticking a line in re-derives the
plan. A component the batch math cannot resolve stays a named `ComponentGap` —
never a `1×` assumption. Each demanding source carries the line that names the
sub-recipe (`lineId`) and, below depth one, the recipe holding it (`via`,
`viaRecipeId`), so the card's **Fix the line in {parent} ›** opens that line in
that recipe's editor (`?line=`) and **Set the yield ›** opens the sub-recipe at
MAKES (`?focus=makes`), both through `gapFixes`. A line a week added (its id is
the override row's) is not in the recipe's editor, which then opens at the top.

**A line said in one of the target's own measures flows through this graph with
its pointer**
([ADR-0018](../../../../docs/decisions/0018-a-recipe-measure-is-a-named-amount.md)).
`loadComponentGraph` carries every recipe's
live words beside its yields (`loadRecipeMeasures`, one query keyed by recipe
id), and the watch joins `recipe_measure`, so re-stating a word re-derives the
plan. The loader's `unit == null` branch is measure-aware: it skips a line only
when it says **neither** a unit nor a word, because a measured line dropped there
is a whole sauce gone from the plan and the shop in silence. A word the target no
longer has is a named `ComponentMeasureMissing` gap whose demanding source keeps
the number and says `saysAMeasure` — never re-read as a count of the yield.

## Deferred

- **Whole-ingredient scaling** (spec §4) — shown as the raw factor for now.
- **Interactive cook-day adjustment** — display-only; making it movable needs a
  persisted override (the plan is otherwise purely derived).
- Both are stretch.
