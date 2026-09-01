import 'dart:async';
import 'dart:io';

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
}
