# Feature: import

**Roadmap:** Step 8 — import + reconciliation (client side) (see `docs/exec-plans/roadmap.md`).

Kick off a server-side import; show the three-state reconciliation screen; commit resolved lines + stubs. Matching itself is server-side (ADR-0004).

## Layout (fill in as this slice is built)

```
import/
  domain/         entities + repository interfaces — PURE DART (no package:flutter)
  data/           repository impls, DTOs, PowerSync queries
  presentation/   Views (widgets) + ViewModels (Riverpod notifiers)
```

Empty until its roadmap step. Start by copying `docs/exec-plans/_template.md`
into `docs/exec-plans/active/`.
