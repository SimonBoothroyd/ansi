# Build sequence & status

Ordered per spec §7 (reordered around the meal-planning core). Each step lands
with tests before the next starts. Update the Status column as you go — this is
the roadmap agents and humans read first.

| # | Step | Where | Status |
|---|------|-------|--------|
| 1 | **Unit + ingredient data model** — families, conversions incl. density | `app/lib/core/units`, `supabase/migrations/0002` | 🟢 done — unit system (tested); data model (`0001`/`0002` + RLS); 291-ingredient household vocab (mined + curated, variety-level, canned/dried forms); `usda_food` reference (8262 foods, macros incl. fiber); prefill → 248 `complete`, 43 honest `stub`. Density still sparse (FAO/INFOODS fallback deferred) |
| 2 | Single-user recipes — create, group ingredients, scale, recipe page | `app/lib/features/recipes` | 🟢 done — Forui UI matching the design board (list · recipe page w/ live servings scaling · editor · inline vocab picker), real bundled fonts; `0003_recipes.sql` (recipe/group/line-item + RLS); local-only PowerSync persistence (no `.connect()` yet — step 7); bundled 291-ingredient vocab loader; verified end-to-end on the iOS sim. **Deferred:** shelf-life editor inputs (→ step 5), macros row (→ step 9), cook mode + inline method chips/timers, Notes tab, books/sections (→ step 3), recipe photos (needs Storage/auth) |
| 3 | Recipe books + user-defined sections | `app/lib/features/books` | 🟢 done — Library home screen (books → user-named sections → recipes, "Unsectioned" bucket); `0004_books.sql` (`book` + `book_section` tables, `recipe.book_id`/`section_id` + RLS); create/rename/reorder/delete sections, create books; recipe editor "file under" book+section picker; recipe hero "Book · Section" breadcrumb; default book auto-created on first run + adopts pre-step-3 recipes (empty-only gate); verified end-to-end on the iOS sim (create section, file recipe, cold-relaunch persistence — all against real PowerSync views). **Deferred:** multi-book many-to-many (spec §8 open question; v1 = one book/recipe); per-book detail screen (all books render inline for v1); still local-only (no `.connect()` — step 7) |
| 4 | Week planning — single-week grid, multiple entries/slot, eaters, copy-last-week | `app/lib/features/planning` | ⚪ not started |
| 5 | Batch cook plan — aggregate by recipe, shelf-life clustering, adjustable cook day | `app/lib/features/cook_plan` | ⚪ not started — **carry-over from step 2:** `recipe.keeps_for_days`/`freezable`/`freezer_days` have DB columns + display chips but no editor input yet; add the inputs here (this step is what makes those values load-bearing) |
| 6 | Shopping list from cook plan — contributions, aggregation, provenance, check-off | `app/lib/features/shopping` | ⚪ not started |
| 7 | Sync layer — PowerSync + household + offline queue (parallel once 1–6 schema stabilises) | `app/lib/core/sync`, `docker/` | 🟡 scaffolded: schema/connector stubs in place |
| 8 | AI/deterministic import — JSON-LD → photo → reconciliation → stub queue | `supabase/functions`, `app/lib/features/import` | 🟡 normalization (§7) implemented + eval-scored; cascade/extraction still stubbed |
| 9 | Computed macros in UI (stretch) | `app/lib/features/recipes` | ⚪ stretch — deferred from step 2 (mockup shows a macro row). Blocked on real data: the seeded vocab is all `stub` with null macros (honest numbers — never invented), so totals need completed ingredients first, plus the "incomplete when stubs present" treatment |
| 10 | Web UI (stretch; near-free with Flutter) | `app/web` | ⚪ stretch |
| 11 | Anti-waste extras (stretch) — freezer batching, monotony warnings, package-size flags | — | ⚪ stretch |

Legend: ⚪ not started · 🟡 scaffolded/in progress · 🟢 done

## Why this order

The unit system underpins recipes, scaling, cook-plan scaling, and shopping-list
aggregation — nothing works until conversions are trustworthy, so it is built
first and hardened with tests. Import (step 8) is deliberately late: it depends
on a stable ingredient vocabulary to match against.

## Open questions (spec §8, low priority)

- Per-entry `portions_override` for big/small appetites, or `|eaters|` only?
- Can a recipe belong to multiple books? (v1 assumes one.)
- Meal slots: fixed set or user-definable? (Assumed user-definable.)
- Freezer-aware batching in v1 or stretch? (Assumed stretch.)
