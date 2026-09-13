# Wide screens — the three layouts, and the one place that reads the width

Ansi runs on a phone, on an iPad in landscape and in a browser window that can
be any width at all. This is how the app answers that width: with three named
bands, one file that reads the viewport, and one widget that every page sits
inside.

---

## 1. The three layouts

| Band | Width | What it is | What the app does |
|---|---|---|---|
| **compact** | `< 640` | a phone, either orientation | the layout every screen is written for, edge to edge |
| **medium** | `640 – 1023` | a portrait tablet, a half-screen browser | the same layout, centred in a 640 column |
| **expanded** | `≥ 1024` | a landscape tablet, a desktop browser | the same layout, centred in a 640 column |

The numbers are **Forui's own** `FBreakpoints` — `sm` 640, `lg` 1024 — read off
the theme rather than typed into the app. They are Tailwind's, which is why they
are unremarkable: nothing here is a bespoke number somebody has to remember.

**640 is the measure**: the widest a column of Ansi content is ever drawn. It is
`sm` itself — the ceiling of compact — and that identity is the point. A page on
a desk is the page on a phone, centred: no reflow, no second layout, nothing to
re-verify against the board. A screen that wants to *use* the width does so by
deliberately not sitting in the measure, and that is a design decision with a
board frame behind it, not a side effect of a wide window.

`medium` and `expanded` do the same thing to a page today. They are still two
bands rather than one, because they differ in what fits *beside* a page — a
persistent sidebar needs `expanded`, and the split is where that decision will
be read.

## 2. Where the reader lives

**`app/lib/shared/ansi_layout.dart` is the only file under `lib/` that reads the
viewport.** It holds three things:

- `AnsiLayout` — the enum above, and `AnsiLayout.of(context)`, which resolves
  the window's width against the theme's breakpoints.
- `AnsiMeasure` — a widget that centres its child in a column no wider than the
  measure, and is a **no-op at compact**, returning the child untouched.
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
  `AnsiMeasure`. The bar is inside the measure on purpose: a bar stretched
  across a monitor above a 640-wide page is two layouts, not one.
- **The router** (`app/lib/core/router/app_router.dart`) wraps every page
  pushed over the shell, in its `_page` helper. Every non-branch route builds
  through it, so a new screen is in the measure the day it is added and cannot
  forget to be.

The **toast** is capped at the measure and anchored bottom-centre on the theme's
toaster style (`app/lib/core/theme/ansi_theme.dart`), so no call site restates
either. On a phone the cap is never reached.

## 4. What a screen may do with width

- **May not:** read the window's size, build a `LayoutBuilder`, or cap itself.
  Fixed logical-px spacing remains the idiom; sizes are not derived from screen
  dimensions.
- **May:** ask `AnsiLayout.of(context)` for a band, where the honest answer
  genuinely differs by band rather than by pixel — a second region beside the
  content, a control that becomes a hover affordance. That is a design decision,
  and it arrives with a board frame.
- **May:** opt out of the measure, for a view whose honest form uses the width.
  That is the same design decision, made deliberately.

## 5. The board's wide frames

The design board draws wide answers in the screen's **own** file, never in a
second copy: a `.board-wide` row under a `Wide · ≥ 1024` rule, in the `desk`
chrome, with every wide frame's name opening with the word *wide*. A view whose
wide answer is "centred, unchanged" draws **no** wide frame at all — it carries
one `wide:` clause on its status line instead.

The rules, and the exact status-line clauses, are
[`board/README.md`](../product-specs/board/README.md) rule 6.

## 6. What this does not answer yet

The chrome beside the content at `expanded`, sheets that become dialogs, and the
views that use the width rather than centring in it are the later legs of
[`exec-plans/active/0047-wide-screens.md`](../exec-plans/active/0047-wide-screens.md),
which also carries the owner's decisions about what each of those looks like.
