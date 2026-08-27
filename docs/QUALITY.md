# Quality bar

A lightweight, hobby-scale version of the "quality score" idea: grade each area
so gaps are visible and tracked over time. Update grades as areas mature. This is
a living signal, not a gate.

Grades: 🟢 solid · 🟡 partial · 🔴 thin/missing

| Area | Grade | Notes |
|------|-------|-------|
| Unit system (`core/units`) | 🟢 | Built and tested; the reference for `core/` style (step 1). |
| Ingredient data model + vocab | 🟢 | Migrations `0001`/`0002` + RLS, 291-ingredient vocab, macros prefilled server-side. Density still sparse. |
| Recipes (`features/recipes`) | 🟢 | Editor (incl. shelf-life inputs), recipe page, scaling; repo tested against real PowerSync views. |
| Books (`features/books`) | 🟢 | Library, sections, filing; repo tested (incl. watched-join re-fire). Reorder is menu-based, not drag (tech-debt). |
| Sync layer (`core/sync`) | 🟡 | Local schema is real and exercised by tests; no `.connect()` until step 7. |
| Planning (`features/planning`) | 🟢 | Week grid + Shared/Per-person lens, two-step add flow (picker → confirm with portions), slot grouping, copy-last-week; batch-aware chips + "same batch" hint (step 5); repo + domain + widget tests; verified on the sim. |
| Cook-plan (`features/cook_plan`) | 🟢 | Derived Cook screen: greedy shelf-life clustering + freezer merge, session cards with timeline/notes; pure-Dart domain + format fully tested, repo tested on real PowerSync views, screen widget-tested; verified on the sim. Whole-ingredient scaling + interactive cook-day deferred (stretch). |
| Shopping (`features/shopping`) | 🔴 | Empty feature slice (step 6). |
| Import + matching (`supabase/functions`) | 🟡 | Normalization implemented + eval-scored; cascade/extraction stubbed (step 8). |
| Docs / harness | 🟢 | Structure in place; `make docs-check` enforces integrity; step-done checklist in the exec-plan template. |
| CI | 🟢 | Format, analyze (+custom_lint), tests on a real `PowerSyncDatabase`, docs-check. The sim smoke (`make test-sim`) is a local gate by choice. |

## The bar for "done" on any slice

- Logic lives in the right layer (domain is pure Dart).
- Tests cover the logic, and they'd fail if the logic broke.
- Behaviour-affecting changes updated the relevant doc.
- `make ci` and `make docs-check` are green.
