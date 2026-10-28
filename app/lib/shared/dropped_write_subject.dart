/// What a refused write changed, in the user's nouns: the thing's name, the
/// kind of change, and the page that opens it.
///
/// The connector discards a refused transaction, but the row it wrote is still
/// in the local database, so the name and the page are a local read. A row
/// that is gone (a refused hard delete, a parent deleted since) falls back to
/// a plain noun for its kind and opens nothing.
library;

import 'package:meta/meta.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:sqlite_async/sqlite_async.dart';

import '../core/sync/database.dart';
import '../core/sync/dropped_write.dart';
import '../core/week_shape.dart';
import '../core/words.dart';

part 'dropped_write_subject.g.dart';

/// One refused write, as the "Didn’t sync" sheet lists it.
@immutable
class DroppedWriteSubject {
  const DroppedWriteSubject({
    required this.name,
    required this.kind,
    this.route,
  });

  /// The subject when nothing could be read: the kind's plain noun, no page.
  factory DroppedWriteSubject.unfound(String table) => DroppedWriteSubject(
    name: _unfoundName(table),
    kind: droppedWriteKind(table),
  );

  /// `Weeknight Chicken Curry`, `Tuesday dinner`; `A recipe` when the row is
  /// gone.
  final String name;

  /// `recipe edit`, `meal change`, …: what sort of change was refused.
  final String kind;

  /// Where the thing is edited, so saving it there again is the retry. Null
  /// when there is no such page any more.
  final String? route;

  @override
  bool operator ==(Object other) =>
      other is DroppedWriteSubject &&
      other.name == name &&
      other.kind == kind &&
      other.route == route;

  @override
  int get hashCode => Object.hash(name, kind, route);

  @override
  String toString() => 'DroppedWriteSubject($name, $kind, $route)';
}

/// The kind of change a write to [table] is, in the user's words.
String droppedWriteKind(String table) => switch (table) {
  'recipe' ||
  'ingredient_group' ||
  'recipe_line_item' ||
  'recipe_measure' => 'recipe edit',
  'week_recipe_line_override' => 'this-week edit',
  'plan_entry' => 'meal change',
  'meal_eaten' => 'meal eaten',
  'batch_leftover' => 'leftovers',
  'week_plan' => 'week change',
  'shopping_list_entry' ||
  'shopping_list_contribution' => 'shopping list change',
  'receipt' || 'receipt_line' => 'receipt edit',
  'ingredient' ||
  'ingredient_alias' ||
  'ingredient_measure' => 'ingredient edit',
  'book' || 'book_section' => 'book change',
  'household_member' => 'portion change',
  'household' => 'household change',
  _ => 'change',
};

String _unfoundName(String table) => switch (table) {
  'recipe' ||
  'ingredient_group' ||
  'recipe_line_item' ||
  'recipe_measure' ||
  'week_recipe_line_override' => 'A recipe',
  'plan_entry' || 'meal_eaten' || 'batch_leftover' => 'A meal',
  'week_plan' => 'A week',
  'shopping_list_entry' || 'shopping_list_contribution' => 'A shopping item',
  'receipt' || 'receipt_line' => 'A receipt',
  'ingredient' || 'ingredient_alias' || 'ingredient_measure' => 'An ingredient',
  'book' || 'book_section' => 'A book',
  'household_member' => 'A household member',
  'household' => 'Your household',
  _ => 'A change',
};

/// Names [write]'s subject from the local database. Never throws: a read that
/// fails is a row that cannot be found.
Future<DroppedWriteSubject> describeDroppedWrite(
  SqliteReadContext db,
  DroppedWrite write,
) async {
  final unfound = DroppedWriteSubject.unfound(write.table);
  final kind = unfound.kind;
  final id = write.rowId;
  try {
    final found = switch (write.table) {
      'recipe' => await _recipe(db, kind, id),
      'ingredient_group' || 'recipe_measure' => await _recipe(
        db,
        kind,
        await _parent(db, write.table, 'recipe_id', id),
      ),
      'recipe_line_item' => await _recipe(
        db,
        kind,
        await _string(
          db,
          'SELECT g.recipe_id AS v FROM recipe_line_item l '
          'JOIN ingredient_group g ON g.id = l.group_id WHERE l.id = ?',
          id,
        ),
      ),
      'week_recipe_line_override' => await _weekOverride(db, kind, id),
      'plan_entry' => await _meal(db, kind, id),
      'meal_eaten' || 'batch_leftover' => await _meal(
        db,
        kind,
        await _parent(db, write.table, 'plan_entry_id', id),
      ),
      'week_plan' => await _week(db, kind, id),
      'shopping_list_entry' => await _shopItem(db, kind, id),
      'shopping_list_contribution' => await _shopItem(
        db,
        kind,
        await _parent(db, write.table, 'entry_id', id),
      ),
      'receipt' => await _receipt(db, kind, id),
      'receipt_line' => await _receipt(
        db,
        kind,
        await _parent(db, write.table, 'receipt_id', id),
      ),
      'ingredient' => await _ingredient(db, kind, id),
      'ingredient_alias' || 'ingredient_measure' => await _ingredient(
        db,
        kind,
        await _parent(db, write.table, 'ingredient_id', id),
      ),
      'book' => await _book(db, kind, id),
      'book_section' => await _book(
        db,
        kind,
        await _parent(db, write.table, 'book_id', id),
      ),
      'household_member' => await _named(
        db,
        kind,
        'SELECT display_name AS name FROM household_member WHERE id = ?',
        id,
        route: '/account',
      ),
      'household' => await _named(
        db,
        kind,
        'SELECT name FROM household WHERE id = ?',
        id,
        route: '/account',
      ),
      _ => null,
    };
    return found ?? unfound;
  } on Object {
    return unfound;
  }
}

/// [column] of row [id] in [table], a parent's id. [table] and [column] come
/// from the switch above, never from the write.
Future<String?> _parent(
  SqliteReadContext db,
  String table,
  String column,
  String id,
) => _string(db, 'SELECT $column AS v FROM $table WHERE id = ?', id);

Future<String?> _string(SqliteReadContext db, String sql, String? id) async {
  if (id == null) return null;
  final row = await db.getOptional(sql, [id]);
  return row?['v'] as String?;
}

/// A named row whose page is [route], or no page once the row is deleted.
Future<DroppedWriteSubject?> _named(
  SqliteReadContext db,
  String kind,
  String sql,
  String? id, {
  required String route,
  bool deletable = false,
}) async {
  if (id == null) return null;
  final row = await db.getOptional(sql, [id]);
  final name = (row?['name'] as String?)?.trim();
  if (row == null || name == null || name.isEmpty) return null;
  final gone = deletable && row['deleted_at'] != null;
  return DroppedWriteSubject(
    name: name,
    kind: kind,
    route: gone ? null : route,
  );
}

Future<DroppedWriteSubject?> _recipe(
  SqliteReadContext db,
  String kind,
  String? id,
) => _named(
  db,
  kind,
  'SELECT title AS name, deleted_at FROM recipe WHERE id = ?',
  id,
  route: '/recipes/$id',
  deletable: true,
);

Future<DroppedWriteSubject?> _ingredient(
  SqliteReadContext db,
  String kind,
  String? id,
) => _named(
  db,
  kind,
  'SELECT canonical_name AS name, deleted_at FROM ingredient WHERE id = ?',
  id,
  route: '/ingredients/$id',
  deletable: true,
);

Future<DroppedWriteSubject?> _book(
  SqliteReadContext db,
  String kind,
  String? id,
) => _named(
  db,
  kind,
  'SELECT name, deleted_at FROM book WHERE id = ?',
  id,
  route: '/books/$id',
  deletable: true,
);

Future<DroppedWriteSubject?> _receipt(
  SqliteReadContext db,
  String kind,
  String? id,
) => _named(
  db,
  kind,
  'SELECT store AS name, deleted_at FROM receipt WHERE id = ?',
  id,
  route: '/receipts/$id',
  deletable: true,
);

/// A this-week edit is named by its recipe and opens that recipe in its week.
Future<DroppedWriteSubject?> _weekOverride(
  SqliteReadContext db,
  String kind,
  String id,
) async {
  final row = await db.getOptional(
    'SELECT o.recipe_id, w.week_start_date FROM week_recipe_line_override o '
    'JOIN week_plan w ON w.id = o.week_plan_id WHERE o.id = ?',
    [id],
  );
  final recipeId = row?['recipe_id'] as String?;
  final week = row?['week_start_date'] as String?;
  final recipe = await _recipe(db, kind, recipeId);
  if (recipe == null || recipe.route == null || week == null) return recipe;
  return DroppedWriteSubject(
    name: recipe.name,
    kind: kind,
    route: Uri(path: recipe.route, queryParameters: {'week': week}).toString(),
  );
}

/// A meal is named by its day and slot (`Tuesday dinner`), or by its day and
/// what it is when it has no slot, and opens its week on that day.
Future<DroppedWriteSubject?> _meal(
  SqliteReadContext db,
  String kind,
  String? id,
) async {
  if (id == null) return null;
  final row = await db.getOptional(
    'SELECT pe.day_of_week, pe.meal_slot, w.week_start_date, '
    'COALESCE(r.title, i.canonical_name, pe.label) AS what '
    'FROM plan_entry pe JOIN week_plan w ON w.id = pe.week_plan_id '
    'LEFT JOIN recipe r ON r.id = pe.recipe_id '
    'LEFT JOIN ingredient i ON i.id = pe.ingredient_id '
    'WHERE pe.id = ?',
    [id],
  );
  final week = row?['week_start_date'] as String?;
  final start = week == null ? null : DateTime.tryParse(week);
  final offset = row?['day_of_week'] as int?;
  if (row == null || week == null || start == null || offset == null) {
    return null;
  }
  // The week's own first day is the shape its offsets count from.
  final shape = WeekShape(start.weekday);
  final day = shape.labelFull(offset);
  final slot = (row['meal_slot'] as String?)?.trim() ?? '';
  final what = (row['what'] as String?)?.trim() ?? '';
  final name = slot.isNotEmpty
      ? '$day ${slot.toLowerCase()}'
      : what.isNotEmpty
      ? '$day · $what'
      : day;
  return DroppedWriteSubject(
    name: name,
    kind: kind,
    route: Uri(
      path: '/week',
      queryParameters: {
        'week': week,
        'day': isoDateOf(shape.dateFor(start, offset)),
      },
    ).toString(),
  );
}

Future<DroppedWriteSubject?> _week(
  SqliteReadContext db,
  String kind,
  String id,
) async {
  final week = await _string(
    db,
    'SELECT week_start_date AS v FROM week_plan WHERE id = ?',
    id,
  );
  final start = week == null ? null : DateTime.tryParse(week);
  if (week == null || start == null) return null;
  return DroppedWriteSubject(
    name: 'Week of ${formatDayMonth(start)}',
    kind: kind,
    route: Uri(path: '/week', queryParameters: {'week': week}).toString(),
  );
}

/// A list item is named by its ingredient or its words, and opens its week's
/// list.
Future<DroppedWriteSubject?> _shopItem(
  SqliteReadContext db,
  String kind,
  String? id,
) async {
  if (id == null) return null;
  final row = await db.getOptional(
    'SELECT COALESCE(i.canonical_name, e.free_text) AS name, '
    'e.week_start_date FROM shopping_list_entry e '
    'LEFT JOIN ingredient i ON i.id = e.ingredient_id WHERE e.id = ?',
    [id],
  );
  final name = (row?['name'] as String?)?.trim();
  if (row == null || name == null || name.isEmpty) return null;
  final week = row['week_start_date'] as String?;
  return DroppedWriteSubject(
    name: name,
    kind: kind,
    route: week == null
        ? '/shop'
        : Uri(path: '/shop', queryParameters: {'week': week}).toString(),
  );
}

/// [write]'s subject, read once from the local database.
@riverpod
Future<DroppedWriteSubject> droppedWriteSubject(Ref ref, DroppedWrite write) =>
    describeDroppedWrite(ref.watch(databaseProvider), write);
