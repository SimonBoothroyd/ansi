# Quality bar

A lightweight, hobby-scale version of the "quality score" idea: grade each area
so gaps are visible and tracked over time. Update grades as areas mature. This is
a living signal, not a gate.

Grades: 🟢 solid · 🟡 partial · 🔴 thin/missing

| Area | Grade | Notes |
|------|-------|-------|
| Unit system (`core/units`) | 🔴 | Contract stubbed; no implementation or tests yet (roadmap step 1). |
| Sync layer (`core/sync`) | 🔴 | Schema/connector stubs only. |
| Recipes / books / planning / cook-plan / shopping | 🔴 | Empty feature slices. |
| Import + matching (`supabase/functions`) | 🔴 | Contract stubbed; no logic. |
| Docs / harness | 🟢 | Structure in place; `make docs-check` enforces integrity. |
| CI | 🟡 | Analyze/test/docs jobs defined; will firm up as code lands. |

## The bar for "done" on any slice

- Logic lives in the right layer (domain is pure Dart).
- Tests cover the logic, and they'd fail if the logic broke.
- Behaviour-affecting changes updated the relevant doc.
- `make ci` and `make docs-check` are green.
