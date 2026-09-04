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
- [`board/`](./board/README.md) — the visual design board ("Ansi"): what every
  screen looks like **today**, one hand-written HTML file per view. Open
  [`board/index.html`](./board/index.html) in a browser — the masthead, the
  system strip (palette · type · the freshness signature) and one status row
  per view, each linking its file. `board.css` is the shared visual language;
  `not-built.html` holds frames that were drawn and never built, each citing
  its [backlog](../exec-plans/backlog.md) row. The board draws pixels and
  nothing else: a screen is **replaced** when a design pass lands, never
  appended to, and the decisions behind it live in the exec plan or the ADR
  its status line links. [`board/README.md`](./board/README.md) states the
  rules and the status-line grammar.
