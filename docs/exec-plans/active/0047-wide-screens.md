# Exec plan: Wide screens — web and iPad landscape

- **Status:** active
- **Owner:** Simon (design), agents in lanes
- **Roadmap step:** Step 10 — Web UI
- **Created:** 2026-09-10

## Goal

The app on a browser and an iPad in landscape, as the same product: the
phone layout centred where a column is the honest form, and the width used
where it removes work. The board carries a wide frame for every view that
changes, and the code gets one place that reads the viewport.

## Acceptance criteria

- [ ] Every board view carries a `wide:` status clause; views that change draw
      a `proposed` wide frame in their own file.
- [ ] `shared/ansi_layout.dart` is the single viewport reader (compact < 640,
      medium 640–1023, expanded ≥ 1024, on Forui's own `FBreakpoints`), held
      by a structural test.
- [ ] Web build in CI, hosted; Google sign-in returns to the deployed origin.
- [ ] Photo import and the barcode scan are gated on web, not thrown.
- [ ] Docs updated: `docs/design-docs/wide-screen.md`, `app/AGENTS.md`
      (the "phone-first" bullet), ADR-0002's PowerSync web line.

## Approach

1. **Board first.** The shell (navigation), Week, Library and the book page,
   recipe page, Shop, Ingredients manager — each drawn `proposed` in its own
   file, against the decisions below. Import review and Cook follow.
2. **W1 — the phone layout on a URL.** The layout file, every tab root and
   pushed page in the measure, the toast capped, the OAuth branch, a `web`
   job, a host. No screen redesign.
3. **W2 — the shell.** Sidebar at ≥ 1024, neutral with a back control on a
   pushed page; sheets become dialogs through `ansi_modals.dart`; hover,
   focus, tooltips, keyboard reorder.
4. **W3 — the width.** Week matrix, book page, recipe page columns,
   Ingredients master-detail, import review with a source pane.

## Decision log

- 2026-09-09 — `flutter build web` is green (48 s) and PowerSync's web path
  opens, writes and persists in Chrome with **and without** cross-origin
  isolation headers, so COOP/COEP is optional and GitHub Pages is a viable
  host. Runtime blockers are the OAuth custom-scheme redirect, `dart:io` /
  `Isolate.run` in photo import, `image_cropper` without web settings, and
  the absent CI job.
- 2026-09-09 — Thesis: centre the views that are a column by nature
  (Shop, Account, the pickers); use the width on Week, Library, the recipe
  page, Ingredients and import. A first mock set and its review found the
  first drafts assumed one screenful and small data everywhere.
- 2026-09-10 — **Shell:** a persistent sidebar at ≥ 1024 with the four
  destinations; on a pushed page it goes **neutral** (nothing lit) and the
  page draws its own back control, keeping navigation.md's "the bar being
  gone is the signal" in spirit. **Account stays in the sidebar footer**;
  on wide it replaces the Library header's household door, so there is one
  door, not two. Owner call.
- 2026-09-10 — **Week is a matrix**, but its rows are the slots that exist
  in the week on screen, derived, never a fixed count (`meal_slot` is
  free text). Every day keeps its one `＋ add a meal` at the column foot in
  every state. The phone's per-day macro strip does not survive a 146 px
  column and is redrawn for wide. Owner call.
- 2026-09-10 — **A book gets its own page.** The Library on wide is a shelf
  of fixed-height book tiles; a tile opens the book page, whose sections
  are a left index against the recipes at a readable measure. The
  per-device fold does not exist on wide. Search results stay one ranked
  column. Owner call; retires the backlog's per-book detail row when built.

## Notes / open questions

- The wide chrome's labels: the phone bar is mono uppercase; Forui's
  `FSidebar` is sans sentence-case. Decide before the board says built.
- Two phones drive the Shop at once; a checked row must not move under the
  other shopper. Wide keeps the list one column.
- Drag-to-move on the Week matrix: week v3 refuses `move`. The matrix must
  not promise it until it is a real operation.

## Step-done checklist

- [ ] Roadmap row 10 flipped, with what shipped and what was deferred.
- [ ] `ARCHITECTURE.md` standing table updated for the shell and layout.
- [ ] `app/AGENTS.md` "phone-first" bullet rewritten.
- [ ] Tech-debt rows added for corners cut (worker/wasm refresh, barcode on
      web), retired for the max-width wrapper debt.
- [ ] `make ci` green.
