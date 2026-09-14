# Exec plan: Wide screens — web and iPad landscape

- **Status:** done — shipped as `v0.17.0`
- **Owner:** Simon (design), agents in lanes
- **Roadmap step:** Step 10 — Web UI
- **Created:** 2026-09-10

## Goal

The app on a browser and an iPad in landscape, as the same product: the
phone layout centred where a column is the honest form, and the width used
where it removes work. The board carries a wide frame for every view that
changes, and the code gets one place that reads the viewport.

## Acceptance criteria

- [x] Every board view carries a `wide:` status clause; views that change draw
      a `proposed` wide frame in their own file.
- [x] `shared/ansi_layout.dart` is the single viewport reader (compact < 640,
      medium 640–1023, expanded ≥ 1024, on Forui's own `FBreakpoints`), held
      by a structural test.
- [ ] Web build in CI, hosted; Google sign-in returns to the deployed origin.
      *Half done: the `web` job builds the bundle on every tag and the code
      returns to the served origin, and the Supabase redirect origins are
      listed. The `pages` deploy has not landed — the `github-pages`
      environment refuses a `v*` tag (release.md §6.1) — so nothing is served
      and no browser sign-in has been walked.*
- [x] Photo import and the barcode scan are gated on web, not thrown.
- [x] Docs updated: `docs/design-docs/wide-screen.md`, `app/AGENTS.md`
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
4. **W3 — the width.** Week's day pane and agenda, book page, recipe page
   columns, Ingredients master-detail, import review with a source pane.

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
  column and is redrawn for wide. Owner call. *(Reversed 2026-09-13, below.)*
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
- 2026-09-13 — **Cook on a desk is one schedule sheet, not two-up cards.** The
  built pair read as gappy and corporate: a card is mostly air around one small
  timeline, and a grid of them leaves a hole under a short one. The sheet spends
  the width on a **shared axis** instead — seven day columns drawn once, faint
  verticals through every row, a row per recipe — so a day is read down a column
  rather than by comparing seven little bars, and a short row is page because no
  box is drawn round it. Capped at 1140 and centred. Nothing about a session
  changes: the phone's tile and the row read one `SessionSpeech` and one
  `CookTimelineSpec`, and every door the card had (the title for this week, the
  whole-batch toggle the tick follows, a gap's fix) is on the row, with the split
  and freezer notes moved from their boxes into the row's margin. Owner call.
- 2026-09-13 — **A tab root and a pushed page share one opt-out.** `AnsiPane`
  is the only applier of the measure, and both router helpers pass it the same
  `fullWidth` flag: `_branch` for the four tab roots (the shelf, the Week's
  two panes, Cook's two-up, the Shop's list beside its provenance pane),
  `_page` for
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
  2026-09-13 "the shelf fills the pane" note.

- 2026-09-13 — **The ledger is fully open: one screen, everything on it.** The
  owner read the built ledger and refused the split it implied — *"I don't like
  the split on Library. Laptops have lots of real estate, so one Library screen
  showing everything is the better flavour."* So the peek and its remainder row
  go: under each heading row the ledger now lists **every section** as a
  one-line heading in the phone's own grammar (the italic label, its count, its
  `＋` and `⋯`, `Unsectioned` last) and **every recipe** under each as a ledger
  line. Nothing counts what is not shown, because nothing is not shown; the
  per-book fold is the only thing that hides anything, and open is the default.
  `/books/:id` keeps its route, its view and its tests — it is deep-linkable,
  and the phone may want a door onto it — but **nothing in the Library links to
  it any more**, so the heading row's name is a name and not a door. The cost
  taken knowingly: the screen is long. That is what the owner asked for, and it
  is why the body is one lazy `SliverList` over flattened lines rather than a
  widget per book — 25 books and a few hundred recipes must cost only the lines
  in the window, and the A–Z margin has to seek to a book that is not built yet.

- 2026-09-13 — First pass landed: the layout file and the measure, the shell
  (sidebar, rail, neutral chrome on a pushed page, sheets as dialogs from
  medium up), the Week at width, the shelf and the book page, the recipe page's
  two columns, Cook two-up, the Shop's provenance pane, the manager's two
  panes, and the web platform work (OAuth origin, gated camera and barcode
  doors, the worker-freshness test, a `web` job with a Pages deploy that
  waits for the owner to enable Pages). Moving modals onto the shell
  navigator moved `hostContextOf` with them: a sheet that popped through the
  root's overlay popped the app instead. Gate: `make test` green, the full
  `make test-sim` on an iPhone 17 simulator green (ten scenarios, nine files)
  after two smoke assertions were brought up to ADR-0016.

- 2026-09-13 — **The Week at width is today, then the week — not a matrix.**
  The owner read the built matrix on his own household and called it busy: it
  bought one screenful with a clipped 11 px line per meal, a bordered card
  round every one of them, and `from Sunday's batch` printed fifteen times.
  A desk scrolls, so the wide Week does not have to be a calendar — *"clarity
  over compactness wins"*. The left pane is a fixed **560** drawing ONE day at
  reading size (today by default; the agenda's `›` moves it, and the choice is
  view state that never persists), and the rest is the whole week as a vertical
  agenda: a heading and one energy line per day, meals as single wrapping lines
  under their slot labels, an eater initial only where the meal is not for
  everyone, the `−` on every line and one `＋ add a meal` per day. Owner call.
  Two consequences he ruled on directly. **Per-meal macros** are on the left as
  well as the day's — `per serving × the portions planned`, read through
  `servedMealMacros`, which is the day total's own function over a set of one,
  so a dish's line and the ledger that sums it cannot drift; the wide form
  spells the figures out (`protein 255 g`) because a 560 px pane has the room
  the phone's glyph strip was compressed for. And **the batch story leaves the
  right pane**: no cook marker, no batch tick, no leader column, no per-day
  grams there. Nothing on the agenda says Wednesday's dinner is Monday's
  leftovers — that reads in the day pane, one tap away, and in Cook. Clarity
  was bought by *moving* the relationship rather than by stating it better;
  the cost, taken knowingly, is that scanning the week to decide what to cook
  now means opening a day.
- 2026-09-13 — **A glyph answers a pointer through one style, and a wide pane
  keeps a gutter for the bar.** The owner's report — *most burger menu buttons
  show no response when hovering … on Library they collide with the scroll bar* —
  was two faults with one cause each. Every glyph control in the app was a bare
  `GestureDetector`, which paints no ground, draws no focus ring and (because
  Forui's tappable style defaults its cursor to `defer`) never even changes the
  arrow; so the answer was the same everywhere and it was nothing. `AnsiTap`
  (`shared/ansi_tap.dart`) is now that answer, over Forui's `FTappable`: a
  herb-soft ground under a herb-deep glyph, the theme's 2 px herb ring at 2 px
  clear, a click cursor and a 32 px minimum target. The two colours are the pair
  `FButtonVariant.ghost` already hovers with (`secondary` /
  `secondaryForeground`), so a `⋯` drawn as a ghost button and a `⋯` drawn as an
  `AnsiTap` read as one control in two shapes; the ring and the cursor are set
  once on the theme, which is also what gave the sidebar, every button and every
  header action a visible hover. **Two deliberate limits.** The 44 px touch
  target is written down and not applied: growing every phone glyph to it from
  underneath would re-lay-out the week card, the header row and every dense
  line, and this pass was to leave the phone alone — so the minimum is
  mouse-only and no phone row moves. And mouse drag-to-scroll stays off: it
  would not have broken drag-to-reorder (the grips use their own all-device
  recognisers) but it would take click-drag text selection away from every
  recipe and ingredient row, and the wheel was never missing. The collision
  half is `AnsiScrollBehavior` plus `ansiScrollPadding`: the bar is the app's
  now — 8 px thick, 2 px in, always visible on a mouse, never drawn on a finger
  — and six wide panes add thickness + margin + 8 to their right padding, one
  derived number, so widening the bar widens the gutter with it.

- 2026-09-13 — **On the wide Shop the check box ticks and the row selects.**
  The owner reads the built pane and finds the row answering two things at
  once: *"pressing the title selects, but the row toggles on/off, which is a
  bit confusing. Feels like just the checkbox should toggle; the rest should
  select."* So the row splits where the drawing already splits it. The box is
  the only tick, inside its own 31 × 44 target — the row's vertical padding
  moves into that target, so a thumb aimed at the box lands on it and the box
  is still drawn exactly where the phone draws it — and a tap anywhere else,
  name, amount or blank, points the pane at that row and lights it. The name
  stops being a special door. A ticked row keeps the pane while it walks to the
  basket section: it did not leave the list, and moving the pane off it would
  be a second thing one tick did. Below `expanded` nothing moves — the whole
  row is the tick, and the breakdown opens under it.
- 2026-09-13 — **The wide import review needed the wire to change, so it did —
  additively.** The frames put the page beside the lines with the current
  line's span lit, and the code had neither half: `ImportReconciling` kept no
  memory of the URL or the photo paths, and the payload threw the fetched page
  away. Both are now carried. The state holds the `ImportSource`, which is the
  photo column's only possible source (its pages are local files the payload
  never mentions), and `import-recipe` sends two optional fields — `source_text`
  (bounded at 20k, well under the prompt's 120k) and a per-line `source_span`
  — omitted whenever there is nothing to say, so a photo import's payload and
  the golden fixture's byte-order are untouched by their existence. The span is
  **located, not extracted**: the server looks for the line's own verbatim
  printed words in the exact string it is about to send and emits a range only
  where they are unambiguous. Asking the model for offsets would have meant a
  prompt, a schema and a re-blessed gold set for a drawing affordance; a fuzzy
  locate would have lit the wrong words, which is a lie about the page. A line
  it cannot place has no span and the column shows the plain page — the same
  never-invent trade the whole pipeline makes.

- 2026-09-13 — **The recipe editor is the recipe page's two columns, written
  instead of read.** Same cap, same seam, one header across the top with the
  title over the lines and the filing over the method, and every one of the four
  small facts still the shipped control — a header redrawn as bare lines would
  state a fact and take away the stepper that sets it. Built as one
  `SliverCrossAxisGroup`, so the lines stay ONE reorderable list and the step
  cards stay lazy. The width buys exactly one relationship: a focused step lights
  the lines its chips point at and rings the chip the caret is inside — following
  **focus**, never the pointer, read off the draft, never stored. Two departures
  from the frame, both from real type against drawn type: the list's two foot
  doors **stack** in the 420 column (side by side they want 544), and the ring is
  the frame's inset herb rule without its hairline, because a text run carries one
  background paint. **Week mode is one column at the measure** — no header form
  and no method means no second column — so `_page` gained `measureOf`: the cap
  when it depends on the route's own query.

- 2026-09-13 — **The URL is the route, on the web.** The owner's bar said a bare
  host while `/recipes/:id/edit` was on screen: go_router reports the *matched*
  route list and ignores anything reached by `push`, and every page above the
  four tab roots here is pushed, so the bar kept reporting the tab root
  underneath — and Flutter's hash strategy omits the `#` for `/`. Back and
  forward worked (each push takes a history entry, with the match list in
  `history.state`); a refresh, which can only read the URL, did not.
  `optionURLReflectsImperativeAPIs = true` is the fix, and its own caveat — a
  pushed route may not be deep-linkable — does not apply, because every pushed
  route here already is and `ansi_back_test.dart` pins that per route. View state
  followed: the week on screen goes in `?week=` on `/week`, `/cook` and `/shop`,
  and the wide Week's day in `?day=` on `/week`, both restated with `replace`
  inside `Router.neglect` so back leaves the week instead of walking the days.
  The Shop's selected row, the Library's fold, search text and the Week's lens
  stay out: a pane pointing somewhere and a half-typed query are not places, and
  a link that scoped a household's week to one eater would be read as the week.
  navigation.md §7.

## Notes / open questions

- Week on wide: where the week band (total, average, `n of 7 days`) sits is
  still open, and the built screen draws none rather than guessing — the day
  pane's ledger carries the open day's figures, the agenda carries every day's
  energy, and a narrower window still has the phone's band. The phone's snack
  day says `4 meals` over three drawn rows.
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
- Drag-to-move on the Week: week v3 refuses `move`. Neither pane may promise
  it until it is a real operation — which is also why the agenda is a list of
  lines and not a column of tiles.

## Step-done checklist

- [x] Roadmap row 10 flipped, with what shipped and what was deferred; the
      untagged row moved into Shipped under `v0.17.0`.
- [x] `ARCHITECTURE.md` standing table updated: the navigation, wide-screen,
      books, recipes, planning, cook-plan, shopping, both import and CI rows.
      The wide-screen row is 🟢 — one reader, one applier, both held by a
      structural test — and names the two limits taken by choice.
- [x] `app/AGENTS.md`'s layout paragraph is the phone-first bullet rewritten,
      and its "Current focus" points at the roadmap, which is current.
- [x] Tech-debt rows added: the web workers nothing refreshes, the crop and the
      scan gated off on web, the 44 px target not applied, drag-to-scroll off,
      the source span's proportional scroll, the Week band with no wide home,
      the wide empty week, `/books/:id` reachable only by a pasted link, the
      Complete dot's two colours on the board, and the `pages` deploy the
      environment refuses. Nothing to retire: no max-width-wrapper row was ever
      opened — the measure arrived with its own applier in this plan's first
      pass.
- [x] `make ci` green on the stacked tree, and `make test-sim` green on an
      iPhone 17 simulator (ten scenarios, nine files) at the first pass.
- [x] No migrations. `import-recipe` changed **additively** (`source_text` and
      a per-line `source_span`, both optional), so a `deploy-supabase` run is
      owed before a review can light a span; nothing breaks until it happens.
