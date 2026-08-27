# Feature: ingredients

**Roadmap:** Step 1–8 touch this (see `docs/exec-plans/roadmap.md`).

The household's controlled ingredient vocabulary: the manual "Add ingredient"
search (offline, exact/prefix over the synced set — ADR-0004/0005), the "new
ingredient" create flow, and the fleshing-out queue for stubs.

## Layout

```
ingredients/
  domain/         Ingredient entity + IngredientRepository — PURE DART
  data/           SqliteIngredientRepository (read-only search), Riverpod providers
  presentation/   ingredient_picker.dart — the inline vocab search sheet
```

**Status:** only the read-only slice recipes need is built — offline exact/prefix
search over the vocab (`ingredient_picker`). The vocab is now **synced from the
server** (step 7): `ensure_onboarded` seeds a household's `ingredient` rows
(with USDA macros), which stream down. The old bundle loader (`VocabSeeder` +
`assets/seed/vocab.jsonl`) is gone.

Still deferred: the "create new ingredient" flow and the fleshing-out (stub)
queue.
