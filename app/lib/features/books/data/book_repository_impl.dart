/// [BookRepository] over the local PowerSync SQLite.
///
/// Reads assemble the Library aggregate and react to local writes via
/// `watch`. Writes are targeted UPDATE/INSERT, never `INSERT ... ON CONFLICT`,
/// which PowerSync's view-backed tables reject. Deletes are soft.
library;

import 'package:sqlite_async/sqlite_async.dart';
import 'package:uuid/uuid.dart';

import '../../../core/units/units.dart' show unitById;
import '../../recipes/domain/recipe.dart' show RecipeSummary;
import '../domain/book.dart';
import '../domain/book_repository.dart';

const _uuid = Uuid();

class SqliteBookRepository implements BookRepository {
  const SqliteBookRepository(this._db, {required String householdId})
    : _householdId = householdId;

  final SqliteConnection _db;

  /// The household stamped on rows this repo writes.
  final String _householdId;

  @override
  Stream<List<Book>> watchLibrary() {
    // The query selects a column from each of the three tables: SQLite drops
    // a LEFT JOIN with no selected column, and PowerSync then never watches
    // that table. The rows are ignored; each fire re-runs [_loadLibrary].
    return _db
        .watch(
          'SELECT b.id, s.id, r.id FROM book b '
          'LEFT JOIN book_section s ON s.book_id = b.id '
          'LEFT JOIN recipe r ON r.book_id = b.id '
          'WHERE b.deleted_at IS NULL LIMIT 1',
        )
        .asyncMap((_) => _loadLibrary());
  }

  Future<List<Book>> _loadLibrary() async {
    final bookRows = await _db.getAll(
      'SELECT id, name FROM book WHERE deleted_at IS NULL '
      'ORDER BY sort_order, created_at',
    );
    final sectionRows = await _db.getAll(
      'SELECT id, book_id, name FROM book_section WHERE deleted_at IS NULL '
      'ORDER BY sort_order, created_at',
    );
    // The yield columns and `favorite` ride along: the line picker and the
    // star read them straight off this tree.
    final recipeRows = await _db.getAll(
      'SELECT id, title, servings_base, book_id, section_id, favorite, '
      'yield_qty, yield_unit, yield_qty_2, yield_unit_2 FROM recipe '
      'WHERE deleted_at IS NULL ORDER BY created_at DESC',
    );

    // Section id → recipe list, and each section's owning book.
    final sectionRecipes = <String, List<RecipeSummary>>{};
    final sectionBook = <String, String>{};
    for (final s in sectionRows) {
      sectionRecipes[s['id'] as String] = [];
      sectionBook[s['id'] as String] = s['book_id'] as String;
    }

    final unsectioned = <String, List<RecipeSummary>>{
      for (final b in bookRows) b['id'] as String: <RecipeSummary>[],
    };

    for (final r in recipeRows) {
      final bookId = r['book_id'] as String?;
      // Skip orphans (no book, or a book that no longer exists).
      if (bookId == null || !unsectioned.containsKey(bookId)) continue;
      final summary = RecipeSummary(
        id: r['id'] as String,
        title: r['title'] as String,
        servingsBase: (r['servings_base'] as num).toDouble(),
        favorite: (r['favorite'] as int? ?? 0) == 1,
        yieldQty: (r['yield_qty'] as num?)?.toDouble(),
        yieldUnit: unitById(r['yield_unit'] as String? ?? ''),
        yieldQty2: (r['yield_qty_2'] as num?)?.toDouble(),
        yieldUnit2: unitById(r['yield_unit_2'] as String? ?? ''),
      );
      final sectionId = r['section_id'] as String?;
      // A live section in the same book claims the recipe; otherwise it
      // falls to the book's Unsectioned bucket.
      if (sectionId != null && sectionBook[sectionId] == bookId) {
        sectionRecipes[sectionId]!.add(summary);
      } else {
        unsectioned[bookId]!.add(summary);
      }
    }

    final sectionsByBook = <String, List<BookSection>>{};
    for (final s in sectionRows) {
      (sectionsByBook[s['book_id'] as String] ??= []).add(
        BookSection(
          id: s['id'] as String,
          name: s['name'] as String,
          recipes: sectionRecipes[s['id']] ?? const [],
        ),
      );
    }

    return [
      for (final b in bookRows)
        Book(
          id: b['id'] as String,
          name: b['name'] as String,
          sections: sectionsByBook[b['id']] ?? const [],
          unsectioned: unsectioned[b['id']] ?? const [],
        ),
    ];
  }

  @override
  Future<Book> ensureDefaultBook() async {
    final existing = await _db.getOptional(
      'SELECT id, name FROM book WHERE deleted_at IS NULL '
      'ORDER BY sort_order, created_at LIMIT 1',
    );
    final String id;
    final String name;
    if (existing != null) {
      id = existing['id'] as String;
      name = existing['name'] as String;
    } else {
      id = await createBook('Our Cookbook');
      name = 'Our Cookbook';
    }
    // Adopt any book-less recipes so nothing is stranded outside the Library.
    final now = _now();
    await _db.execute(
      'UPDATE recipe SET book_id = ?, updated_at = ? '
      'WHERE book_id IS NULL AND deleted_at IS NULL',
      [id, now],
    );
    return Book(id: id, name: name);
  }

  @override
  Future<String> createBook(String name) async {
    final id = _uuid.v4();
    final now = _now();
    final order = await _nextSortOrder('book', 'deleted_at IS NULL');
    await _db.execute(
      'INSERT INTO book (id, household_id, name, sort_order, created_at, '
      'updated_at) VALUES (?, ?, ?, ?, ?, ?)',
      [id, _householdId, name.trim(), order, now, now],
    );
    return id;
  }

  @override
  Future<void> renameBook(String bookId, String name) async {
    await _db.execute('UPDATE book SET name = ?, updated_at = ? WHERE id = ?', [
      name.trim(),
      _now(),
      bookId,
    ]);
  }

  @override
  Future<void> reorderBooks(List<String> orderedBookIds) async {
    final now = _now();
    await _db.writeTransaction((tx) async {
      for (var i = 0; i < orderedBookIds.length; i++) {
        await tx.execute(
          'UPDATE book SET sort_order = ?, updated_at = ? WHERE id = ?',
          [i, now, orderedBookIds[i]],
        );
      }
    });
  }

  @override
  Future<int> countRecipesIn(String bookId) async {
    final row = await _db.get(
      'SELECT COUNT(*) AS n FROM recipe '
      'WHERE book_id = ? AND deleted_at IS NULL',
      [bookId],
    );
    return row['n'] as int;
  }

  @override
  Future<void> moveBookContents({
    required String fromBookId,
    required String toBookId,
  }) async {
    // One statement: the move and the un-filing are the same fact.
    await _db.execute(
      'UPDATE recipe SET book_id = ?, section_id = NULL, updated_at = ? '
      'WHERE book_id = ? AND deleted_at IS NULL',
      [toBookId, _now(), fromBookId],
    );
  }

  @override
  Future<void> deleteBook(String bookId) async {
    final now = _now();
    await _db.writeTransaction((tx) async {
      await tx.execute(
        'UPDATE book_section SET deleted_at = ?, updated_at = ? '
        'WHERE book_id = ? AND deleted_at IS NULL',
        [now, now, bookId],
      );
      await tx.execute(
        'UPDATE book SET deleted_at = ?, updated_at = ? '
        'WHERE id = ? AND deleted_at IS NULL',
        [now, now, bookId],
      );
    });
  }

  @override
  Future<String> createSection(String bookId, String name) async {
    final id = _uuid.v4();
    final now = _now();
    final order = await _nextSortOrder(
      'book_section',
      'book_id = ? AND deleted_at IS NULL',
      [bookId],
    );
    await _db.execute(
      'INSERT INTO book_section (id, household_id, book_id, name, sort_order, '
      'created_at, updated_at) VALUES (?, ?, ?, ?, ?, ?, ?)',
      [id, _householdId, bookId, name.trim(), order, now, now],
    );
    return id;
  }

  @override
  Future<void> renameSection(String sectionId, String name) async {
    await _db.execute(
      'UPDATE book_section SET name = ?, updated_at = ? WHERE id = ?',
      [name.trim(), _now(), sectionId],
    );
  }

  @override
  Future<void> reorderSections(
    String bookId,
    List<String> orderedSectionIds,
  ) async {
    final now = _now();
    await _db.writeTransaction((tx) async {
      for (var i = 0; i < orderedSectionIds.length; i++) {
        await tx.execute(
          'UPDATE book_section SET sort_order = ?, updated_at = ? '
          'WHERE id = ? AND book_id = ?',
          [i, now, orderedSectionIds[i], bookId],
        );
      }
    });
  }

  @override
  Future<void> deleteSection(String sectionId) async {
    final now = _now();
    await _db.execute(
      'UPDATE book_section SET deleted_at = ?, updated_at = ? WHERE id = ?',
      [now, now, sectionId],
    );
  }

  Future<int> _nextSortOrder(
    String table,
    String where, [
    List<Object?> params = const [],
  ]) async {
    final row = await _db.get(
      'SELECT COALESCE(MAX(sort_order), -1) AS m FROM $table WHERE $where',
      params,
    );
    return (row['m'] as int) + 1;
  }

  String _now() => DateTime.now().toUtc().toIso8601String();
}
