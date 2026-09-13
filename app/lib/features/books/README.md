# Feature: books

**Roadmap:** Step 3 — recipe books + sections (done; see
`docs/exec-plans/completed/0003-books.md`).

Recipe books with user-defined section labels (not a fixed enum). The **Library**
is the app's home screen: books hold ordered, user-named sections ("Weeknight",
"Sweet"), each listing the recipes filed under it, plus a synthetic
"Unsectioned" bucket for recipes with no section.

## Layout

```
books/
  domain/         PURE DART (no package:flutter)
    book.dart              Book · BookSection aggregate (reuses RecipeSummary)
    book_repository.dart   BookRepository interface
  data/
    book_repository_impl.dart  SqliteBookRepository over local PowerSync
    book_providers.dart        bookRepositoryProvider (keepAlive)
  presentation/
    library_view.dart      the `/` home screen (book cards → sections → recipes,
                           or a shelf of book tiles on a wide window)
    book_page_view.dart    the `/books/:id` page — one book, sections as an
                           index beside the recipes at `expanded`
    book_rows.dart         what both of those draw: the book `⋯`, a section
                           block with its `＋` and `⋯`, the recipe row and its
                           `⋯`, the count and stats lines
    book_view_models.dart  libraryProvider (stream)
    text_prompt.dart       shared name/rename dialog
```

**One book, two doors, one set of widgets.** The Library card and the book page
are different containers around the same objects, so every control lives in
`book_rows.dart` and neither screen owns a copy: an item added to the book menu
appears at both doors, and a change to the recipe row changes both. The page is
pushed (`/books/:id`), so it covers the bar and back returns to the Library.

**What the width changes.** At `AnsiLayout.expanded` the Library body is a grid
of fixed-height book tiles — the name on its herb band, the count line, the first
three titles and `+ N more`, or the `＋` where a shelf is bare — and a tile opens
the page. Tiles list **titles only**: the recipe row is two lines with a `⋯`, and
three of those do not fit the body a fixed tile leaves. The fold is not read
there (a tile is the folded book), and everything that is not a book — the `＋ new
book` door, the Ingredients shelf, the ranked search column — is the phone's own,
in the phone's order.

## What the Library's rows say

- **A recipe row** is a title on its own line, then a muted mono stats line:
  `serves 4 · 520 kcal · 28 g protein`. The macros are read straight off
  `RecipeSummary.macros`, which the same watch already computes — a second line
  costs no query. **A recipe whose macros are incomplete prints the serves and
  stops**: no dash, no `incomplete` badge, no nag (invariant 3 — honest
  numbers, or silence; the picker row wears the badge, because that is where a
  person is choosing what to cook). The row has no `›`: the whole row is the
  door, and the `⋯` owns that corner. A search result is the same row with its
  `Book · Section` filing line above the stats.
- **The Ingredients shelf** at the foot is a **rule and a row, not a card** — a
  hairline, the uppercase micro-label in herb ink, the counts, and a `›`. A
  book is a container that folds; the vocabulary is a place you go, so nothing
  about it invites the fold, the `⋯` or the reorder a book header carries. It
  keeps its position after the books and never renders a zero count.

## Model notes

- **Sections are rows** (`book_section`), not a label on the recipe, so they
  carry `sort_order` (reorder), rename in one place, and can exist empty. A
  recipe's `section_id` is a nullable FK; null (or a soft-deleted section) →
  Unsectioned. See the decision log in the exec plan.
- **A recipe lives in one book** (`recipe.book_id`). Multi-book many-to-many is a
  deferred open question (spec §8).
- **Default book** ("Our Cookbook") is auto-created on first run and adopts any
  book-less recipes (empty-only gate, idempotent). Since step 7 the caller is
  `core/sync/session.dart` — after `.connect()` **and** `waitForFirstSync()`, so
  an existing household's books arrive before we'd seed one and a second device
  can't mint a duplicate. `bootstrap.dart` no longer does this — the vocab
  seeder it used to follow was retired when vocab started syncing. New recipes default into it via `RecipeEditor.build`, and imports file
  into it inside the commit transaction — the Library renders books and skips
  book-less recipes, so a null `book_id` hides the recipe.
- **Writes are view-safe**: local PowerSync tables are SQLite views, so every
  statement is a plain INSERT/UPDATE (no UPSERT, no subquery DELETE). Repo tests
  run on plain SQLite (real tables) and can't catch view-only failures, so the
  write paths are verified on the iOS sim.

## Still local-only

`0004_books.sql` authors the RLS/grants/publication; the book tables sync since
step 7 (`.connect()` in `core/sync/session.dart`).
