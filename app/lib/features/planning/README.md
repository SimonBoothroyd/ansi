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
  presentation/   WeekView (day-card grid + Shared/Per-person lens),
                  recipe_picker_sheet + confirm_meal_sheet (the two-step add
                  flow), edit_eaters_dialog, week_widgets (Pill, EaterAvatar,
                  EaterAvatarStack), week_format
```

## The add flow (two steps)

Tapping a day's dashed "+ Add a meal" runs `_addMealFlow` in `week_view.dart`:

1. **`showRecipePickerSheet`** — search, Recent/Books tabs, book·section
   subtitles (from the books `libraryProvider`), and dishes "already this week"
   surfaced as quick picks. Returns the chosen `RecipeSummary`.
2. **`showConfirmMealSheet`** — slot pills, who's-eating, and a **portions**
   stepper (`plan_entry.portions`, null = track |eaters|, spec §8). Writes the
   entry.

The mockup's shelf-life chips + "same batch" hint are **step 5** (they need
recipe shelf-life data + cook-plan clustering).

## Model notes

- **Active week = the Monday-first week containing today** (`mondayOf(now)`);
  older `week_plan` rows are the past, reached only via "copy last week". No
  calendar (spec §4).
- **`plan_entry.eaters`** is a JSON array of `household_member` ids; demand for
  an entry = `|eaters|`. It's a field (last-write-wins, spec §3), not a join
  table.
- **Meal slots are free text** (spec §8). `kDefaultMealSlots` are the three the
  UI offers; `mealSlotRank` orders known slots ahead of custom ones per day.
- **Members** are seeded as a **local-only** `household_member` table (two
  members, `ensureMembers()` in `bootstrap.dart`) because the real 0001 table's
  `auth_user_id` FK can't exist before auth. Step 7 flips it to synced — the
  same playbook as `ingredient`. See [`schema.dart`](../../core/sync/schema.dart).

## Navigation

The Week is a bottom-nav tab (`shared/mise_bottom_nav.dart`), alongside Library.
Cook and Shop render but are inert until steps 5–6.

## Deferred

- Batch-awareness: the shelf-life "keeps N d" chips and the "same batch" hint
  from the mockup — **step 5** (needs shelf-life inputs + clustering).
- Recipe photos (picker/confirm thumbnails are placeholders) — needs Storage.
- Favorites tab in the picker — no favorite flag on `recipe` yet.
- Still local-only; nothing syncs until step 7.
