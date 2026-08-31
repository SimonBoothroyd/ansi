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

import '../../../core/units/macros.dart';
import '../../../core/units/measure.dart';
import '../../../core/units/units.dart';
import '../domain/method_step.dart';
import '../domain/recipe.dart';
import '../domain/recipe_macros.dart';
import '../domain/recipe_repository.dart';

class SqliteRecipeRepository implements RecipeRepository {
  const SqliteRecipeRepository(this._db, {required String householdId})
    : _householdId = householdId;

  final SqliteConnection _db;

  /// The household stamped on rows this repo writes.
  final String _householdId;

  @override
  Stream<List<RecipeSummary>> watchRecipes() {
    // The summaries carry computed per-serving macros (step 7.7), so the
    // watch must fire on any change to the tables the load below reads —
    // groups, line items, the vocab (macros/basis/density/status) and the
    // measures. Each LEFT JOIN contributes a *selected* column: SQLite omits
    // a join whose columns go unused, and an omitted join is an undetected
    // table (the stale-breadcrumb class). Rows are ignored; each fire
    // re-loads.
    return _db
        .watch(
          'SELECT r.id, g.id, li.id, ing.id, im.id FROM recipe r '
          'LEFT JOIN ingredient_group g ON g.recipe_id = r.id '
          'LEFT JOIN recipe_line_item li ON li.group_id = g.id '
          'LEFT JOIN ingredient ing ON ing.id = li.ingredient_id '
          'LEFT JOIN ingredient_measure im ON im.id = li.measure_id '
          'WHERE r.deleted_at IS NULL',
        )
        .asyncMap((_) => _loadSummaries());
  }

  Future<List<RecipeSummary>> _loadSummaries() async {
    final recipeRows = await _db.getAll(
      'SELECT id, title, servings_base, keeps_for_days, freezable, '
      'freezer_days, favorite FROM recipe '
      'WHERE deleted_at IS NULL ORDER BY created_at DESC',
    );
    // Every live line item with its ingredient's nutrition and (when
    // resolved) its measure, in one pass across all recipes.
    final lineRows = await _db.getAll(
      'SELECT g.recipe_id, li.id, li.ingredient_id, li.quantity, li.unit, '
      'li.measure_id, im.label AS m_label, im.basis_amount AS m_amount, '
      'im.sort_order AS m_sort, im.source AS m_source, '
      'ing.macros, ing.macros_basis, ing.density_g_per_ml, ing.status '
      'FROM recipe_line_item li '
      'JOIN ingredient_group g ON g.id = li.group_id AND g.deleted_at IS NULL '
      'LEFT JOIN ingredient ing '
      'ON ing.id = li.ingredient_id AND ing.deleted_at IS NULL '
      'LEFT JOIN ingredient_measure im '
      'ON im.id = li.measure_id AND im.deleted_at IS NULL '
      'WHERE li.deleted_at IS NULL',
    );

    final linesByRecipe = <String, List<LineItem>>{};
    final nutritionByIngredient = <String, IngredientNutrition>{};
    for (final r in lineRows) {
      final measureId = r['measure_id'] as String?;
      final measureLabel = r['m_label'] as String?;
      final measureAmount = (r['m_amount'] as num?)?.toDouble();
      (linesByRecipe[r['recipe_id'] as String] ??= []).add(
        LineItem(
          id: r['id'] as String,
          ingredientId: r['ingredient_id'] as String,
          ingredientName: '',
          unit: unitById(r['unit'] as String) ?? pieces,
          quantity: (r['quantity'] as num?)?.toDouble(),
          measureId: measureId,
          // Full construction incl. sort_order/source (the 51c80b9 rule:
          // every loader selects what Measure's == compares).
          measure:
              measureId == null || measureLabel == null || measureAmount == null
              ? null
              : Measure(
                  id: measureId,
                  label: measureLabel,
                  amount: measureAmount,
                  // The line ingredient's basis denominates its measures
                  // (ADR-0008); a tombstoned ingredient falls back per-g.
                  basis: MacrosBasis.fromDb(r['macros_basis'] as String?),
                  sortOrder: (r['m_sort'] as int?) ?? 0,
                  source: r['m_source'] as String?,
                ),
        ),
      );
      // A tombstoned/unknown ingredient never lands here (LEFT JOIN nulls its
      // status), so the lookup below treats its lines as stubs.
      if (r['status'] != null) {
        nutritionByIngredient[r['ingredient_id'] as String] = (
          // A stub's macros are excluded even if a value lingers on the row —
          // status is the source of truth for completeness (invariant 3).
          macros: r['status'] == 'complete'
              ? Macros.tryParse(r['macros'] as String?)
              : null,
          basis: MacrosBasis.fromDb(r['macros_basis'] as String?),
          densityGPerMl: (r['density_g_per_ml'] as num?)?.toDouble(),
        );
      }
    }

    return [
      for (final r in recipeRows)
        RecipeSummary(
          id: r['id'] as String,
          title: r['title'] as String,
          servingsBase: (r['servings_base'] as num).toDouble(),
          keepsForDays: r['keeps_for_days'] as int?,
          freezable: (r['freezable'] as int? ?? 0) == 1,
          freezerDays: r['freezer_days'] as int?,
          favorite: (r['favorite'] as int? ?? 0) == 1,
          macros: summarizeRecipeMacros(
            servingsBase: (r['servings_base'] as num).toDouble(),
            lines: linesByRecipe[r['id']] ?? const [],
            nutritionOf: (id) => nutritionByIngredient[id],
          ),
        ),
    ];
  }

  @override
  Stream<Recipe?> watchRecipe(String id) {
    // The triggers for this stream are the watched query's source tables, so
    // every table [_loadRecipe] reads must be one — including ingredient
    // (line-item names AND the nutrition behind the macro panel, so a vocab
    // row gaining macros/density re-fires the page) and book/section (the
    // breadcrumb). Each joined table
    // must also contribute a *selected* column: SQLite omits a LEFT JOIN whose
    // columns go unused, and an omitted join is an undetected table (the
    // stale-breadcrumb class). The rows themselves are ignored; each fire
    // re-assembles the recipe.
    return _db
        .watch(
          'SELECT r.id, g.id, li.id, ing.canonical_name, im.label, b.name, '
          's.name '
          'FROM recipe r '
          'LEFT JOIN ingredient_group g ON g.recipe_id = r.id '
          'LEFT JOIN recipe_line_item li ON li.group_id = g.id '
          'LEFT JOIN ingredient ing ON ing.id = li.ingredient_id '
          'LEFT JOIN ingredient_measure im ON im.id = li.measure_id '
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
      // The nutrition columns feed the recipe page's macro panel (step 9) —
      // the same summation the picker rows use, so the two agree.
      'SELECT li.*, ing.canonical_name AS ingredient_name, '
      'ing.macros_basis AS ingredient_basis, ing.macros AS ingredient_macros, '
      'ing.density_g_per_ml AS ingredient_density, '
      'ing.status AS ingredient_status, '
      'ing.deleted_at AS ingredient_deleted_at, '
      'im.label AS measure_label, im.basis_amount AS measure_amount, '
      'im.sort_order AS measure_sort, im.source AS measure_source '
      'FROM recipe_line_item li '
      'JOIN ingredient_group g ON g.id = li.group_id '
      'LEFT JOIN ingredient ing ON ing.id = li.ingredient_id '
      'LEFT JOIN ingredient_measure im '
      'ON im.id = li.measure_id AND im.deleted_at IS NULL '
      'WHERE g.recipe_id = ? AND li.deleted_at IS NULL '
      'ORDER BY li.sort_order, li.created_at',
      [id],
    );

    final itemsByGroup = <String, List<LineItem>>{};
    final lines = <LineItem>[];
    final nutritionByIngredient = <String, IngredientNutrition>{};
    for (final row in itemRows) {
      final line = _toLineItem(row);
      lines.add(line);
      (itemsByGroup[row['group_id'] as String] ??= []).add(line);
      // A tombstoned or unknown ingredient contributes no nutrition, so its
      // lines read as stubs and the panel says so — matching what the picker
      // rows do for the same recipe (its LEFT JOIN nulls the status instead).
      if (row['ingredient_status'] != null &&
          row['ingredient_deleted_at'] == null) {
        nutritionByIngredient[row['ingredient_id'] as String] = (
          // A stub's macros are excluded even if a value lingers on the row —
          // status is the source of truth for completeness (invariant 3).
          macros: row['ingredient_status'] == 'complete'
              ? Macros.tryParse(row['ingredient_macros'] as String?)
              : null,
          basis: MacrosBasis.fromDb(row['ingredient_basis'] as String?),
          densityGPerMl: (row['ingredient_density'] as num?)?.toDouble(),
        );
      }
    }

    final (plainSteps, methodSteps) = _parseSteps(r['steps'] as String?);
    return Recipe(
      id: r['id'] as String,
      title: r['title'] as String,
      servingsBase: (r['servings_base'] as num).toDouble(),
      steps: plainSteps,
      methodSteps: methodSteps,
      keepsForDays: r['keeps_for_days'] as int?,
      freezable: (r['freezable'] as int? ?? 0) == 1,
      freezerDays: r['freezer_days'] as int?,
      bookId: r['book_id'] as String?,
      sectionId: r['section_id'] as String?,
      bookName: r['book_name'] as String?,
      sectionName: r['section_name'] as String?,
      macros: summarizeRecipeMacros(
        servingsBase: (r['servings_base'] as num).toDouble(),
        lines: lines,
        nutritionOf: (id) => nutritionByIngredient[id],
      ),
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

  LineItem _toLineItem(Row r) {
    // The measure resolves only when its row is live locally; the raw
    // measure_id is kept regardless so a save never strips it (see [LineItem]).
    final measureId = r['measure_id'] as String?;
    final measureLabel = r['measure_label'] as String?;
    final measureAmount = (r['measure_amount'] as num?)?.toDouble();
    return LineItem(
      id: r['id'] as String,
      ingredientId: r['ingredient_id'] as String,
      ingredientName: r['ingredient_name'] as String? ?? '(unknown ingredient)',
      unit: unitById(r['unit'] as String) ?? pieces,
      quantity: (r['quantity'] as num?)?.toDouble(),
      measureId: measureId,
      measure:
          measureId == null || measureLabel == null || measureAmount == null
          ? null
          : Measure(
              id: measureId,
              label: measureLabel,
              amount: measureAmount,
              // The line ingredient's basis denominates its measures
              // (ADR-0008); a tombstoned ingredient falls back per-g.
              basis: MacrosBasis.fromDb(r['ingredient_basis'] as String?),
              sortOrder: (r['measure_sort'] as int?) ?? 0,
              source: r['measure_source'] as String?,
            ),
      note: r['note'] as String?,
    );
  }

  /// Reads the `steps` jsonb, which holds one of two shapes ([mise-data-
  /// ephemeral], no coexistence): a legacy array of plain-text strings (the
  /// editor) or an array of tokenized step objects (import, step 8). A string
  /// element ⇒ plain text; an object with `tokens` ⇒ tokenized.
  (List<String>, List<MethodStep>?) _parseSteps(String? raw) {
    final decoded = jsonDecode(raw ?? '[]');
    if (decoded is! List || decoded.isEmpty) return (const [], null);
    if (decoded.first is String) return (decoded.cast<String>(), null);
    return (
      const <String>[],
      [
        for (final e in decoded)
          MethodStep.fromJson((e as Map).cast<String, Object?>()),
      ],
    );
  }

  /// What the `steps` jsonb is written as. The column holds ONE of two shapes
  /// ([mise-data-ephemeral], see [_parseSteps]), and a recipe carries whichever
  /// one it was loaded with: an imported recipe's [Recipe.methodSteps] is the
  /// tokenized shape and its plain [Recipe.steps] is empty, so serializing the
  /// plain list unconditionally would erase the imported method on the first
  /// save. The tokenized shape therefore wins whenever it is present.
  Object _stepsJson(Recipe recipe) {
    final tokenized = recipe.methodSteps;
    if (tokenized == null) return recipe.steps;
    return [for (final step in tokenized) step.toJson()];
  }

  @override
  Future<void> saveRecipe(Recipe recipe) async {
    final now = DateTime.now().toUtc().toIso8601String();
    final steps = jsonEncode(_stepsJson(recipe));
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
              'quantity = ?, unit = ?, measure_id = ?, note = ?, '
              'sort_order = ?, updated_at = ?, deleted_at = NULL WHERE id = ?',
              [
                group.id,
                item.ingredientId,
                item.quantity,
                item.unit.id,
                item.measureId,
                item.note,
                li,
                now,
                item.id,
              ],
            );
          } else {
            await tx.execute(
              'INSERT INTO recipe_line_item (id, household_id, group_id, '
              'ingredient_id, quantity, unit, measure_id, note, sort_order, '
              'created_at, updated_at) '
              'VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)',
              [
                item.id,
                _householdId,
                group.id,
                item.ingredientId,
                item.quantity,
                item.unit.id,
                item.measureId,
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
  Future<void> setFavorite(String id, bool favorite) async {
    final now = DateTime.now().toUtc().toIso8601String();
    await _db.execute(
      'UPDATE recipe SET favorite = ?, updated_at = ? WHERE id = ?',
      [if (favorite) 1 else 0, now, id],
    );
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
