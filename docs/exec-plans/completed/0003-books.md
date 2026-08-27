# Exec plan: Recipe books + user-defined sections

- **Status:** done
- **Owner:** Simon (+ agent)
- **Roadmap step:** Step 3 — recipe books + user-defined sections
- **Created:** 2026-08-26

## Goal

The app's home screen becomes a **Library**: books holding user-named sections
("Weeknight", "Sweet" — not a preset enum), each listing the recipes filed under
it. You can create books, create/rename/reorder/delete sections, and file a
recipe into a book + section from the recipe editor. The recipe page shows a
"Book · Section" breadcrumb. Everything persists on-device. **Still local-only** —
no `.connect()` (sync is step 7).

## Acceptance criteria

- [x] `book` + `book_section` tables (`0004_books.sql`) with RLS/grants/publication
      mirroring 0003; `recipe` gains nullable `book_id` + `section_id`.
- [x] `schema.dart` mirrors 0004 (new tables + two new `recipe` columns).
- [x] Library home screen: book cards → sections → recipes, with an "Unsectioned"
      bucket and a "+ new section" affordance (matches the design board).
- [x] Create/rename/reorder/delete sections; create a book; file a recipe.
- [x] Recipe editor "file under" book+section picker (pick existing or type new);
      recipe page hero shows "Book · Section".
- [x] Default book auto-created on first run; pre-step-3 recipes adopted into it
      (empty-only gate, idempotent).
- [x] Books domain is pure Dart (invariant 2).
- [x] Tests: repository CRUD + grouping; widget tests for the Library. Verified
      end-to-end on the iOS sim (against the real PowerSync views).
- [x] Docs updated: roadmap, books README, this log. `make ci` green.

## Approach (as built)

Dependency order, mirroring the step-2 slice structure:

1. **Migration `0004_books.sql`** — `book`, `book_section`; `ALTER recipe ADD
   book_id, section_id`. Full RLS/grants/publication like 0003.
2. **`schema.dart`** — `book`, `book_section` synced tables; `book_id`/`section_id`
   columns on `recipe`.
3. **Books domain** — `Book { sections, unsectioned }`, `BookSection { recipes }`
   (reusing `RecipeSummary`); `BookRepository` interface.
4. **Books data** — `SqliteBookRepository` over the local DB (reactive
   `watchLibrary` join; targeted view-safe writes); `bookProviders`;
   `ensureDefaultBook()` wired into `bootstrap.dart`.
5. **Recipes integration** — `Recipe` carries `bookId`/`sectionId` (+ denormalised
   `bookName`/`sectionName` for the hero); repo persists/loads them; editor gains
   the "file under" picker; recipe page renders the breadcrumb.
6. **Presentation** — `LibraryView` becomes `/`; the old flat `RecipeListView`
   (and its test) is removed as superseded.
7. **Docs.**

## Decision log

- 2026-08-26 — **Sections are a `book_section` table**, not a bare recipe label
  (user-confirmed). Honours the spec's "user-defined label, not an enum" while
  adding `sort_order` (reorder), single-point rename, and empty sections the
  mockup's "+ new section" implies. `recipe.section_id` nullable FK; a null or
  soft-deleted section reads as the synthetic "Unsectioned" bucket (no row).
- 2026-08-26 — **Default book auto-created on first run** (empty-only gate),
  reusing `vocab_seeder.dart`'s idempotency; orphan step-2 recipes adopted into
  it. Not SQL-seeded (the local-only DB isn't SQL-seeded yet).
- 2026-08-26 — **Local-only, no `.connect()`** (unchanged from step 2); 0004 RLS
  authored now so step 7 stays a no-op.
- 2026-08-26 — **`LibraryView` replaces the flat recipe list** as `/`. New
  recipes are created from the Library header's "+" menu (New recipe / New book)
  and default into the default book (Unsectioned) via the editor.
- 2026-08-26 — **No `LibraryActions` notifier; views call the keep-alive
  `bookRepositoryProvider` directly.** The first cut wrapped mutations in an
  autoDispose `@riverpod` notifier; the sim caught a runtime crash — the notifier
  was disposed during the async name-dialog, so its captured `ref` threw on the
  callback. The keep-alive repo provider stays valid across async gaps.
  **Plain-SQLite repo tests could not catch this** (no provider lifecycle) — the
  sim did. See [[mise-riverpod-notifier-ref-after-async]].
- 2026-08-26 — **Verified end-to-end on the iOS Simulator** (real PowerSync
  views): default book auto-create + orphan adoption, create section, file a
  recipe into a section via the editor, hero breadcrumb, live regrouping, and
  cold-relaunch persistence. This is the only layer that exercises the view-only
  write path (see [[mise-powersync-views-no-upsert]]).

## Deferred (later steps / open questions)

- **Multi-book many-to-many** — v1 is one book per recipe (`book_id` scalar);
  stays a spec §8 open question.
- **Per-book detail screen** — all books render inline on the Library for v1
  (the design board shows a single book card with its sections).
- **Shelf-life editor inputs, macros, cook mode, Notes, photos** — unchanged from
  step 2's deferrals.

## Carried to the tech-debt tracker

- Repo tests run on plain SQLite (real tables), so PowerSync-view-only and
  provider-lifecycle failures slip through — the sim is the only guard. Section
  reorder is up/down buttons (no drag). See `tech-debt-tracker.md`.
