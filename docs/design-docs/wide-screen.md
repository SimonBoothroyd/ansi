# Wide screens — the three layouts, and the one place that reads the width

Ansi runs on a phone, on an iPad in landscape and in a browser window that can
be any width at all. This is how the app answers that width: with three named
bands, one file that reads the viewport, and one widget that every page sits
inside — and, from `lg` up, a shell whose navigation stands beside the content
rather than under it.

---

## 1. The three layouts

| Band | Width | What it is | What the app does |
|---|---|---|---|
| **compact** | `< 640` | a phone, either orientation | the layout every screen is written for, edge to edge |
| **medium** | `640 – 1023` | a portrait tablet, a half-screen browser | the same layout, centred in a 640 column |
| **expanded** | `≥ 1024` | a landscape tablet, a desktop browser | the same layout, centred in the pane left beside the sidebar |

The numbers are **Forui's own** `FBreakpoints` — `sm` 640, `lg` 1024 — read off
the theme rather than typed into the app. They are Tailwind's, which is why they
are unremarkable: nothing here is a bespoke number somebody has to remember.

**640 is the measure**: the widest a column of Ansi content is ever drawn. It is
`sm` itself — the ceiling of compact — and that identity is the point. A page on
a desk is the page on a phone, centred: no reflow, no second layout, nothing to
re-verify against the board. A screen that wants to *use* the width does so by
deliberately not sitting in the measure, and that is a design decision with a
board frame behind it, not a side effect of a wide window.

`medium` and `expanded` do the same thing to a page; they differ in what fits
*beside* it. A persistent sidebar needs `expanded`, and that is the split's
whole job — the chrome's own form is a second question, answered by `AnsiShell`
(§4), because it does not divide at the same widths.

## 2. Where the reader lives

**`app/lib/shared/ansi_layout.dart` is the only file under `lib/` that reads the
viewport.** It holds three things:

- `AnsiLayout` — the enum above, and `AnsiLayout.of(context)`, which resolves
  the window's width against the theme's breakpoints.
- `AnsiMeasure` — a widget that centres its child in a column no wider than the
  measure, and is a **no-op at compact**, returning the child untouched.
- `AnsiShell` — the **form the navigation takes**, and `AnsiShell.of(context)`:
  `bar` below `lg`, `rail` from `lg` to just under `xl`, `sidebar` from `xl` up.
  A second question rather than a view on `AnsiLayout`, because the answers do
  not line up: `bar` spans compact *and* medium (a 900 px window is too wide for
  the phone layout to stretch and too narrow to spend 188 px on chrome), while
  `rail` and `sidebar` split `expanded` in two. `form.beside` is the question
  most callers actually ask — is there a pane, or is the window the pane?
- `AnsiPane` — the widget the router wraps **every** route in, and the only
  place `AnsiMeasure` is applied from. Section 3.
- `ansiViewportHeight(context, factor)` — a share of the window's height, for a
  sheet pinned to a fraction of the screen. It lives here for one reason: it is
  a viewport read.

`test/structure/one_viewport_reader_test.dart` fails the build if
`MediaQuery.sizeOf`, `MediaQuery.of(context).size` or `LayoutBuilder` appears in
any other file under `lib/`. There is no allow-list beyond the layout file.

Reads of the *insets* — `MediaQuery.viewInsetsOf`, `paddingOf`, the keyboard and
the home indicator — are not viewport reads and are not restricted. They are
about what is covering the screen, not how wide it is.

**Why one reader.** A screen that measures itself is a second source of truth
for "what is a phone". Fifteen screens measuring themselves is fifteen answers,
fifteen caps that drift apart, and a breakpoint change that has to be chased
through the whole app. Asking once and applying the answer structurally means a
wide-screen change is one file's business.

## 3. Where the measure is applied

Twice. A screen never wraps itself.

- **The tab shell** (`app/lib/shared/ansi_tab_shell.dart`) wraps everything it
  owns — the sync banner, the four branches and the bottom bar — in one
  `AnsiMeasure`, **while the bar is under the content**. The bar is inside the
  measure on purpose: a bar stretched across a monitor above a 640-wide page is
  two layouts, not one.
- **The router** (`app/lib/core/router/app_router.dart`) wraps every route in an
  `AnsiPane`, through its `_page` and `_branch` helpers. Every screen in the app
  builds through one of the two, so a new screen is in its pane the day it is
  added and cannot forget to be.

`_branch` is the four tab roots, and it passes `insideShellMeasure: true`: while
the bar is under the content the shell's single wrap already covers them, and a
second one there would be the screen measuring itself. Once the chrome is beside
the content that wrap is gone — there is no bar to keep company with — and each
branch root measures its own pane like any other page.

### The full-pane opt-out

A view whose honest form uses the width says so **on its route**:

```dart
_branch(path: '/week', name: 'week', fullWidth: true,
        builder: (state) => const WeekView()),
```

`fullWidth` takes the whole content pane instead of the measure — and only once
the chrome is beside the content. At `AnsiShell.bar` there is no pane to fill:
the window *is* the pane, so a full-width page still sits in the measure, which
is what keeps a 900 px browser window one column rather than a stretched phone.

It is a fact about the route rather than something the screen does to itself,
for the same reason the measure is: a screen that decides its own width is a
second source of truth about what a page is, and the wide answer then has to be
chased screen by screen.

**All four tab roots opt out**, through `_branch`: the Library's ledger, the
Week's agenda beside its day pane, Cook's schedule sheet and the Shop's list
with its provenance pane are each a pane's worth of design, and each caps itself
where its own drawing says — Cook at 1140 and centred, the Shop pair at the
measure plus its 360 pane, the Library ledger at 900 with its margin index, and
the Week a fixed 340 agenda with the day pane taking whatever is left.

**A pushed page opts out the same way**, through `_page`'s `fullWidth`:
`/books/:id`, where a book is a ~200 px section index beside its recipes, which
does not fit 640; `/ingredients` and `/ingredients/:id`, the manager's two
panes; and `/import`, whose review is the page beside the lines beside one
line's form. Below the band each is centred like every other page. One flag over both
helpers, so the measure still has exactly two appliers and a screen still never
wraps itself — opting out is a route's stated decision, readable in one place,
not a widget quietly escaping its parent.

The **toast** is capped at the measure and anchored bottom-centre on the theme's
toaster style (`app/lib/core/theme/ansi_theme.dart`), so no call site restates
either. On a phone the cap is never reached.

## 4. The shell beside the content

From `lg` up the four destinations move off the bottom and stand beside the
page: `app/lib/shared/ansi_side_nav.dart` draws them, and
`app/lib/shared/ansi_wide_shell.dart` is the builder of the router's **outer
`ShellRoute`**, which wraps the tab shell *and* every pushed page.

| Form | Width | What it draws |
|---|---|---|
| `bar` | `< 1024` | nothing — the tab shell keeps its bottom bar, and the outer shell returns the navigator untouched |
| `rail` | `1024 – 1279` | a 64 px icon rail, labels as tooltips on hover or focus |
| `sidebar` | `≥ 1280` | the 188 px sidebar: the wordmark, the four destinations with their labels, Account in the footer |

Three things follow from the sidebar being drawn **outside** the navigator that
holds the pages, and they are the reason it is:

- **A push keeps the chrome.** The sidebar takes no part in a route transition,
  so it cannot slide in over itself, fade, or appear twice while a page animates.
- **It is one instance.** The lit destination is read from the location, so the
  lit form and the neutral form are one widget with a different index rather
  than two sidebars that have to agree.
- **Nothing lit is the signal that you have left the tab loop.** On a phone the
  bar being gone says it; a sidebar cannot go away, so a pushed page goes quiet
  behind and draws its own back control. Every pushed page already carries one
  in its header, and a structural test
  (`app/test/shared/ansi_wide_shell_test.dart`) keeps it that way.

**Account is the sidebar's footer item, and on wide it is the only household
door** — the Library's header does not draw a second one. One door, not two. It
**pushes** the page, the way the phone's header door does, so the page's own
chevron has something to pop; the four destinations above it `go`
([`navigation.md`](./navigation.md) §3).

## 5. What a screen may do with width

- **May not:** read the window's size, build a `LayoutBuilder`, or cap itself.
  Fixed logical-px spacing remains the idiom; sizes are not derived from screen
  dimensions.
- **May:** ask `AnsiLayout.of(context)` for a band, where the honest answer
  genuinely differs by band rather than by pixel — a second region beside the
  content, a control that becomes a hover affordance. That is a design decision,
  and it arrives with a board frame.
- **Must:** answer a pointer. On a mouse-and-keyboard device every glyph-only
  control — the `⋯`, the `−`, the `＋` doors, the fold chevrons, the sidebar
  items, the A–Z letters — takes its hover (a herb-soft ground
  under a herb-deep glyph), its 2 px herb focus ring, its click cursor and its
  32 px minimum target from **one shared style**: `AnsiTap`
  (`app/lib/shared/ansi_tap.dart`) over Forui's `FTappable`, with the ring and
  the cursor stated once on the theme so a `FButton` and a swept glyph say the
  same thing. None of it exists on a phone, and the target minimum is applied
  only where the pointer is a mouse, so no phone row moves. And **a wide pane
  keeps a right gutter for the scrollbar** — `ansiScrollPadding`
  (`app/lib/shared/ansi_scroll.dart`), the bar's thickness plus its margin plus
  8 px of air — because the bar is drawn over the content, last, and a `⋯` at the
  end of a ledger row would otherwise sit under the thumb. The bar itself is the
  app's: one `AnsiScrollBehavior` at the root, a stated thickness and margin,
  always visible on a mouse and never drawn at all on a finger.
- **May:** opt out of the measure, for a view whose honest form uses the width.
  That is the same design decision, made deliberately. Such a page is capped
  wider rather than stretched: it passes a `measure:` through the router's
  `_page` helper, and the number is the layout file's (`ansiWideMeasureWidth`),
  never the router's or the screen's.

**The screens that use the width**, one line each:

- **The recipe page** — at `expanded` it has no tabs: Ingredients and Method are
  two columns read together under one hero, which carries the scaler and the
  `⋯`; the per-serving panel closes the ingredients column at that column's
  width, with `Used in · N` under it while the count is non-zero. It is capped
  at `ansiWideMeasureWidth` — a measure and a half plus the page's own gutters,
  about 1000. Below `expanded` it is the phone's page, centred at 640.
- **The recipe editor** — the same recipe, so the same cap: one header across
  the top (the title over the lines, the filing over the method, then serves /
  makes / times / shelf life as four cells), the ingredient lines left in a
  fixed 420 column and the method right as the phone's step cards. While a step
  has focus the lines its chips point at are lit and the chip the caret is
  inside is ringed — view state that follows focus, never the pointer, and never
  stored. Week mode (`?week=`) is one column at the measure instead.

### What each wide screen does with the width

One row per screen that uses the width rather than centring in it — the board
frame behind it is in that screen's own file, under its `Wide · ≥ 1024` rule.

| Screen | From `expanded` up |
|---|---|
| **Library** (`features/books`) | at `expanded` the body is a **ledger, fully open**: one column of books capped at 900 and centred, with a 34 px **A–Z index** in the right margin that lights the letters with books and scrolls to them. A book is a heading row — name, dotted leader, count line, `⋯` — over **every section it keeps and every recipe under each**: a section is a one-line heading (italic label, count, `＋`, `⋯`), a recipe one line with its stats in the same column, `Unsectioned` last. No remainder row and no link to `/books/:id`. The **fold is read**, the phone's own per-device state, and it is the only thing that hides anything. The whole shelf is one lazy `SliverList`, so length costs only the lines in the window; the field is 300 px at the head of the column rather than a header bar, and the ranked results column, the `＋ new book` door and the vocabulary shelf are the phone's. |
| **Book page** (`/books/:id`, `features/books`) | **two panes**: a 200 section index (counts, current lit, tapping scrolls the one list) beside the recipes at the measure; every row and menu is the Library's own. Nothing links here — the ledger lists what the page holds — so it is reached by a pasted link. |
| **Week** (`features/planning`) | **two panes, the week at left**: a fixed **340 agenda** — a heading per day (name, date, `TODAY`, and what the day holds at its right edge), every meal of that day as ONE wrapping mono run with an eater mark only where the meal is not for everyone, and the day's macros as the phone's own strip — beside a **day pane** that takes the rest and draws one day as a page, capped at a 600 reading measure: the day at 24, a dish at 17, each meal's figures as the muted strip, and the ledger pinned to the foot with its grams spelt out. The week's band pins to the agenda's foot. There is **one** add door and it is in the pane; the day the pane stands on lives in the location (`/week?day=`), so a refresh lands back on it. |
| **Shop** (`features/shopping`) | the walk stays **one column at the measure** — two phones drive it at once, and a checked row must not move — with a 360 pane beside it holding one row's `from …` breakdown open. The row's two answers are split in one place: the **check box ticks** — its own 31 × 44 target, the row's vertical padding folded in so the box is drawn where the phone draws it — and a tap **anywhere else on the row** points the pane at it, lit. A ticked row keeps the pane as it walks to the basket section. The aisles and the one basket section are the phone's, and below `expanded` the whole row is still the tick. |
| **Cook** (`features/cook_plan`) | the plan is **one schedule sheet, capped at 1140 and centred**: a row per recipe against seven day columns drawn once — a herb tick with its `×N` on the cook day, a herb-soft band for as long as the batch keeps, a dot on every day it feeds, amber for a day only the freezer reaches — with the covers sentence at the row's end and the split or freezer note in its margin. One set of words (`SessionSpeech`) and one keep-window geometry (`CookTimelineSpec`) serve both forms, and every door the phone's card has is on the row. |
| **Recipe editor** (`features/recipes`) | at `expanded` the phone's one scroll becomes **two columns under one header**, capped at `ansiWideMeasureWidth` like the page it edits: the header's six sections folded onto two rows — the title over the lines and the filing over the method, then the four small facts as cells, every one the shipped control — over a 420 lines column and a method column that takes the rest. One `SliverCrossAxisGroup`, so the lines are still ONE reorderable list and the step cards are still lazy. The width buys one relationship: a focused step lights the lines its chips point at (the Shop's own selected-row wash) and rings the chip the caret is inside. **Week mode** (`?week=`) draws no header form and no method, so it has no second column: one column at the measure, with the week's own statement in a column at the row's right end. |
| **Import review** (`features/import`) | **three columns, capped at 1240 and centred**: the SOURCE at 380 (a link's fetched page with the selected line's span lit, a photo import's pages with a thumbnail each), the LINES at 480 — the phone's rows on bare paper, amber as a 2 px margin rule, one row washed herb, no expand-in-place — and a 340 PANEL holding that line's form, which is the phone's *expanded card* verbatim. Idle, the panel is the import's outstanding work grouped by what each line wants, read from the one validation map the header count and the Save gate read. The commit bar is the lines column's footer. Narrowing, the source gives up its width first (floor 300), then the panel (300), and the lines last (440). The reading state draws the source column already. |
| **Ingredients manager** (`features/ingredients`) | **two panes**: the vocabulary (its search field and stub band pinned, the aisle sections scrolling under them, the add door at the foot) and the fact sheet, capped at 720, opened **in place** rather than pushed. `/ingredients/:id` lands on the same split with that row lit; `?edit=1` stays the form in the measure at every width. |

The recipe page and the recipe editor keep one wrap and pass a wider cap
through `_page`'s `measure`. The editor's is the one cap that depends on the
route's own query — `?week=` is a different page inside `/recipes/:id/edit` —
so it comes through `_page`'s `measureOf` instead, still naming the layout
file's number rather than a new one.

The two pages of the manager, the book page and `/import` opt out of the
router's measure through `_page`'s `fullWidth` flag — handed the whole pane once the
chrome is beside the content, in the measure below it — never by wrapping or
unwrapping themselves. The four tab roots say the same thing through `_branch`.

## 6. A sheet on a phone is a dialog on a desk

`showAnsiSheet` (`app/lib/shared/ansi_modals.dart`) presents the **same builder**
two ways: a bottom sheet at `AnsiLayout.compact`, and from `medium` up a centred
dialog. There is no bottom edge worth rising from on a desk, and nothing to gain
by spanning the window.

- A **short** sheet is sized to its content, at most **560** wide. Narrower than
  the measure on purpose: a dialog as wide as the page it covers reads as a
  second page.
- A **tall** one — a sheet that asks for a share of the screen's height
  (`heightFactor`, which is every `PickerShell`) — takes the dialog's own
  **640**, so a long vocabulary scrolls inside it instead of pushing the search
  field off the top. A short window shortens it rather than overflowing.
- **Esc dismisses**, and a dismissal is not an answer: every caller already
  reads a null as the no.
- The sheet shell's bottom pad (`max(keyboard, home indicator) + 12`) is not
  applied in the dialog form, and neither is its lip: a centred dialog has no
  strip beneath it and a ring on all four sides. It lifts itself off the
  keyboard.

**All 21 call sites are unchanged**, and so is every return value. The form is
the door's business, not theirs.

One consequence worth stating: the dialog opens on the app's shell navigator —
the one navigator holding the tab shell and every pushed page — so its barrier
covers the pages but **not** the sidebar beside them. That is the price of
keeping a page pushed from inside a sheet landing *on* the sheet (the add-new
chain), which needs the two on one navigator. See `navigation.md` §4.

## 7. The board's wide frames

The design board draws wide answers in the screen's **own** file, never in a
second copy: a `.board-wide` row under a `Wide · ≥ 1024` rule, in the `desk`
chrome, with every wide frame's name opening with the word *wide*. A view whose
wide answer is "centred, unchanged" draws **no** wide frame at all — it carries
one `wide:` clause on its status line instead.

The rules, and the exact status-line clauses, are
[`board/README.md`](../product-specs/board/README.md) rule 6.

## 8. What this does not answer yet

Three things a desk asks for that no width here answers:

- **A finger on a wide screen.** The 32 px minimum target `AnsiTap` gives a
  glyph control is a *mouse* minimum. The phone's 44 px rule is written down
  and deliberately not applied to those controls, because growing them from
  underneath would re-lay-out the week card and every dense line.
- **Drag.** Mouse drag-to-scroll is off — it would take click-drag text
  selection away from every recipe and ingredient row — and neither Week pane
  offers drag-to-move a meal, because the week has no `move` operation to
  promise.
- **A keyboard.** Tab order is the framework's: the reorder a desk would do
  with the arrow keys is not built, and a cold page's first Tab lands on the
  sidebar rather than the page.

The owner's decisions behind every wide answer above are the decision log of
[`exec-plans/completed/0047-wide-screens.md`](../exec-plans/completed/0047-wide-screens.md);
what someone still owes is in the
[tracker](../exec-plans/tech-debt-tracker.md).
