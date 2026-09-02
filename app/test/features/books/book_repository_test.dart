import 'dart:async';
import 'dart:io';

import 'package:ansi/core/units/units.dart';
import 'package:ansi/features/books/data/book_repository_impl.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:powersync/powersync.dart';

import '../../helpers/test_db.dart';

/// Inserts a bare recipe row (the books repo only reads id/title/book/section).
Future<void> _insertRecipe(
  PowerSyncDatabase db,
  String id,
  String title, {
  String? bookId,
  String? sectionId,
}) async {
  final now = DateTime.now().toUtc().toIso8601String();
  await db.execute(
    'INSERT INTO recipe (id, household_id, title, servings_base, book_id, '
    'section_id, created_at, updated_at) VALUES (?, ?, ?, ?, ?, ?, ?, ?)',
    [id, 'h', title, 2, bookId, sectionId, now, now],
  );
}

void main() {
  late PowerSyncDatabase db;
  late Directory dir;
  late SqliteBookRepository repo;

  setUp(() async {
    (db, dir) = await openTestDb();
    repo = SqliteBookRepository(db, householdId: 'h');
  });

  tearDown(() => closeTestDb(db, dir));

  test('ensureDefaultBook creates a book and adopts orphan recipes', () async {
    await _insertRecipe(db, 'r1', 'Curry');
    final book = await repo.ensureDefaultBook();

    expect(book.name, 'Our Cookbook');
    final books = await db.getAll('SELECT id FROM book');
    expect(books, hasLength(1));

    final row = await db.get('SELECT book_id FROM recipe WHERE id = ?', ['r1']);
    expect(row['book_id'], book.id);
  });

  test('ensureDefaultBook is idempotent', () async {
    final first = await repo.ensureDefaultBook();
    final second = await repo.ensureDefaultBook();

    expect(second.id, first.id);
    final books = await db.getAll('SELECT id FROM book');
    expect(books, hasLength(1));
  });

  test('ensureDefaultBook run twice adopts each recipe once', () async {
    await _insertRecipe(db, 'r1', 'Curry');
    final book = await repo.ensureDefaultBook();
    final section = await repo.createSection(book.id, 'Weeknight');
    await repo.assignRecipe('r1', bookId: book.id, sectionId: section);
    await _insertRecipe(db, 'r2', 'Toast');

    await repo.ensureDefaultBook();

    // The second run must not re-file the already-adopted recipe (which would
    // drop it out of its section) nor duplicate it in the Library.
    final b = (await repo.watchLibrary().first).single;
    expect(b.id, book.id);
    expect(b.sections.single.recipes.map((r) => r.title), ['Curry']);
    expect(b.unsectioned.map((r) => r.title), ['Toast']);
  });

  test('watchLibrary re-fires when a section is renamed', () async {
    final book = await repo.ensureDefaultBook();
    final section = await repo.createSection(book.id, 'Weeknight');

    final library = StreamIterator(repo.watchLibrary());
    addTearDown(library.cancel);

    expect(await library.moveNext(), isTrue);
    expect(library.current.single.sections.single.name, 'Weeknight');

    await repo.renameSection(section, 'Sunday Batch');
    expect(await library.moveNext(), isTrue);
    expect(library.current.single.sections.single.name, 'Sunday Batch');

    await _insertRecipe(db, 'r1', 'Toast', bookId: book.id);
    expect(await library.moveNext(), isTrue);
    expect(library.current.single.unsectioned.map((r) => r.title), ['Toast']);
  });

  test('watchLibrary groups recipes into sections + unsectioned', () async {
    final book = await repo.ensureDefaultBook();
    final weeknight = await repo.createSection(book.id, 'Weeknight');
    await _insertRecipe(
      db,
      'r1',
      'Curry',
      bookId: book.id,
      sectionId: weeknight,
    );
    await _insertRecipe(db, 'r2', 'Toast', bookId: book.id);

    final library = await repo.watchLibrary().first;
    expect(library, hasLength(1));
    final b = library.single;
    expect(b.sections.single.name, 'Weeknight');
    expect(b.sections.single.recipes.map((r) => r.title), ['Curry']);
    expect(b.unsectioned.map((r) => r.title), ['Toast']);
  });

  test('assignRecipe files a recipe into a section', () async {
    final book = await repo.ensureDefaultBook();
    final sweet = await repo.createSection(book.id, 'Sweet');
    await _insertRecipe(db, 'r1', 'Cookies', bookId: book.id);

    await repo.assignRecipe('r1', bookId: book.id, sectionId: sweet);

    final b = (await repo.watchLibrary().first).single;
    expect(b.unsectioned, isEmpty);
    expect(b.sections.single.recipes.map((r) => r.title), ['Cookies']);
  });

  test('deleteSection returns its recipes to Unsectioned', () async {
    final book = await repo.ensureDefaultBook();
    final sweet = await repo.createSection(book.id, 'Sweet');
    await _insertRecipe(db, 'r1', 'Cookies', bookId: book.id, sectionId: sweet);

    await repo.deleteSection(sweet);

    final b = (await repo.watchLibrary().first).single;
    expect(b.sections, isEmpty);
    expect(b.unsectioned.map((r) => r.title), ['Cookies']);
  });

  test(
    'the library summary carries what a batch makes (step 8.6 / D2)',
    () async {
      final book = await repo.ensureDefaultBook();
      await _insertRecipe(db, 'r1', 'Romesco Aioli', bookId: book.id);
      await db.execute(
        'UPDATE recipe SET yield_qty = 1, yield_unit = ?, yield_qty_2 = 250, '
        'yield_unit_2 = ? WHERE id = ?',
        ['cup', 'g', 'r1'],
      );

      final aioli = (await repo.watchLibrary().first).single.unsectioned.single;

      // The editor's line picker offers its "Your recipes" rows off this tree
      // and hands the pick straight to the batch-math sheet, so a summary
      // without the yield makes a recipe that states one read "no yield yet".
      expect(aioli.yields, [(qty: 1.0, unit: cup), (qty: 250.0, unit: g)]);
    },
  );

  test('createSection appends and reorderSections reorders', () async {
    final book = await repo.ensureDefaultBook();
    final a = await repo.createSection(book.id, 'A');
    final b = await repo.createSection(book.id, 'B');

    var sections = (await repo.watchLibrary().first).single.sections;
    expect(sections.map((s) => s.name), ['A', 'B']);

    await repo.reorderSections(book.id, [b, a]);
    sections = (await repo.watchLibrary().first).single.sections;
    expect(sections.map((s) => s.name), ['B', 'A']);
  });

  test('renameBook persists and the library re-fires with the name', () async {
    final book = await repo.ensureDefaultBook();

    final library = StreamIterator(repo.watchLibrary());
    addTearDown(library.cancel);
    expect(await library.moveNext(), isTrue);
    expect(library.current.single.name, 'Our Cookbook');

    await repo.renameBook(book.id, '  Weeknights  ');
    expect(await library.moveNext(), isTrue);
    // Trimmed on the way in, the same as createBook/createSection.
    expect(library.current.single.name, 'Weeknights');
  });

  test('reorderBooks writes contiguous orders the library reads', () async {
    final a = await repo.createBook('Baking');
    final b = await repo.createBook('Our Cookbook');

    expect((await repo.watchLibrary().first).map((x) => x.name), [
      'Baking',
      'Our Cookbook',
    ]);

    await repo.reorderBooks([b, a]);

    expect((await repo.watchLibrary().first).map((x) => x.name), [
      'Our Cookbook',
      'Baking',
    ]);
    final orders = await db.getAll('SELECT id, sort_order FROM book');
    expect(
      {for (final r in orders) r['id'] as String: r['sort_order']},
      {b: 0, a: 1},
    );
  });

  test('countRecipesIn counts live rows in that book only', () async {
    final book = await repo.ensureDefaultBook();
    final other = await repo.createBook('Baking');
    await _insertRecipe(db, 'r1', 'Curry', bookId: book.id);
    await _insertRecipe(db, 'r2', 'Toast', bookId: book.id);
    await _insertRecipe(db, 'r3', 'Scones', bookId: other);
    // A tombstoned recipe must not inflate the delete refusal's count.
    await db.execute('UPDATE recipe SET deleted_at = ? WHERE id = ?', [
      DateTime.now().toUtc().toIso8601String(),
      'r2',
    ]);

    expect(await repo.countRecipesIn(book.id), 1);
    expect(await repo.countRecipesIn(other), 1);
    expect(await repo.countBooks(), 2);
  });

  test('deleteBook soft-deletes the book and its sections', () async {
    final book = await repo.ensureDefaultBook();
    final keep = await repo.createBook('Baking');
    final section = await repo.createSection(book.id, 'Weeknight');

    await repo.deleteBook(book.id);

    expect((await repo.watchLibrary().first).map((b) => b.id), [keep]);
    final row = await db.get(
      'SELECT deleted_at FROM book_section WHERE id = ?',
      [section],
    );
    expect(row['deleted_at'], isNotNull);

    // A second delete is a harmless no-op — the tombstone is already there.
    await repo.deleteBook(book.id);
    expect(await repo.countBooks(), 1);
  });

  test(
    'moveBookContents re-parents live recipes and unsections them',
    () async {
      final from = await repo.ensureDefaultBook();
      final to = await repo.createBook('Baking');
      final section = await repo.createSection(from.id, 'Weeknight');
      await _insertRecipe(
        db,
        'r1',
        'Curry',
        bookId: from.id,
        sectionId: section,
      );
      await _insertRecipe(db, 'r2', 'Toast', bookId: from.id);
      await _insertRecipe(db, 'r3', 'Scones', bookId: to);

      await repo.moveBookContents(fromBookId: from.id, toBookId: to);

      final library = await repo.watchLibrary().first;
      final source = library.firstWhere((b) => b.id == from.id);
      expect(source.unsectioned, isEmpty);
      expect(source.sections.single.recipes, isEmpty);

      final target = library.firstWhere((b) => b.id == to);
      // Sections belong to the book they were named in, so everything lands
      // unsectioned — never pointing at the old shelf's label.
      expect(
        target.unsectioned.map((r) => r.title),
        containsAll(<String>['Curry', 'Toast', 'Scones']),
      );
      final moved = await db.get('SELECT section_id FROM recipe WHERE id = ?', [
        'r1',
      ]);
      expect(moved['section_id'], isNull);
    },
  );

  test('the library tree reports a favourited recipe (D6)', () async {
    final book = await repo.ensureDefaultBook();
    await _insertRecipe(db, 'r1', 'Romesco Aioli', bookId: book.id);
    await _insertRecipe(db, 'r2', 'Toast', bookId: book.id);
    await db.execute('UPDATE recipe SET favorite = 1 WHERE id = ?', ['r1']);

    final rows = (await repo.watchLibrary().first).single.unsectioned;

    // The yield-column bug class, one column over: a tree that drops
    // `favorite` renders every Library row unstarred whatever the recipe page
    // says. Pin it at the tree, not only at the recipe list.
    expect(
      {for (final r in rows) r.title: r.favorite},
      {'Romesco Aioli': true, 'Toast': false},
    );
  });

  test('createBook after deleting the only book still yields one', () async {
    final first = await repo.ensureDefaultBook();
    await repo.deleteBook(first.id);

    final second = await repo.ensureDefaultBook();

    expect(second.id, isNot(first.id));
    expect(await repo.countBooks(), 1);
  });
}
