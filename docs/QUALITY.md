# Quality bar

A lightweight, hobby-scale version of the "quality score" idea: grade each area
so gaps are visible and tracked over time. Update grades as areas mature. This is
a living signal, not a gate.

Grades: 🟢 solid · 🟡 partial · 🔴 thin/missing

| Area | Grade | Notes |
|------|-------|-------|
| Unit system (`core/units`) | 🟢 | Built and tested; the reference for `core/` style (step 1). Named `Measure`s (step 7.6, `measure.dart`) bridge count↔mass via stored gram weights — honest by construction (bad grams refuse like bad density; volume still needs a density). |
| Ingredient data model + vocab | 🟢 | Migrations `0001`/`0002` + RLS, 291-ingredient vocab, macros prefilled server-side. `ingredient_measure` (`0009`): 28 hand-curated starter measures (sources noted), synced + cloned at onboarding, watched per-ingredient repo. Density still sparse; no in-app measure editor yet (tracker). |
| Recipes (`features/recipes`) | 🟢 | Editor (incl. shelf-life inputs, `allowedUnitsFor`-filtered units), recipe page, scaling; `saveRecipe` diffs children (sync-safe edits); repo tested against real PowerSync views. |
| Books (`features/books`) | 🟢 | Library, sections, filing; repo tested (incl. watched-join re-fire). Reorder is menu-based, not drag (tech-debt). |
| Sync layer (`core/sync`) | 🟢 | `.connect()` is live behind a sign-in + `/connecting` gate (dev email/password; Google wired). `ensure_onboarded` (advisory-locked, template-vocab clone; `0007`+`0008`) + `add_household_claim` JWT hook, all 14 tables synced (`ingredient_measure` joined in 0009), `MiseConnector` drains the queue soft-delete-safe **and jsonb-safe** (decodes `steps`/`eaters`/`macros`, clears `deleted_at` on PUT — both unit-tested against real `ps_crud`). Session is a sealed state machine (retry/sign-out, cached-household offline relaunch, queued auth events). Onboarding/hook/RLS pinned by ~50 pgTAP assertions. **Verified live**: local + cloud E2E (0008), on-device hardening pass (7.4), and the auth-aware `make test-sim` smoke now round-trips recipes and plan entries through live sync. Cloud health is now scripted read-only (`scripts/cloud_verify.sh` + `cloud.env` + committed `docker/powersync-cloud.streams.yaml` with a CI drift check; ledger in `docs/cloud-setup.md`). **Untested**: Google browser flow, offline-queue drain, two-client concurrent session (tracker). |
| Planning (`features/planning`) | 🟢 | Week grid + Shared/Per-person lens, two-step add flow (picker → confirm with portions), slot grouping, copy-last-week; batch-aware chips + "same batch" hint (step 5); repo + domain + widget tests; verified on the sim. |
| Cook-plan (`features/cook_plan`) | 🟢 | Derived Cook screen: greedy shelf-life clustering + freezer merge, session cards with timeline/notes; **whole-batch nudge** on fractional sessions (step 7.6: `wholeBatchNudgeFor`, display-level toggle — the raw factor stays what everything scales by); pure-Dart domain + format fully tested, repo tested on real PowerSync views, screen widget-tested; verified on the sim. Interactive cook-day still deferred (stretch). |
| Shopping (`features/shopping`) | 🟢 | Derived Shop screen: aisle-grouped list summed from the cook plan with provenance + check-off; honest `aggregateQuantities` (now folds measure-quantified lines into the mass subtotal, step 7.6) + `buildShoppingList` fully unit-tested; **whole-unit hint** on measure-bearing count foods ("2.25 → buy 3" — beside the total, never replacing it); thin overlay (`0006` + `0009` measure FK) for check-off / manual / non-food; repo tested on real PowerSync views (incl. recipe-deletion lifecycle, two-device duplicate-entry merge, and measure degradation); verified on the sim. Package-size flags stay step 11; edit-top-up unit filter open (tracker). |
| Import + matching (`supabase/functions`) | 🟡 | Normalization implemented + eval-scored; cascade/extraction stubbed (step 8). |
| Docs / harness | 🟢 | Structure in place; `make docs-check` enforces integrity; `make docs` really generates `docs/generated/db-schema.md`; step-done checklist in the exec-plan template. |
| CI | 🟢 | Format, analyze (+custom_lint), tests on a real `PowerSyncDatabase`, docs-check. The sim smoke (`make test-sim`) is a local gate by choice. |

## The bar for "done" on any slice

- Logic lives in the right layer (domain is pure Dart).
- Tests cover the logic, and they'd fail if the logic broke.
- Behaviour-affecting changes updated the relevant doc.
- `make ci` and `make docs-check` are green.
