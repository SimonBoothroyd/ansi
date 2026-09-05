# Feature: planning

**Roadmap:** Step 4 — week planning (see `docs/exec-plans/roadmap.md`,
[exec plan](../../../../docs/exec-plans/completed/0005-week-planning.md)).

Single active week; multiple entries per (day, slot); per-meal eaters;
copy-last-week. The INPUT to the derived cook-plan / shopping pipeline (steps
5–6) — you say *what you want to eat*, nothing about batching or leftovers.

A planned meal is a **recipe or a bare ingredient** — a protein bar, a yoghurt
— never both and never neither (`plan_entry_target_xor`, migration 0033). See
[The entry XOR](#the-entry-xor) below.

## What's here

```
planning/
  domain/         planning.dart (Member, PlanEntry, WeekPlan, mondayOf,
                  mealSlotRank), week_macros.dart (sumPlannedMacros +
                  ingredientPortionMacros) + planning_repository.dart
                  — PURE DART
  data/           SqlitePlanningRepository over the local PowerSync views;
                  providers
  presentation/   WeekView (day-card grid; ONE state since v3 — the mode is
                  gone; an empty week is a STATE of it, not a page),
                  week_header (the week switcher and its returns),
                  recipe_picker_sheet + confirm_meal_sheet (the add flow's ONE
                  door and its confirm), meal_editor_sheet (who's eating + portions,
                  opened by a row's avatar/portions cluster — v3 E7; it
                  replaced entry_sheet, which was a hub behind a mode),
                  meal_fields (the controls both sheets share),
                  household_section (the members' usual portions, a section
                  of /account — plan 0027 P-D3, moved there by 0028 E6),
                  week_widgets (Pill, EaterAvatar, EaterAvatarStack,
                  PortionsChip, CookMarkerLine), week_format
```

## The entry XOR

`plan_entry` names a `recipe_id` **or** an `ingredient_id`, enforced server-side
(migration 0033, the shape `recipe_line_item` has worn since 0017). Something
you simply *eat* is planned as itself rather than dressed up as a one-line
recipe.

- An **ingredient** entry states the amount of **one portion** —
  `quantity` + `unit`, or a `measure_id` ("1 bar") with `unit` holding the
  honest count fallback. The amount columns are refused on a recipe entry,
  whose amount is its `portions`.
- It **carries eaters and multiplies** like any other entry: the same `eaters`
  array, the same `portions` override, the same Σ-portion-factor demand. Two
  people having the same snack is two of them.
- Read `PlanEntry.isIngredient`, never a null `recipeId` by hand. **Every
  derivation branches explicitly**, and a null recipe never means "skip":
  - **week macros** weigh it from the nutrition the entry carries
    (`ingredientPortionMacros`), and name any refusal in a stub *line's* own
    words (`MealExclusion.ingredientNotCounted` + a `MacroLineReason`);
  - **the cook plan ignores it** — nothing about it is cooked, so it opens no
    session and joins no batch;
  - **the shopping list includes it**, which is why
    `SqliteShoppingRepository._derivePlannedIngredients` walks the week's
    ENTRIES beside the cook plan's sessions.

## The add flow

Tapping a day's dashed "+ Add a meal" runs `_addMealFlow` in `week_view.dart`:

1. **`showRecipePickerSheet`** — **one door for both kinds of thing**: search,
   Recent/Books tabs, book·section subtitles (from the books `libraryProvider`),
   dishes "already this week" as quick picks, and — once something is typed — an
   `INGREDIENTS` section over the household vocabulary, mirroring how the
   editor's `line_target_picker` gained "Your recipes". Returns a `PickedMeal`.
2. **The quantity sheet**, for an ingredient only: the shipped
   `showQuantityUnitSheet`, seeded from the row's stated `default_measure_id`
   so "1 bar" means a bar.
3. **`showConfirmMealSheet`** — slot pills, who's-eating, and a **portions**
   stepper (`plan_entry.portions`, null = track |eaters|, spec §8). It takes a
   `MealTarget` (`RecipeMeal` / `SnackMeal`) and writes the matching entry.

The picker/confirm rows show the shelf-life chips ("keeps N d · freezable"),
and the confirm sheet surfaces a **"same batch" hint** when the new meal would
cook alongside one already on the week — both landed in step 5 (they reuse the
cook plan's `batchHintFor`/`clusterSessions`). Neither appears on a snack: they
are facts about a cooked dish, and `MealSnackCard` prints its amount instead.

## Model notes

- **Active week = the Monday-first week containing today** (`mondayOf(now)`);
  older `week_plan` rows are the past, reached only via "copy last week". No
  calendar (spec §4).
- **`plan_entry.eaters`** is a JSON array of `household_member` ids; demand for
  an entry = Σ of the eaters' `portion_factor` (`demandPortions`, plan 0027
  P-D1 — `1¾` for a 1 and a ¾ eater, printed as a fraction through
  `core/units/portions.dart`, never rounded), unless the whole-number
  `portions` override is set. It's a field (last-write-wins, spec §3), not a
  join table.
- **Meal slots are free text** (spec §8). `kDefaultMealSlots` are the three the
  UI offers; `mealSlotRank` orders known slots ahead of custom ones per day.
- **Members** are **synced** from the server (step 7): `ensure_onboarded`
  (migration 0007) creates the `household_member` rows at sign-in and they stream
  down; the app reads them, and the one column it writes is `portion_factor`
  (plan 0027 P-D3: the Household sheet off the Library `⋯`, either member may
  set either's). (Pre-step-7 they were a local-only, `ensureMembers()`-seeded
  table.) See [`schema.dart`](../../core/sync/schema.dart).

## Navigation

The Week is a bottom-nav tab (`shared/ansi_bottom_nav.dart`), alongside Library,
Cook (step 5), and Shop (step 6) — all four tabs are live.

## Deferred

- Recipe photos (picker/confirm thumbnails are placeholders) — needs Storage.
- Favorites tab in the picker — no favorite flag on `recipe` yet.
- Syncs since step 7 (`week_plan`/`plan_entry` are synced, household-scoped).
