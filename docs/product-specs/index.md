# Product specs — index

What the app does, from the user's point of view. The "why" behind technical
choices lives in `../decisions/`; the "what to build next" in
`../exec-plans/roadmap.md`.

- [`product-spec.md`](./product-spec.md) — the full v1 spec: scope, data model,
  meal planning, batch cook plan, shopping list, feature specs, build sequence.
- [`import-and-matching.md`](./import-and-matching.md) — the import + ingredient
  matching design: extraction, normalization, the match cascade, reconciliation,
  the stub lifecycle, and the offline/online split. It is the authority on the
  **import mechanism** — extraction, normalization, the match cascade and the
  stub lifecycle — where the spec's §5 only states the product claim and links
  here. The rest of §5 (the review screen's behaviour, the header, the method,
  the curated default measure) stands.
- [`design-board.html`](./design-board.html) — the visual design board ("Ansi"):
  palette, type, and every screen. Open in a browser.
