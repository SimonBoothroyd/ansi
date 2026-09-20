# Feature: cook_plan

**Roadmap:** Step 5 — batch cook plan (derived) (see `docs/exec-plans/roadmap.md`,
[exec plan](../../../../docs/exec-plans/completed/0006-batch-cook-plan.md)).

The **Cook** screen: the derived counterpart to the Week. It groups the active
week's meals by recipe and splits each into **cook sessions** bounded by shelf
life (spec §4). Read-only — nothing here is planned or persisted; edit the Week
and this re-derives.

## Layout

```
cook_plan/
  domain/         PURE DART (no package:flutter)
    cook_plan.dart              CoveredMeal · PlannedRecipe · CookSession ·
                                RecipeCookPlan · CookPlan; clusterSessions +
                                buildCookPlan + batchHintFor
    cook_plan_repository.dart   read-only contract
  data/           SqliteCookPlanRepository (watch → buildCookPlan) + providers
  presentation/   CookView + CookTimeline; cook_format.dart (copy + timeline
                  geometry, pure Dart); cook_view_models.dart
```

## The clustering rule (spec §4)

Greedy, per recipe (`clusterSessions`): sort the days a dish appears; start a
session at the first; fold each later meal in while it stays within the fridge
window (`keeps_for_days`). A meal past the window folds in anyway as a **frozen**
share when the recipe is `freezable` and the meal is within `freezer_days`
(null = no limit); otherwise it opens a new session. O(n·log n).

- The **cook day** is the earliest covered day (display-only this step).
- The **scale factor** is the raw `total_portions / servings_base` — honest, not
  nudged to a whole batch (whole-ingredient scaling is deferred). Since plan
  0027 `total_portions` is a double: a meal's demand is Σ of its eaters'
  portion factors (`1¾` for a 1 and a ¾ eater), the batch math was already
  fractional, and every count is printed as a fraction (`core/units/
  portions.dart`), the nudge's leftover included.
- A recipe with no `keeps_for_days` (unknown shelf life) is never split.

`batchHintFor` reuses `clusterSessions` so the planner's "same batch" hint on the
add-a-meal flow can never disagree with the cook plan.

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
never a `1×` assumption.

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
