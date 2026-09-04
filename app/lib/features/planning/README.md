# Feature: planning

**Roadmap:** Step 4 — week planning (see `docs/exec-plans/roadmap.md`,
[exec plan](../../../../docs/exec-plans/completed/0005-week-planning.md)).

Single active week; multiple entries per (day, slot); per-meal eaters;
copy-last-week. The INPUT to the derived cook-plan / shopping pipeline (steps
5–6) — you say *what you want to eat*, nothing about batching or leftovers.

## What's here

```
planning/
  domain/         planning.dart (Member, PlanEntry, WeekPlan, mondayOf,
                  mealSlotRank) + planning_repository.dart — PURE DART
  data/           SqlitePlanningRepository over the local PowerSync views;
                  providers
  presentation/   WeekView (day-card grid; ONE state since v3 — the mode is
                  gone; an empty week is a STATE of it, not a page),
                  week_header (the week switcher and its returns),
                  recipe_picker_sheet + confirm_meal_sheet (the two-step add
                  flow), entry_sheet (what a row opens in edit mode),
                  meal_fields (the controls both sheets share),
                  household_sheet (the members' usual portions, off the
                  Library ⋯ — plan 0027 P-D3),
                  week_widgets (Pill, EaterAvatar, EaterAvatarStack,
                  PortionsChip, CookMarkerLine), week_format
```

## The add flow (two steps)

Tapping a day's dashed "+ Add a meal" runs `_addMealFlow` in `week_view.dart`:

1. **`showRecipePickerSheet`** — search, Recent/Books tabs, book·section
   subtitles (from the books `libraryProvider`), and dishes "already this week"
   surfaced as quick picks. Returns the chosen `RecipeSummary`.
2. **`showConfirmMealSheet`** — slot pills, who's-eating, and a **portions**
   stepper (`plan_entry.portions`, null = track |eaters|, spec §8). Writes the
   entry.

The picker/confirm rows show the shelf-life chips ("keeps N d · freezable"),
and the confirm sheet surfaces a **"same batch" hint** when the new meal would
cook alongside one already on the week — both landed in step 5 (they reuse the
cook plan's `batchHintFor`/`clusterSessions`).

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
