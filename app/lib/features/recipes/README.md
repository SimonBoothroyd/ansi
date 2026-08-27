# Feature: recipes

**Roadmap:** Step 2 — single-user recipes (see `docs/exec-plans/roadmap.md`).

Create a recipe, group ingredients ("for the sauce"), scale it, and render the beautiful recipe page + method + cook mode.

## Layout

```
recipes/
  domain/         Recipe/IngredientGroup/LineItem (Freezed), RecipeRepository,
                  scaling.dart — PURE DART (no package:flutter)
  data/           SqliteRecipeRepository over the local PowerSync SQLite,
                  Riverpod providers
  presentation/   Forui Views (list · recipe page · editor) + Riverpod
                  ViewModels (recipe_view_models.dart)
```

Built in step 2 (see `docs/exec-plans/completed/0002-single-user-recipes.md`).
Notes:
- **Synced persistence (since step 7).** The app `.connect()`s PowerSync once
  signed in (`core/sync/session.dart`); recipes persist on-device and sync to the
  household, with writes queuing harmlessly while offline.
- **Scaling is a view concern** — `scaling.dart` scales displayed quantities for
  a target serving; the stored recipe is untouched. Imprecise units never scale.
- **Save replaces children** (groups/line-items) wholesale rather than diffing.
- The ingredient picker lives in `features/ingredients` (read-only vocab search).

The editor's **shelf-life inputs** (keeps / freezable / freezer days) landed in
step 5 — they feed the cook plan's clustering; the recipe page renders the
`keeps`/`freezable` chips from those values.

**Deferred (implemented in later steps, not missing by accident):** the macro
row → step 9 (needs completed, non-`stub` ingredients); cook mode, method
ingredient-chips/timers, Notes tab, photos. See the roadmap + `tech-debt-tracker.md`.
