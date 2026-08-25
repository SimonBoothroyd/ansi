# Feature: ingredients

**Roadmap:** Step 1–8 touch this (see `docs/exec-plans/roadmap.md`).

The household's controlled ingredient vocabulary: the manual "Add ingredient"
search (offline, exact/prefix over the synced set — ADR-0004/0005), the "new
ingredient" create flow, and the fleshing-out queue for stubs.

## Layout

```
ingredients/
  domain/         Ingredient entity + repository interface — PURE DART
  data/           repo impl over PowerSync's local SQLite
  presentation/   search, create, and stub-queue views + view models
```

Empty until its roadmap step.
