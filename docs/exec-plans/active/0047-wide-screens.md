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
- [x] Photo import and the barcode scan are gated on web, not thrown.
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
- 2026-09-13 — **The page exists, and the backlog row is deleted.**
  `/books/:id` ships with the shelf: the book's name and count line, its
  sections in order with `Unsectioned` last, and the Library card's own
  widgets for every control (`features/books/book_rows.dart`, shared by the
  card and the page). What the retired row asked for beyond that — a cover
  or colour (`book.color`), notes, per-book search — is **not** built and no
  migration was added for it; the page earned its place from the width, not
  from a book wanting decoration. The router's `_page` helper gained one
  flag, `fullWidth`, so a page whose honest wide form is two panes opts out
  of the measure once the chrome is beside the content and stays centred
  everywhere else.
- 2026-09-13 — **The shelf fills the pane it is given.** The grid takes as
  many columns as fit at a 320 px tile. Until the shell lane hands a branch
  root the whole width, the tab shell still centres the Library at the
  measure, so a desk window draws two columns rather than four, and the
  Library header keeps its household door until the sidebar's Account
  replaces it. Both are named on `library.html` as `differs`.

- 2026-09-13 — **W1's platform half is built** (release.md §6, app/AGENTS.md):
  OAuth returns to the served page, photo import reads a blob URL through
  `XFile` and downscales through `compute`, the crop step is skipped on web
  (cropperjs + a `BuildContext` the provider has not got was judged
  disproportionate) and the scan door is not drawn. A `web` job builds the
  browser bundle on every tag and a gated `pages` job deploys it. **Two
  operator steps are owed before a browser can sign in:** the Supabase
  redirect origins (cloud-setup.md §1.6) and Pages → Source: GitHub Actions.
  The endpoint-disclosure trade that hosting carries is release.md §6.2 —
  owner's call, not an agent's.
- 2026-09-13 — ADR-0002's "PowerSync web is in beta" line is **no longer
  true**; the ADR is immutable, so release.md §6.3 carries the correction
  until the wide-screen design doc exists to hold it.
- 2026-09-13 — **A tab root and a pushed page share one opt-out.** `AnsiPane`
  is the only applier of the measure, and both router helpers pass it the same
  `fullWidth` flag: `_branch` for the four tab roots (the shelf, the matrix,
  Cook's two-up, the Shop's list beside its provenance pane), `_page` for
  `/books/:id` and the two `/ingredients` routes. A page that stays one wrap
  but needs a wider cap passes `measure:` instead — `/recipes/:id`, and only
  it. One vocabulary for "this view uses the pane", so the shell lane's roots
  and the view lanes' pages are not two rules that have to be kept in step.

- 2026-09-13 — **The Library on wide is a ledger, not a shelf of tiles.**
  Owner's call on the built shelf, on his own household at 1440: *"corporate"*
  — the solid dark herb bands, the uniform four-across grid and the full-width
  search bar read as a SaaS dashboard, which is the one thing the product is
  not. What replaces them states every fact once and sets it in a column on
  bare paper: one ledger column at 900, centred, with a 34 px A–Z index in the
  right margin; a book is a heading row (name, dotted leader, count line, `⋯`)
  over its first three recipes as one-line rows and a remainder row that opens
  the book page; the search field is a 300 px line, not a bar. Three things the
  tiles could not do come back with it — the **fold**, which is the phone's own
  per-device state and now reads the same store on both bodies; the recipe
  row's **stats**, set into the counts column instead of dropped for want of
  tile height; and **twenty-five books**, which the margin keeps scannable
  without the shape changing. It supersedes the 2026-09-10 tile ruling and the
  2026-09-13 "the shelf fills the pane" note; `/books/:id` is unchanged, and is
  still the door a heading row opens.

- 2026-09-13 — First pass landed: the layout file and the measure, the shell
  (sidebar, rail, neutral chrome on a pushed page, sheets as dialogs from
  medium up), the Week matrix, the shelf and the book page, the recipe page's
  two columns, Cook two-up, the Shop's provenance pane, the manager's two
  panes, and the web platform work (OAuth origin, gated camera and barcode
  doors, the worker-freshness test, a `web` job with a Pages deploy that
  waits for the owner to enable Pages). Moving modals onto the shell
  navigator moved `hostContextOf` with them: a sheet that popped through the
  root's overlay popped the app instead. Gate: `make test` green, the full
  `make test-sim` on an iPhone 17 simulator green (ten scenarios, nine files)
  after two smoke assertions were brought up to ADR-0016.

## Notes / open questions

- Week on wide: where the week band (total, average, `n of 7 days`) sits is
  still open, and the built matrix draws none rather than guessing — the
  per-day band carries every day's figures, and a narrower window still has
  the phone's band. The phone's snack day says `4 meals` over three drawn
  rows.
- The ledger's density is the risk the direction was chosen with: it sits one
  notch from a spreadsheet, and if "corporate" meant "too much at once" it can
  fail on the same word. Worth a second look on his own 25 books.
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
