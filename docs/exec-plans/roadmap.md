# Build sequence & status

Ordered per spec §7 (reordered around the meal-planning core). Each step lands
with tests before the next starts. Update the Status column as you go — this is
the roadmap agents and humans read first.

| # | Step | Where | Status |
|---|------|-------|--------|
| 1 | **Unit + ingredient data model** — families, conversions incl. density | `app/lib/core/units`, `supabase/migrations/0002` | 🟢 done — unit system (tested); data model (`0001`/`0002` + RLS); 291-ingredient household vocab (mined + curated, variety-level, canned/dried forms); `usda_food` reference (8262 foods, macros incl. fiber); prefill → 248 `complete`, 43 honest `stub`. Density still sparse (FAO/INFOODS fallback deferred) |
| 2 | Single-user recipes — create, group ingredients, scale, recipe page | `app/lib/features/recipes` | 🟢 done — Forui UI matching the design board (list · recipe page w/ live servings scaling · editor · inline vocab picker), real bundled fonts; `0003_recipes.sql` (recipe/group/line-item + RLS); local-only PowerSync persistence (no `.connect()` yet — step 7); bundled 291-ingredient vocab loader; verified end-to-end on the iOS sim. **Deferred:** shelf-life editor inputs (→ step 5), macros row (→ step 9), cook mode + inline method chips/timers, Notes tab, books/sections (→ step 3), recipe photos (needs Storage/auth) |
| 3 | Recipe books + user-defined sections | `app/lib/features/books` | 🟢 done — Library home screen (books → user-named sections → recipes, "Unsectioned" bucket); `0004_books.sql` (`book` + `book_section` tables, `recipe.book_id`/`section_id` + RLS); create/rename/reorder/delete sections, create books; recipe editor "file under" book+section picker; recipe hero "Book · Section" breadcrumb; default book auto-created on first run + adopts pre-step-3 recipes (empty-only gate); verified end-to-end on the iOS sim (create section, file recipe, cold-relaunch persistence — all against real PowerSync views). **Deferred:** multi-book many-to-many (spec §8 open question; v1 = one book/recipe); per-book detail screen (all books render inline for v1); still local-only (no `.connect()` — step 7) |
| 3.5 | **Test harness + doc hygiene** — repo tests on a real `PowerSyncDatabase` (view-backed, from `schema.dart`), enabled integration smoke behind `make test-sim`, step-done checklist, satellite-doc refresh | `app/test`, `app/integration_test`, `docs/` | 🟢 done — [exec plan](./completed/0004-test-harness-and-doc-hygiene.md). Repo tests open the real schema (host loads the PowerSync core extension via `make powersync-core`); regression test pins that the local tables stay views; the sim smoke drives create-section → create-recipe → file → breadcrumb. Found and fixed a live stale-breadcrumb bug: SQLite dropped the unused book/section LEFT JOINs, so `watchRecipe` never re-fired on a rename |
| 4 | Week planning — single-week grid, multiple entries/slot, eaters, copy-last-week | `app/lib/features/planning` | 🟢 done — [exec plan](./completed/0005-week-planning.md). Week screen (active week = the Monday-first week containing today; seven-day grid of day cards; meals grouped by slot; **Shared/Per-person lens**; blank-week state with "copy last week" + last-week reference). **Two-step add flow** matching the mockup: a recipe picker (search · Recent/Books · "already this week" surfacing · book·section subtitles · "+ new recipe") → a confirm sheet (slot · eaters · **portions stepper**). `0005_planning.sql` (`week_plan` + `plan_entry`, `eaters` JSON array, free-text `meal_slot`, `portions` override resolving spec §8, RLS); `household_member` seeded as a local-only table (two members "Ada"/"Jun" — real table's `auth_user_id` FK blocks server-seeding until step 7); a bottom nav (Library · Week · Cook · Shop — Cook/Shop inert until steps 5–6) in a shared `MiseBottomNav`. Verified end-to-end on the iOS sim (two-step add + portions, per-person filtering, edit eaters live, tab nav, cold-relaunch persistence — against real PowerSync views). **Deferred to step 5:** the batch-aware shelf-life chips + the "same batch" hint (need shelf-life inputs + clustering); still local-only (no `.connect()` — step 7) |
| 5 | Batch cook plan — aggregate by recipe, shelf-life clustering, adjustable cook day | `app/lib/features/cook_plan` | 🟢 done — [exec plan](./completed/0006-batch-cook-plan.md). The **Cook** screen (third live tab): the derived batch view — the week's meals grouped by recipe, each greedily clustered into **cook sessions** bounded by fridge shelf life (`keeps_for_days`), with a **freezer merge** (a freezable dish's far instance folds into one session — cook once, freeze the far share — rather than splitting). Each session shows cook day · honest scale (`portions/servings`) · "covers…" · a fresh→gone timeline; split + freezer notes explain the why. Pure-Dart `buildCookPlan`/`clusterSessions` (fully unit-tested); `CookPlanRepository` re-derives on any plan/recipe change (no new tables — the plan is derived). Added the **recipe-editor shelf-life inputs** (keeps/freezable/freezer-days), making those step-2 columns load-bearing. Lit up the **planning add-flow batch chips** owed from step 4: "keeps N d" on picker/confirm + a "same batch" hint (reuses `batchHintFor`→`clusterSessions`). Verified end-to-end on the iOS sim. **Deferred:** whole-ingredient scaling nudge (raw factor for now) + interactive cook-day adjustment (display-only; needs a persisted override) — both stretch; still local-only (no `.connect()` — step 7) |
| 6 | Shopping list from cook plan — contributions, aggregation, provenance, check-off | `app/lib/features/shopping` | ⚪ not started |
| 7 | Sync layer — PowerSync + household + offline queue (parallel once 1–6 schema stabilises) | `app/lib/core/sync`, `docker/` | 🟡 scaffolded: schema/connector stubs in place |
| 8 | AI/deterministic import — JSON-LD → photo → reconciliation → stub queue | `supabase/functions`, `app/lib/features/import` | 🟡 normalization (§7) implemented + eval-scored; cascade/extraction still stubbed |
| 9 | Computed macros in UI (stretch) | `app/lib/features/recipes` | ⚪ stretch — deferred from step 2 (mockup shows a macro row). Macros **do** exist server-side: the Postgres seed is 248 `complete` / 43 `stub` after prefill. What the app ships with is the bundled `assets/seed/vocab.jsonl` (loaded by `vocab_seeder.dart`), which carries no macros — so totals stay unavailable on-device until step 7 sync lands, or the bundle is deliberately enriched. Either way the "incomplete when stubs present" treatment is part of this step (honest numbers — never invented) |
| 10 | Web UI (stretch; near-free with Flutter) | `app/web` | ⚪ stretch |
| 11 | Anti-waste extras (stretch) — freezer batching, monotony warnings, package-size flags | — | ⚪ stretch |

Legend: ⚪ not started · 🟡 scaffolded/in progress · 🟢 done

## Why this order

The unit system underpins recipes, scaling, cook-plan scaling, and shopping-list
aggregation — nothing works until conversions are trustworthy, so it is built
first and hardened with tests. Import (step 8) is deliberately late: it depends
on a stable ingredient vocabulary to match against.

## Open questions (spec §8, low priority)

- ~~Per-entry `portions_override` for big/small appetites, or `|eaters|` only?~~
  **Resolved (step 4):** `plan_entry.portions` — null tracks `|eaters|`, a number
  overrides (the confirm sheet's stepper).
- Can a recipe belong to multiple books? (v1 assumes one.)
- ~~Meal slots: fixed set or user-definable?~~ **Resolved (step 4):** free-text
  slots with Breakfast/Lunch/Dinner offered as defaults (`mealSlotRank` orders
  known slots ahead of custom ones).
- ~~Freezer-aware batching in v1 or stretch?~~ **Resolved (step 5):** built in
  v1 — a freezable recipe's distant instance merges into one cook session
  (cook once, freeze the far share) rather than splitting.
