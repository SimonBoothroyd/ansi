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
  nudged to a whole batch (whole-ingredient scaling is deferred).
- A recipe with no `keeps_for_days` (unknown shelf life) is never split.

`batchHintFor` reuses `clusterSessions` so the planner's "same batch" hint on the
add-a-meal flow can never disagree with the cook plan.

## Deferred

- **Whole-ingredient scaling** (spec §4) — shown as the raw factor for now.
- **Interactive cook-day adjustment** — display-only; making it movable needs a
  persisted override (the plan is otherwise purely derived).
- Both are stretch. The plan stays local-only until sync (step 7).
