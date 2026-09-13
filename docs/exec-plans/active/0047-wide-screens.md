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
- [x] `shared/ansi_layout.dart` is the single viewport reader (compact < 640,
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
3. **W2 — the shell.** Built: the sidebar at ≥ 1280 and the icon rail from
   1024, neutral on a pushed page, which draws its own back control; sheets
   become dialogs through `ansi_modals.dart`; tooltips and focus rings. Left:
   the keyboard reorder, and the first Tab on a cold page landing on the page
   rather than on the sidebar.
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
- 2026-09-13 — **The outer shell preserves every back rule.** One `ShellRoute`
  now wraps the tab shell and all eight pushed routes, and the table in
  `navigation.md` §3 holds row by row: the tab shell's `PopScope` still rides
  the page that carries it, so a non-Library tab spends its back on coming home
  and the Library tab leaves the app; a pushed page pops to the tab under it; a
  cold deep link still reports `canPop() == false`, because go_router's own
  `canPop` walks into nested shells. On wide the browser's Back does what the
  page's own control does. Asserted in `app/test/shared/ansi_wide_shell_test.dart`
  against the real route shape.
- 2026-09-13 — **Modals open on the shell navigator, not the root above it.**
  The root would put a sheet above the pushed pages as well, and the add-new
  chain (a picker pushing the flesh-out form over its own surface) needs the
  form to land ON the sheet — a page and a modal stack in a knowable order only
  when they share a navigator. The cost, taken knowingly: a dialog's barrier
  stops at the content pane, so the sidebar stays clickable beside it. The
  board's dialog frame says otherwise and the view carries a `differs:` clause.
- 2026-09-13 — **The sidebar speaks Forui's voice.** Sentence-case sans labels
  in the rail against the bar's mono uppercase: a bar item is a word under a
  glyph, a sidebar item is a line of a list. Closes the label-voice question.
- 2026-09-10 — **A book gets its own page.** The Library on wide is a shelf
  of fixed-height book tiles; a tile opens the book page, whose sections
  are a left index against the recipes at a readable measure. The
  per-device fold does not exist on wide. Search results stay one ranked
  column. Owner call; retires the backlog's per-book detail row when built.

## Notes / open questions

- Week on wide: where the week band (total, average, `n of 7 days`) sits;
  what an empty week draws (a matrix with no slot rows); the phone's snack
  day says `4 meals` over three drawn rows.
- Library tiles carry titles, not stats: three two-line rows do not fit a
  fixed tile and most books have no board-stated macros.
- Recipe page: a struck (per-week) line's chip in the method column has no
  stated rendering; the 272 px ingredients column wraps whole-measure amounts.
- Board debts outside the wide frames: `ingredient-detail.html` paints the
  Complete strip amber in one frame and fresh green in another; the phone
  navigation back-table counts (sheets, dialogs) are stale against the code.

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
