/// [RecipeRepository] over the local PowerSync SQLite (offline in step 2).
///
/// Reads assemble the recipe/group/line-item rows into the domain aggregate and
/// react to local writes via `watch`. Writes go through `saveRecipe`, which
/// diffs a recipe's children against the stored tree (see the interface doc)
/// inside a transaction. Deletes are soft (tombstone), per spec §3.
library;

import 'dart:convert';

import 'package:sqlite3/common.dart' show Row;
import 'package:sqlite_async/sqlite_async.dart';

import '../../../core/units/units.dart';
import '../domain/recipe.dart';
import '../domain/recipe_repository.dart';

class SqliteRecipeRepository implements RecipeRepository {
  const SqliteRecipeRepository(this._db, {required String householdId})
    : _householdId = householdId;

  final SqliteConnection _db;

  /// The household stamped on rows this repo writes.
  final String _householdId;

  @override
  Stream<List<RecipeSummary>> watchRecipes() {
    return _db
        .watch(
          'SELECT id, title, servings_base, keeps_for_days, freezable, '
          'freezer_days FROM recipe '
          'WHERE deleted_at IS NULL ORDER BY created_at DESC',
        )
        .map(
          (rows) => rows
              .map(
                (r) => RecipeSummary(
                  id: r['id'] as String,
                  title: r['title'] as String,
                  servingsBase: (r['servings_base'] as num).toDouble(),
                  keepsForDays: r['keeps_for_days'] as int?,
                  freezable: (r['freezable'] as int? ?? 0) == 1,
                  freezerDays: r['freezer_days'] as int?,
                ),
              )
              .toList(),
        );
  }

  @override
  Stream<Recipe?> watchRecipe(String id) {
    // The triggers for this stream are the watched query's source tables, so
    // every table [_loadRecipe] reads must be one — including ingredient
    // (line-item names) and book/section (the breadcrumb). Each joined table
    // must also contribute a *selected* column: SQLite omits a LEFT JOIN whose
    // columns go unused, and an omitted join is an undetected table (the
    // stale-breadcrumb class). The rows themselves are ignored; each fire
    // re-assembles the recipe.
    return _db
        .watch(
          'SELECT r.id, g.id, li.id, ing.canonical_name, b.name, s.name '
          'FROM recipe r '
          'LEFT JOIN ingredient_group g ON g.recipe_id = r.id '
          'LEFT JOIN recipe_line_item li ON li.group_id = g.id '
          'LEFT JOIN ingredient ing ON ing.id = li.ingredient_id '
          'LEFT JOIN book b ON b.id = r.book_id '
          'LEFT JOIN book_section s ON s.id = r.section_id '
          'WHERE r.id = ? AND r.deleted_at IS NULL LIMIT 1',
          parameters: [id],
        )
        .asyncMap((_) => _loadRecipe(id));
  }

  Future<Recipe?> _loadRecipe(String id) async {
    final r = await _db.getOptional(
      // Join the filing book/section for the recipe page's hero line. LEFT
      // joins + deleted_at guards so a deleted section (or none) reads as null.
      'SELECT r.*, b.name AS book_name, s.name AS section_name '
      'FROM recipe r '
      'LEFT JOIN book b ON b.id = r.book_id AND b.deleted_at IS NULL '
      'LEFT JOIN book_section s '
      'ON s.id = r.section_id AND s.deleted_at IS NULL '
      'WHERE r.id = ? AND r.deleted_at IS NULL',
      [id],
    );
    if (r == null) return null;

    final groupRows = await _db.getAll(
      'SELECT * FROM ingredient_group '
      'WHERE recipe_id = ? AND deleted_at IS NULL '
      'ORDER BY sort_order, created_at',
      [id],
    );
    final itemRows = await _db.getAll(
      'SELECT li.*, ing.canonical_name AS ingredient_name '
      'FROM recipe_line_item li '
      'JOIN ingredient_group g ON g.id = li.group_id '
      'LEFT JOIN ingredient ing ON ing.id = li.ingredient_id '
      'WHERE g.recipe_id = ? AND li.deleted_at IS NULL '
      'ORDER BY li.sort_order, li.created_at',
      [id],
    );

    final itemsByGroup = <String, List<LineItem>>{};
    for (final row in itemRows) {
      (itemsByGroup[row['group_id'] as String] ??= []).add(_toLineItem(row));
    }

    return Recipe(
      id: r['id'] as String,
      title: r['title'] as String,
      servingsBase: (r['servings_base'] as num).toDouble(),
      steps: (jsonDecode(r['steps'] as String? ?? '[]') as List).cast<String>(),
      keepsForDays: r['keeps_for_days'] as int?,
      freezable: (r['freezable'] as int? ?? 0) == 1,
      freezerDays: r['freezer_days'] as int?,
      bookId: r['book_id'] as String?,
      sectionId: r['section_id'] as String?,
      bookName: r['book_name'] as String?,
      sectionName: r['section_name'] as String?,
      groups: [
        for (final g in groupRows)
          IngredientGroup(
            id: g['id'] as String,
            name: g['name'] as String?,
            items: itemsByGroup[g['id']] ?? const [],
          ),
      ],
    );
  }

  LineItem _toLineItem(Row r) => LineItem(
    id: r['id'] as String,
    ingredientId: r['ingredient_id'] as String,
    ingredientName: r['ingredient_name'] as String? ?? '(unknown ingredient)',
    unit: unitById(r['unit'] as String) ?? pieces,
    quantity: (r['quantity'] as num?)?.toDouble(),
    note: r['note'] as String?,
  );

  @override
  Future<void> saveRecipe(Recipe recipe) async {
    final now = DateTime.now().toUtc().toIso8601String();
    final steps = jsonEncode(recipe.steps);
    final freezable = recipe.freezable ? 1 : 0;
    await _db.writeTransaction((tx) async {
      // PowerSync's local tables are SQLite VIEWS with INSTEAD OF triggers,
      // which do NOT support `INSERT ... ON CONFLICT` (UPSERT). Branch on
      // existence and issue a plain INSERT or UPDATE instead.
      final exists = await tx.getOptional('SELECT 1 FROM recipe WHERE id = ?', [
        recipe.id,
      ]);
      if (exists == null) {
        await tx.execute(
          'INSERT INTO recipe (id, household_id, title, servings_base, steps, '
          'keeps_for_days, freezable, freezer_days, book_id, section_id, '
          'created_at, updated_at) '
          'VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)',
          [
            recipe.id,
            _householdId,
            recipe.title,
            recipe.servingsBase,
            steps,
            recipe.keepsForDays,
            freezable,
            recipe.freezerDays,
            recipe.bookId,
            recipe.sectionId,
            now,
            now,
          ],
        );
      } else {
        await tx.execute(
          'UPDATE recipe SET title = ?, servings_base = ?, steps = ?, '
          'keeps_for_days = ?, freezable = ?, freezer_days = ?, book_id = ?, '
          'section_id = ?, updated_at = ? WHERE id = ?',
          [
            recipe.title,
            recipe.servingsBase,
            steps,
            recipe.keepsForDays,
            freezable,
            recipe.freezerDays,
            recipe.bookId,
            recipe.sectionId,
            now,
            recipe.id,
          ],
        );
      }

      // Diff the children against the stored tree instead of delete +
      // re-insert: PowerSync queues ops literally (a DELETE then a PUT of the
      // same id, no consolidation), and the connector maps DELETE to a
      // server-side tombstone — so replacing kept ids would soft-delete them
      // on the server and every other device. Kept ids become UPDATEs, new
      // ids INSERTs, and dropped ids soft-deletes.
      final oldGroupRows = await tx.getAll(
        'SELECT id, deleted_at FROM ingredient_group WHERE recipe_id = ?',
        [recipe.id],
      );
      final oldItemRows = await tx.getAll(
        'SELECT li.id, li.deleted_at FROM recipe_line_item li '
        'JOIN ingredient_group g ON g.id = li.group_id WHERE g.recipe_id = ?',
        [recipe.id],
      );
      final oldGroupIds = {for (final r in oldGroupRows) r['id'] as String};
      final oldItemIds = {for (final r in oldItemRows) r['id'] as String};
      final keptGroupIds = {for (final g in recipe.groups) g.id};
      final keptItemIds = {
        for (final g in recipe.groups)
          for (final i in g.items) i.id,
      };

      // Soft-delete dropped children (items first — they hang off the groups).
      // Rows that are already tombstoned are left alone rather than re-stamped.
      for (final r in oldItemRows) {
        final id = r['id'] as String;
        if (!keptItemIds.contains(id) && r['deleted_at'] == null) {
          await tx.execute(
            'UPDATE recipe_line_item SET deleted_at = ?, updated_at = ? '
            'WHERE id = ?',
            [now, now, id],
          );
        }
      }
      for (final r in oldGroupRows) {
        final id = r['id'] as String;
        if (!keptGroupIds.contains(id) && r['deleted_at'] == null) {
          await tx.execute(
            'UPDATE ingredient_group SET deleted_at = ?, updated_at = ? '
            'WHERE id = ?',
            [now, now, id],
          );
        }
      }

      for (var gi = 0; gi < recipe.groups.length; gi++) {
        final group = recipe.groups[gi];
        if (oldGroupIds.contains(group.id)) {
          // Clearing deleted_at revives a group whose id is being reused.
          await tx.execute(
            'UPDATE ingredient_group SET name = ?, sort_order = ?, '
            'updated_at = ?, deleted_at = NULL WHERE id = ?',
            [group.name, gi, now, group.id],
          );
        } else {
          await tx.execute(
            'INSERT INTO ingredient_group (id, household_id, recipe_id, name, '
            'sort_order, created_at, updated_at) VALUES (?, ?, ?, ?, ?, ?, ?)',
            [group.id, _householdId, recipe.id, group.name, gi, now, now],
          );
        }
        for (var li = 0; li < group.items.length; li++) {
          final item = group.items[li];
          if (oldItemIds.contains(item.id)) {
            // group_id is included: an item can move between groups.
            await tx.execute(
              'UPDATE recipe_line_item SET group_id = ?, ingredient_id = ?, '
              'quantity = ?, unit = ?, note = ?, sort_order = ?, '
              'updated_at = ?, deleted_at = NULL WHERE id = ?',
              [
                group.id,
                item.ingredientId,
                item.quantity,
                item.unit.id,
                item.note,
                li,
                now,
                item.id,
              ],
            );
          } else {
            await tx.execute(
              'INSERT INTO recipe_line_item (id, household_id, group_id, '
              'ingredient_id, quantity, unit, note, sort_order, created_at, '
              'updated_at) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)',
              [
                item.id,
                _householdId,
                group.id,
                item.ingredientId,
                item.quantity,
                item.unit.id,
                item.note,
                li,
                now,
                now,
              ],
            );
          }
        }
      }
    });
  }

  @override
  Future<void> deleteRecipe(String id) async {
    final now = DateTime.now().toUtc().toIso8601String();
    await _db.execute(
      'UPDATE recipe SET deleted_at = ?, updated_at = ? WHERE id = ?',
      [now, now, id],
    );
  }
}
