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
    library_view.dart      the `/` home screen (book cards → sections → recipes)
    book_view_models.dart  libraryProvider (stream)
    text_prompt.dart       shared name/rename dialog
```

## Model notes

- **Sections are rows** (`book_section`), not a label on the recipe, so they
  carry `sort_order` (reorder), rename in one place, and can exist empty. A
  recipe's `section_id` is a nullable FK; null (or a soft-deleted section) →
  Unsectioned. See the decision log in the exec plan.
- **A recipe lives in one book** (`recipe.book_id`). Multi-book many-to-many is a
  deferred open question (spec §8).
- **Default book** ("Our Cookbook") is auto-created on first run and adopts any
  book-less recipes — `bootstrap.dart` calls `ensureDefaultBook()` after the
  vocab seeder (empty-only gate, idempotent). New recipes default into it via the
  editor's "file under" picker.
- **Writes are view-safe**: local PowerSync tables are SQLite views, so every
  statement is a plain INSERT/UPDATE (no UPSERT, no subquery DELETE). Repo tests
  run on plain SQLite (real tables) and can't catch view-only failures, so the
  write paths are verified on the iOS sim.

## Still local-only

Like step 2, nothing calls `.connect()` — `0004_books.sql` authors the
RLS/grants/publication now so step 7 only has to connect.
