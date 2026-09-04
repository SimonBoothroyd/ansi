# Exec plan: 0033 — Library v2 — the decision annex

- **Status:** done — retrospective, written 2026-09-04 from the design board's
  prose before it was cut. The work itself landed 2026-09-02.
- **Owner:** Simon (rulings) + Claude (design lane, then build)
- **Roadmap step:** part of the polish pass —
  [`0022-polish-pass.md`](./0022-polish-pass.md)
- **Created:** 2026-09-02

## Goal

The step-3 frame drew a library you could only add to. Two years of features
later it was the app's home screen and still could not rename a book, fold
one, or find a recipe by name — while its single `＋` had quietly become a
catch-all holding creation, a vocabulary door and sign out.

This file exists because **D1–D8 are cited by number** by later work
(`0028-library-v3.md` amends D6 and fired on D1's own deferral trigger) and
the board's locknote pointed those citations at `library-decisions.md` and
`library-impl.md`, **two files that never existed**. The rulings and the
arguments behind them are recorded here so the numbers resolve.

The owner's sign-off, 2026-09-02: **"looks awesome"** — D1–D8 as
recommended.

## What shipped

`4fac35e` (the header splits — `＋` creates, `⋯` manages), `cf624d8` (rename,
reorder, delete-with-refusal, move contents), `12bace4` (foldable books,
remembered per device), `10737f3` (the book `⋯` menu and the dashed new-section
row inside the card), `69eb9dc` (pinned recipe search replaces the tree with
filed rows), `5d36d4d` (the row reports a favourite), `1cc2033` (the seam with
the shell and the shared search) and `aea1bee` (the docs).

**Zero migrations.** `0004_books.sql` had already given `book` a `name`, a
`sort_order` and a `deleted_at`, with the update policy and grant to match;
`0011` had already given `recipe` its `favorite`. Everything here was
repository methods, one `SharedPreferences` store and presentation. A book
cover or colour was the one idea deferred because it would need a column.

## Decision log

- **D1 — `＋` is the two doors that make a recipe; a new `⋯` beside it holds
  the rest** (Ingredients · New book · Reorder books · Sign out).
  - The argument: *a plus on a library of recipes should promise exactly one
    thing.* The single menu conflated creation with navigation and with
    ending your session — the owner's words were *"the ＋ menu is no longer
    just ＋"*. Split it: `＋` = write it or import it, and a `⋯` to its left
    for everything else. The primary creation action keeps the rightmost,
    thumb-reachable slot it already owns, so existing muscle memory gets
    *shorter* rather than relocated.
  - Rejected: keeping one menu merely regrouped (cheapest — and it keeps the
    exact conflation being complained about); a fifth Ingredients tab
    (standing refusal: the four tabs are the loop, a vocabulary is reference
    data).
  - **The deferral, and its trigger.** Pushing account to a `/account` route
    *now* was refused, because a screen whose only content is a Sign-out
    button exists to hold a divider. The trigger was stated with it: **take
    that route the moment a second setting appears, and Sign out moves there
    whole.** Library v3's E6 is that moment firing — `/account` now holds the
    household roster, the sync line and the session.
- **D2 — a pinned search field; a live query replaces the tree with flat rows
  carrying `Book · Section`; titles only in v1.**
  - The field is top-anchored and pinned under the header, borrowing the
    picker shell's anatomy exactly — a field *on the screen*, not a sheet,
    because the Library is where you already are. The rule it follows is the
    ingredients manager's: **typing collapses the structured view into
    results**, which is what a search is for. No new matcher —
    `matchesSearchQuery` verbatim.
  - The filing line is the whole reason the results are flat: two Ragùs in
    two books are otherwise the same row twice. Clearing the field restores
    the tree exactly as it was, folds included; while a query is live the
    fold state is ignored, because there is no tree to fold.
  - Rejected: filtering the tree in place (it keeps context, but wraps one
    answer in book headers, italic section labels and empty-section lines,
    and the tree jumps as books appear and vanish); a pushed `/search` route
    behind a magnifier (a third header action and a screen you must decide to
    enter); a search tab.
  - **Titles only, said out loud.** "Recipes with almonds" is a different
    query shape — `recipe_line_item → ingredient`, and transitively through
    `sub_recipe_id` — and a hit on a field the row does not show needs a
    *matched: almonds* line to explain itself, which is a new row anatomy.
- **D3 — books fold from a chevron, persisted per device, never synced;
  sections do not fold.**
  - The fold is a **view preference**, so it stays on the device: default
    expanded, persisted in `SharedPreferences` under
    `ansi.book_collapsed.<id>`, swept on sign-out with the rest.
  - Rejected hardest: a synced `book.collapsed` column. Collapse is not
    household data, and **under last-write-wins Jun's tap folds Ada's screen
    mid-scroll** — for the price of a migration and a bucket entry. Also
    rejected: not persisting at all (every relaunch re-opens everything, so
    "Baking stays shut" never sticks).
  - Sections do not fold: a section header is one italic line and its recipes
    are the point of it; two levels of disclosure on a 340 px screen makes
    "what am I looking at" a two-variable question.
- **D4 — a `⋯` on the book header: rename · new section · move up/down ·
  delete, refused with a count and a "Move them to…" door.**
  - The surface already existed one level down: this is the section menu's
    `⋯`, the same `FPopoverMenu`, one level up, so nothing new is learned.
    Reorder is deliberately the same clunky `Move up` / `Move down` the
    sections ship — **don't give books drag-and-drop while sections still
    lack it**; when Forui exposes a drag handle, both convert in one slice.
  - **A book is a shelf, not a container**, so deleting one never cascades to
    recipes. The refusal names the count, read from the repository *at the
    moment of the tap*, never from the cached tree — *"Used in 2 recipes"* is
    something a person can act on; *"failed"* is not.
  - **The refusal is only honest if it is a door.** Without "Move them to…"
    it is a wall in front of the one action that would clear it, which is why
    the one new bulk method (`moveBookContents`) was in scope. It picks a
    target book and then says what it will do — *"42 recipes will move to
    Baking, unsectioned"* — because sections belong to the book they were
    named in and nothing is silently re-filed.
  - **The two refusals are distinct on purpose.** On your only book it reads
    *"This is your only book — every recipe needs a shelf."* A cascade
    refusal would be wrong there: `ensureDefaultBook()` would re-mint a book
    on the next launch, and a book that reappears after you deleted it is
    worse than being told no.
  - Deferred with it: a per-book detail screen (the tracker has carried that
    row since 2026-08-27, whose trigger is "when book count makes the inline
    list unwieldy") — **D3's fold pays that debt more cheaply**, because a
    folded book costs two lines however much it holds. The row is re-worded
    rather than closed: revisit when a book needs a page of its own — a
    cover, notes, per-book search — not because the list got long.
- **D5 — the dashed "new section" row moves inside the expanded card.** It
  was floating in the gap under every book; as the last row of the expanded
  card the noise scales with what is open, not with how many books exist.
- **D6 — the row stays `title · serves`, plus a ★ that only ever reports.**
  - `RecipeSummary.favorite` had existed since `0011` and the picker had a
    Favorites tab, so a library that cannot show a star makes the recipe
    page's star feel like it went nowhere. It **reports only**: tapping
    anywhere on the row opens the recipe, and the toggle stays on the recipe
    page. Absent when false — never a hollow outline on every line, which is
    the stub badge's rule.
  - Rejected on the row: a `keeps 4 d` chip (shelf life is a *planning* fact,
    which is why the picker row carries it and this one does not); a macro
    badge (on honest numbers it is either a number nobody asked for or an
    incomplete nag on most rows).
  - **Amended by Library v3 E8** (2026-09-03, owner): the row gains a `⋯`
    with *Move to…* and the favourite toggle — not a long-press. That amends
    D6's "single tap target"; the mitigation is kept, in that the ★ still
    only reports on the row and the toggle lives in the menu.
- **D7 — five empty states.**
  - **No recipes in a book:** the count reads *no recipes yet*, never
    `0 recipes` — the stub badge's rule, a zero that renders looks like a bug.
  - **An empty shelf offers the two doors in place** — the same two the
    header `＋` offers, so the answer to "it isn't here" is never "go find a
    menu".
  - **An empty section inside a book** keeps the muted mono *No recipes yet*,
    because a section is a label someone typed on purpose, and keeping it
    visible while empty is the whole reason sections are rows and not a
    string on the recipe (plan 0003's ruling).
  - **No books at all** — nearly unreachable, since `ensureDefaultBook()` runs
    at bootstrap, but honest: *"A book is a shelf — name it whatever you call
    it out loud"*, over the same dashed `＋ new book` row.
  - **Search with no hits** — the only empty state that earns real design.
    The typed query becomes the new recipe's title
    (`/recipes/new?title=…`), the ingredient picker's *can't find it? add a
    new one* move: **you searched for a recipe you were about to write.**
    Honest about the query, not clever about it — the string is echoed as
    typed. Rejected: a bare "No results" line; it is the one screen where the
    app knows exactly what you wanted and can hand it to you.
- **D8 — the stub badge climbs to a dot on `⋯`.** The door advertises itself
  without being opened; absent, never grey, when there is nothing to flesh
  out. This is **not a demotion of Ingredients, it is the board catching up**:
  the shipped ingredients-manager frame was annotated "reached from Library ▸
  `⋯` ▸ Ingredients" and the code had put it under `＋` only because `＋` was
  the only menu there was. The door stayed one tap from home, plan 0020 D8's
  "second door" intact.

### What v2 refused

No `0 recipes` and no hollow star — absence renders as absence. No cascade
delete. No synced fold state. No shelf-life chip and no macro badge on a
browsing row. No fifth tab. No new matcher — `matchesSearchQuery` or nothing.

## Notes

- Carried gap at the time: single-word fuzzy search — "chiken" found nothing,
  which is what made D7's no-hits state load-bearing. When a fuzzy tier
  exists it belongs there as a chip band above the two doors, in the import
  review's idiom. (It exists now: the Library renders a `DID YOU MEAN` band.)
- Hand-off recorded with D1: splitting the header **doubled** the header
  popovers, so the navigation lane's fix for "the `＋` menu still shows after
  I close the import modal" had to be menu-agnostic.
- Every idiom in v2 was already shipped somewhere else in the app — the
  pinned search field is the pickers', the flat filing row is the recipe
  picker's, the `⋯` menu is the section menu's, and the delete refusal is the
  8.5/8.6 refusal word for word.

## Step-done checklist

- [x] Shipped 2026-09-02, `make test-sim` 6/6 at the landing.
- [x] Zero migrations — nothing to push to cloud.
- [x] Spec and tracker updated in `aea1bee` / `f1fbdf1`.
- [x] D1's deferral trigger fired, and is recorded as fired: Library v3 E6
      built `/account`.
- [x] D6's amendment recorded: Library v3 E8.
