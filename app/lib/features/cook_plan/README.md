# Feature: cook_plan

**Roadmap:** Step 5 — batch cook plan (derived) (see `docs/exec-plans/roadmap.md`).

Group the week's entries by recipe; split into cook sessions bounded by shelf life (greedy clustering); adjustable cook day; whole-ingredient scaling.

## Layout (fill in as this slice is built)

```
cook_plan/
  domain/         entities + repository interfaces — PURE DART (no package:flutter)
  data/           repository impls, DTOs, PowerSync queries
  presentation/   Views (widgets) + ViewModels (Riverpod notifiers)
```

Empty until its roadmap step. Start by copying `docs/exec-plans/_template.md`
into `docs/exec-plans/active/`.
