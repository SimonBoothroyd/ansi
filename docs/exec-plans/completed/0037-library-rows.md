# Exec plan: Library rows — the recipe line, and the shelf that is not a book

- **Status:** built — both fronts landed; the sim's library leg and the
  roadmap row are still owed
- **Owner:** Simon (rulings) · agent lane (build)
- **Roadmap step:** 8.14 — field test, round five
- **Created:** 2026-09-04

## Goal

Two rows on the home shelf say the wrong thing. A recipe row squeezes its title
against `serves 4` — a number the owner does not want there in that shape — and
the **Ingredients** shelf reads as one more book. Done: the recipe row either
loses the serves label or earns a second line worth the space, and the
vocabulary shelf is unmistakably not a book.

This plan is **drawn on the board before it is built** — both changes reverse
or extend a recorded decision, so the frames come first and the owner signs
them off.

## What was true before this plan

- `_RecipeRow` printed `title · ★ · serves N · › · ⋯` on one line. Its own doc
  recorded the refusal this plan reopened: a macro badge was refused because
  "on honest numbers most rows would show a number nobody asked for, or an
  `incomplete` nag".
- The data was already there: `RecipeSummary.macros` carries **honest
  per-serving macros or an incomplete marker**, computed in the same watch the
  library reads. A second line costs no query.
- The shelf was drawn as a filled herb card with paper text, while the board
  still drew it as a `book-card` with a `›`. **The board and the code
  disagreed** — whatever else this plan did, `library.html` needed
  re-verifying.

## Fronts

Every ruling below is settled; both frames are signed off.

### Front A — the recipe row

- **A-D1** **Ruled (owner, 2026-09-04): the second line.** Muted mono under
  the title — `serves 4 · 520 kcal · 28 g protein` — so the title gets the
  whole first line back and the second line is worth the space it takes.
- **A-D2** The honest-numbers rule is not relaxed. A recipe whose macros are
  incomplete prints **serves only** — no `—`, no `incomplete` badge, no nag.
  That is what makes A-D1 survivable where the old refusal did not: the badge
  was refused as a *badge on every row*; a second line that simply says less
  when it knows less is a different object.
- **A-D3** **Ruled: `kcal` and `protein`** — the two the owner named, and the
  two the recipe page's per-serving panel leads with, so the surfaces agree
  about what matters. Carb and fat stay on the recipe page.
- **A-D4** The row's tap target and its `⋯` are untouched; `★` still reports
  only (Library v2 D6 stands). The `›` goes: the whole row was already the
  door, and the chevron was competing with `⋯` for the same corner.

### Front B — the Ingredients shelf

- **B-D1** **Ruled (owner, 2026-09-04): the rule-and-row.** The shelf stops
  borrowing the book card's shape — a full-width row under a hairline, not a card — the same herb ink as the app's
  other structural type, an icon or a `▤`, the count line, and the `›`. A book
  is a container that folds; the vocabulary is a place you go.
- **B-D2** It keeps its position (after the books, before nothing) and its
  count line, which the Library v3 pass argued for and nobody has complained
  about.
- **B-D3** The board's `library.html` frame is corrected to whatever ships —
  it is currently drawing a card the code does not render.

## Acceptance criteria

- [x] The shipped rows match the two signed-off frames on `library.html`.
- [x] The recipe row ships A-D1's chosen shape; an incomplete-macro recipe
      shows serves only.
- [x] The Ingredients shelf is visually distinct from a book at a glance.
- [x] Tests: `library_view_test` for both rows (incl. the incomplete case).
- [ ] The sim's library leg re-driven (one simulator, scheduled serially).
- [x] Docs: `library.html` status line re-verified (it currently disagrees with
      the code), `app/lib/features/books/README.md`, and `_RecipeRow`'s own doc
      comment — its recorded refusal is superseded and must say so.

## Approach

1. Draw both frames on `library.html` as `proposed`. Nothing else starts.
2. Sign-off → build A, then B; delete the frames they replace.
3. Re-verify the whole `library.html` file while there — the shelf drift proves
   the status date is stale.

## Decision log

- 2026-09-04 — Filed from the owner's round-five notes ("Ingredients in library
  should have a different style"; "either drop serves label … OR redesign into
  something more fancy with macros per serving as well, both on a new line so
  titles aren't squished"). Board-first because A-D1 reverses `_RecipeRow`'s
  recorded refusal.
- 2026-09-04 — Owner: *"yup I like the idea of showing kcal and protein"*.
  A-D1 and A-D3 ruled.
- 2026-09-04 — Owner signed off both proposed frames: B-D1 is the rule-and-row
  as drawn. Nothing in this plan is open.
- 2026-09-04 — **Built, both fronts.** `recipeStatsLine` is the one place the
  second line is composed; `_RecipeRow`'s doc comment now records that its
  macro-badge refusal is superseded, and says why a second line survives where
  a badge did not.
- 2026-09-04 — **The stats line lands on the search row too, not only the tree
  row.** A-D1's frame draws the tree row, but `_RecipeRow` is one widget and
  the search result was the surface still printing `serves N` in the trailing
  slot beside a `›`. Two shapes for one row would have been the accretion the
  plan is trying to undo, so the search result is the same row with its
  `Book · Section` filing line above the stats, and `library.html`'s
  **Search · active** frame is redrawn to match.
- 2026-09-04 — **The shelf's name is the app's uppercase micro-label**
  (`ansiLabel`, herb-deep), as B-D1's frame draws it — so the rendered string
  is `INGREDIENTS`, not `Ingredients`. The sim's `openIngredientsShelf` helper
  and `ingredients_test` were moved onto a shared `ingredientsShelf` finder in
  the same change; they have not been re-driven here (one simulator, serial).
- 2026-09-04 — **The shelf's glyph is Lucide `carrot`**, not the nav's
  `library` icon: the shelf is a door *out* of the Library, not a second badge
  for it. The board's `▤` stands in for it exactly as it stands in for every
  nav glyph the code paints as a Lucide icon.
- 2026-09-04 — Re-verifying the whole view turned up a second, older drift
  (see Notes): the **empty shelf's two doors carry no filing**. Left as drawn
  and named in a `differs:` line rather than fixed here — it is neither front,
  and a fix belongs to the tracker.

## Notes / open questions

- **Found while re-verifying, not fixed here:** `_EmptyShelf`'s two doors
  (`new recipe` / `import one`) push `/recipes/new` and `/import` **bare**,
  while the section `＋` one row above carries `?book=&section=`. The widget
  even holds the `book` it belongs to and never reads it — so a recipe started
  from an empty *Baking* shelf files into whichever book sorts first, silently.
  Named in a `differs:` line on `library.html`'s **First run** frame; it wants a
  tech-debt row, which this lane does not own.

## Step-done checklist

- [ ] Roadmap row updated.
- [ ] `ARCHITECTURE.md` standing table matches for `features/books`.
- [ ] `app/AGENTS.md` current focus still true.
- [ ] `make test-sim` run, result recorded here.
- [ ] Tech-debt rows added/retired.
- [ ] No migration — say so in the roadmap row.
- [ ] `make ci` green.
