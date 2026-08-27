# Feature: ingredients

**Roadmap:** Step 1–8 touch this (see `docs/exec-plans/roadmap.md`).

The household's controlled ingredient vocabulary: the manual "Add ingredient"
search (offline, exact/prefix over the synced set — ADR-0004/0005), the "new
ingredient" create flow, and the fleshing-out queue for stubs.

## Layout

```
ingredients/
  domain/         Ingredient entity + IngredientRepository — PURE DART
  data/           SqliteIngredientRepository (read-only search), VocabSeeder,
                  Riverpod providers
  presentation/   ingredient_picker.dart — the inline vocab search sheet
```

**Status (step 2, partial):** only the read-only slice recipes need is built —
offline exact/prefix search over the seeded vocab (`ingredient_picker`) plus a
one-shot `VocabSeeder` that loads the bundled `assets/seed/vocab.jsonl` into the
local table on first run (nothing syncs yet; superseded by sync in step 7).

Still deferred: the "create new ingredient" flow and the fleshing-out (stub)
queue.
