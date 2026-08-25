# Feature: shopping

**Roadmap:** Step 6 — shopping list (derived) (see `docs/exec-plans/roadmap.md`).

Contributions per (cook_session, ingredient) → aggregate in canonical base → provenance → check-off + manual top-up.

## Layout (fill in as this slice is built)

```
shopping/
  domain/         entities + repository interfaces — PURE DART (no package:flutter)
  data/           repository impls, DTOs, PowerSync queries
  presentation/   Views (widgets) + ViewModels (Riverpod notifiers)
```

Empty until its roadmap step. Start by copying `docs/exec-plans/_template.md`
into `docs/exec-plans/active/`.
