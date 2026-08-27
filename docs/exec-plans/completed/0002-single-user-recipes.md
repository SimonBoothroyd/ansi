# Exec plan: Single-user recipes

- **Status:** done
- **Owner:** Simon (+ agent)
- **Roadmap step:** Step 2 — single-user recipes
- **Created:** 2026-08-26

## Goal

A running app (no longer a scaffold) where you can create a recipe, group its
ingredients ("for the sauce"), attach ingredients from the seeded vocabulary,
write a method, and view a clean recipe page whose quantities scale live with a
servings control. Everything persists on-device across restarts. **No backend
connection** — this step is offline/local-only; sync (step 7) is untouched.

## Non-goals (explicitly deferred)

- **No PowerSync `.connect()`** — no connector, no dev Supabase session, no
  `household_id` JWT claim. Local-only mode; step 7 adds exactly one thing.
- **No cook mode** (full-screen stepper/timers). Method is a plain ordered list.
- **No ingredients feature** — no "create new ingredient", no stub queue. Recipe
  line-items pick from the seeded vocab via an inline picker inside `recipes/`.
- **No books/sections** (step 3), **no whole-ingredient scaling** (step 5),
  **no computed macros in UI** (step 9), **no recipe photos** (needs Storage/auth).
- **No real auth** — reuse the fixed dev household `…0000000000aa` from `seed.sql`.

## Acceptance criteria

- [x] App boots into a real `MaterialApp.router` + go_router; scaffold placeholder gone.
- [x] Recipe list → recipe page → editor navigation works.
- [x] Create/edit a recipe: title, base servings, ≥1 ingredient group, line-items
      (ingredient + quantity + unit), method steps. Persists across app restart.
- [x] Inline ingredient picker searches the local seeded vocab (exact/prefix).
- [x] Recipe page scales quantities live by servings; imprecise units unchanged.
- [x] Domain (entities, scaling) is pure Dart — no `package:flutter` import.
- [x] Tests cover scaling + repository CRUD; widget tests render every screen (33 total).
- [x] Docs updated: roadmap status, recipes + ingredients READMEs, this decision log.
- [x] `make ci` and `make docs-check` green (analyze, format, flutter+deno tests, docs).

Frontend built entirely in **Forui** (no Material widgets bar the
`MaterialApp.router` host). One follow-up remains for full design fidelity: the
actual Spectral / Inter / IBM Plex Mono faces aren't bundled yet, so type falls
back to generic serif/sans/mono families (hierarchy matches; exact faces don't).

## Approach

Dependency order; each block lands with its tests before the next.

1. **App shell.** `bootstrap.dart` opens the local DB (block 2) and passes it as a
   ProviderScope override; `app.dart` → `MaterialApp.router` with the Forui theme
   from `core/theme/` and the go_router from `core/router/`. First route = recipe list.
2. **Local persistence (no connect).** Declare recipe + ingredient tables in
   `core/sync/schema.dart` (mirrors migration 0003 + 0002). Open
   `PowerSyncDatabase(schema:)` in `database.dart`, expose it + query-stream
   providers. **Never call `.connect()`** — writes/reads stay local.
3. **Recipe migration `0003_recipes.sql`.** `recipe`, `ingredient_group`,
   `recipe_line_item` (see schema below). Full RLS + grants + publication +
   sync-rules bucket entries per `docs/SECURITY.md` — authored now so step 7 is a
   no-op, even though nothing connects yet. Keeps Postgres and `schema.dart` in lockstep.
4. **Bundled vocab loader.** Extend `gen_seed.ts` to also emit
   `app/assets/seed/ingredients.json` (generated from `vocab.jsonl`, never
   hand-edited). On first run, if the local `ingredient` table is empty, load it
   (assign local uuids). Idempotent; gated to "empty only" so step-7 sync supersedes it.
5. **Recipe domain (pure Dart).** Freezed `Recipe`, `IngredientGroup`, `LineItem`;
   a `RecipeRepository` interface; `scaleLineItem(base, factor)` using `core/units`
   (imprecise → unchanged). Unit tests for scaling edge cases.
6. **Recipe data.** `RecipeRepository` impl over the local DB — reactive `watch`
   queries for list/detail, transactional writes for create/edit, DTO↔entity
   mapping. Repository tests against an in-memory/local PowerSync DB.
7. **Presentation (Views + Riverpod ViewModels).** Recipe list, recipe page
   (grouped line-items + method + servings scaler), editor (add/reorder groups &
   line-items, inline ingredient picker). Widget test: create → appears → scales.
8. **Docs.** Update roadmap step-2 status, `features/recipes/README.md` layout,
   and this decision log. Note in roadmap that step 7 still owns the connector.

## Proposed schema (migration 0003)

- `recipe`: `id · household_id · title · servings_base · steps jsonb (ordered text[])
  · keeps_for_days int? · freezable bool default false · freezer_days int? · timestamps · deleted_at`
  - shelf-life columns land now (spec attaches them to Recipe) so step 5 doesn't churn schema; no UI yet.
  - `book_id`/`section` deferred to step 3 (books table doesn't exist) — added then, avoiding a dangling FK.
- `ingredient_group`: `id · household_id · recipe_id (fk, on delete cascade) · name text? · sort_order int · timestamps · deleted_at`
- `recipe_line_item`: `id · household_id · group_id (fk, on delete cascade) · ingredient_id (fk → ingredient) · quantity numeric? · unit text (units.dart id) · note text? · sort_order int · timestamps · deleted_at`
  - `quantity` nullable so imprecise units ("to taste") carry no number.

Groups and line-items are separate rows (not nested JSON) to match the spec §3
conflict model (independent adds union) and give stable `sort_order` under sync.

## Decision log

- 2026-08-26 — **Persistence: PowerSync local-only, not full wiring.** Open the
  local DB, skip `.connect()`. Same schema/repo/watch code step 7 uses → zero
  app-side throwaway; defers connector + dev session + JWT `household_id` claim.
  (Reversed the earlier "wire it fully" call after weighing the step-7 pull-in.)
- 2026-08-26 — **Ingredient vocab via bundled generated asset**, since nothing
  syncs. One net-new shim; generated from `vocab.jsonl` (no hand-drift), gated to
  load only when the table is empty so sync supersedes it later.
- 2026-08-26 — **Reuse fixed dev household `…0000000000aa`** already in `seed.sql`.
- 2026-08-26 — **Inline picker inside `recipes/`, no ingredients feature.** Search
  over the local vocab only; create-new/stub queue deferred to its own slice.
- 2026-08-26 — **Method as ordered text, no cook mode.** Matches spec §4.
- 2026-08-26 — Author 0003 RLS/grants/publication/sync-rules now despite no
  connection, so step 7 adds only `.connect()`.
- 2026-08-26 — **Frontend is Forui components only, not Material** (ADR-0002).
  An initial Material-widget pass was scrapped: the point is to write the real
  UI now, not scaffolding that's instantly replaced. `mise_theme.dart` builds a
  real `FThemeData` from the Mise tokens; screens use FScaffold/FButton/etc.
  `MaterialApp.router` stays only as the go_router host, wrapped in `FTheme`.
- 2026-08-26 — Minimal read-only ingredient model lives under
  `features/ingredients/domain` (not crammed into `recipes/`); the deferred part
  is the create/stub/queue *feature*, not the entity the picker needs.
- 2026-08-26 — **Real fonts bundled** (Spectral, IBM Plex Mono; Inter reused from
  Forui) so the type roles render as designed, offline. See `assets/fonts/`.
- 2026-08-26 — **`saveRecipe` UPSERT bug fixed.** PowerSync's local tables are
  SQLite views that reject `INSERT ... ON CONFLICT` and subquery DELETEs; now an
  exists→INSERT/UPDATE branch with subquery-free child deletes. The plain-sqlite
  repo tests could not catch this (real tables allow UPSERT) — verified instead
  by running the app on the sim. See [[mise-powersync-views-no-upsert]].
- 2026-08-26 — **Verified end-to-end on the iOS Simulator** (real PowerSync):
  create → cold-relaunch → reopen → live scaling → delete all work. `web` also
  runs (`kIsWeb` db-path branch). iOS builds via Swift Package Manager (no Pods).

## Deferred within recipes (implemented later, not bugs)

- **Shelf-life inputs** (`keeps_for_days`, `freezable`, `freezer_days`): DB
  columns exist and the recipe page renders chips when set, but there is **no
  editor input** — deferred to step 5 (cook plan), which is what makes those
  values load-bearing. Until then the chips only show `serves N`.
- **Macros row** (mockup shows kcal/protein/carb/fat): step 9. Blocked on data —
  the seeded vocab is all `stub` with null macros (honest numbers; never
  invented), so totals need completed ingredients first.
- **Cook mode**, inline method ingredient chips, timer pills, **Notes tab**,
  **books/sections** (step 3), **recipe photos** (needs Storage/auth).
- **Ingredient create / stub / fleshing-out queue** — only read-only vocab search
  is built (the inline picker).

## Resolved during the design-fidelity pass

- Real fonts (Spectral, IBM Plex Mono; Inter via Forui) now render — the fix was
  setting `fontFamily` explicitly (a fallback-only family lost to Forui's ambient
  Inter in the style merge).
- Underline tabs, white background, ⋯ overflow menu, tighter ingredient density,
  mono ink quantities, method dividers — all matched to the mockup on the sim.
- `saveRecipe` UPSERT-on-a-view bug fixed (see decision log).

## Carried to the tech-debt tracker

- Repo tests run on plain SQLite (real tables), so PowerSync-view-only failures
  slip through. Two Forui workarounds (custom underline tabs, custom hairline).
  Post-save nav uses `go(recipe)` + a back fallback. See `tech-debt-tracker.md`.

## Notes / open questions

- Local uuids assigned at seed-load won't match server ids when sync lands; dev
  recipes created pre-sync reference local-only ingredient ids. Acceptable (dev
  data is throwaway); revisit at step 7 if we want deterministic (uuidv5) ids.
- Reorder UX for groups/line-items: drag vs up/down buttons — decide during block 7.
- Confirm Forui has the form primitives we need (number field, stepper) or wrap Material.
