/// [WeekVariantRepository] over the local PowerSync SQLite.
///
/// Writes go through the local VIEWS, so no UPSERT (a view rejects
/// `ON CONFLICT`): making the stored set equal the handed set is a read of
/// what is there, an UPDATE per row that stays, an INSERT per row that is new,
/// and a tombstone per row that went.
///
/// A row that stays keeps its id. That is what makes the unique key
/// `(week_plan, recipe, line)` survive repeated saves instead of racing
/// against its own tombstones, and it is why an added line's override id is
/// minted when the line is DRAFTED rather than when it is stored.
///
/// One watch query serves both streams, and it names every table the two
/// loads read while selecting a column from each: SQLite drops a LEFT JOIN
/// whose columns go unused, and a dropped join is a table PowerSync never
/// fires on.
library;

import 'package:sqlite3/common.dart' show Row;
import 'package:sqlite_async/sqlite_async.dart';
import 'package:uuid/uuid.dart';

import '../../../core/units/macros.dart';
import '../../../core/units/measure.dart';
import '../../../core/units/units.dart';
import '../../recipes/data/recipe_repository_impl.dart'
    show loadRecipeMacroNodes;
import '../../recipes/domain/effective_lines.dart';
import '../../recipes/domain/line_override.dart';
import '../../recipes/domain/recipe_macros.dart';
import '../domain/planning.dart' show weekKeyOf;
import '../domain/week_variant_repository.dart';
import 'planning_repository_impl.dart' show getOrCreateWeekPlan;

const _uuid = Uuid();

class SqliteWeekVariantRepository implements WeekVariantRepository {
  const SqliteWeekVariantRepository(this._db, {required String householdId})
    : _householdId = householdId;

  final SqliteConnection _db;

  /// The household stamped on rows this repo writes (injected — the app passes
  /// the signed-in household, tests pass their own).
  final String _householdId;

  @override
  Stream<Map<String, List<LineOverride>>> watchWeekOverrides(
    DateTime weekStart,
  ) {
    final key = weekKeyOf(weekStart);
    return _weekChanges(key).asyncMap((_) => _loadByRecipe(key));
  }

  /// Every table the two loads read, each contributing a SELECTed column so
  /// SQLite keeps its join and PowerSync registers it as a trigger. The
  /// recipe/group/line tables are in here for the macro summation, which
  /// re-sums a varied recipe off its own lines.
  Stream<void> _weekChanges(String weekKey) => _db.watch(
    'SELECT wp.id, wro.id, r.id, g.id, li.id, i.id, im.id '
    'FROM week_plan wp '
    'LEFT JOIN week_recipe_line_override wro '
    'ON wro.week_plan_id = wp.id AND wro.deleted_at IS NULL '
    'LEFT JOIN recipe r ON 1 = 1 '
    'LEFT JOIN ingredient_group g ON g.recipe_id = r.id '
    'LEFT JOIN recipe_line_item li ON li.group_id = g.id '
    'LEFT JOIN ingredient i ON 1 = 1 '
    'LEFT JOIN ingredient_measure im ON 1 = 1 '
    'WHERE wp.week_start_date = ? AND wp.deleted_at IS NULL LIMIT 1',
    parameters: [weekKey],
  );

  @override
  Future<List<LineOverride>> loadOverrides(
    DateTime weekStart,
    String recipeId,
  ) async =>
      (await _loadByRecipe(weekKeyOf(weekStart)))[recipeId] ??
      const <LineOverride>[];

  @override
  Stream<Map<String, RecipeMacroSummary>> watchVariantRecipeMacros(
    DateTime weekStart,
  ) {
    final key = weekKeyOf(weekStart);
    return _weekChanges(key).asyncMap((_) => _loadVariantRecipeMacros(key));
  }

  /// The week's whole variant, by recipe. One query: a week holds a handful of
  /// changed lines, so there is nothing to page and nothing to narrow.
  Future<Map<String, List<LineOverride>>> _loadByRecipe(String weekKey) async {
    final rows = await _db.getAll(
      // `wp.week_start_date` is selected as well as filtered on: an
      // unselected join is one SQLite drops, and a dropped join is a table
      // the watch never fires for.
      'SELECT wp.week_start_date, '
      'wro.id, wro.recipe_id, wro.recipe_line_item_id, wro.action, '
      'wro.ingredient_id, wro.sub_recipe_id, wro.quantity, wro.unit, '
      'wro.note, wro.sort_order, wro.measure_id, '
      'ing.canonical_name AS ing_name, ing.macros_basis, '
      'im.label AS m_label, im.basis_amount AS m_amount, '
      'im.sort_order AS m_sort, im.source AS m_source '
      'FROM week_recipe_line_override wro '
      'JOIN week_plan wp ON wp.id = wro.week_plan_id AND wp.deleted_at IS NULL '
      'LEFT JOIN ingredient ing '
      'ON ing.id = wro.ingredient_id AND ing.deleted_at IS NULL '
      'LEFT JOIN ingredient_measure im '
      'ON im.id = wro.measure_id AND im.deleted_at IS NULL '
      'WHERE wp.week_start_date = ? AND wro.deleted_at IS NULL '
      'ORDER BY wro.sort_order, wro.created_at',
      [weekKey],
    );
    final byRecipe = <String, List<LineOverride>>{};
    for (final r in rows) {
      (byRecipe[r['recipe_id'] as String] ??= []).add(_overrideFrom(r));
    }
    return byRecipe;
  }

  LineOverride _overrideFrom(Row r) {
    final measureId = r['measure_id'] as String?;
    final measureLabel = r['m_label'] as String?;
    final measureAmount = (r['m_amount'] as num?)?.toDouble();
    return LineOverride(
      id: r['id'] as String,
      action: _actionOf(r['action'] as String),
      recipeLineItemId: r['recipe_line_item_id'] as String?,
      ingredientId: r['ingredient_id'] as String?,
      // The vocab row's name, or nothing: a row that has not synced leaves the
      // line reading as the recipe's own name rather than as an empty cell.
      ingredientName: r['ing_name'] as String? ?? '',
      subRecipeId: r['sub_recipe_id'] as String?,
      quantity: (r['quantity'] as num?)?.toDouble(),
      // An unknown persisted unit id stays null — never a `pieces` fallback,
      // which would let a total sum an invented unit (invariant 3).
      unit: unitById(r['unit'] as String? ?? ''),
      measureId: measureId,
      measure:
          measureId == null || measureLabel == null || measureAmount == null
          ? null
          : Measure(
              id: measureId,
              label: measureLabel,
              amount: measureAmount,
              basis: MacrosBasis.fromDb(r['macros_basis'] as String?),
              sortOrder: (r['m_sort'] as int?) ?? 0,
              source: r['m_source'] as String?,
            ),
      note: r['note'] as String?,
      sortOrder: r['sort_order'] as int?,
    );
  }

  /// An action this client does not know is not a delta it can apply, so the
  /// row is read as an exclusion of nothing: `include` on a line it is about
  /// changes no total. Never a guess at what a newer client meant.
  static LineOverrideAction _actionOf(String stored) => switch (stored) {
    'exclude' => LineOverrideAction.exclude,
    'replace' => LineOverrideAction.replace,
    'add' => LineOverrideAction.add,
    _ => LineOverrideAction.include,
  };

  Future<Map<String, RecipeMacroSummary>> _loadVariantRecipeMacros(
    String weekKey,
  ) async {
    final byRecipe = await _loadByRecipe(weekKey);
    // The common week has no variant at all, and a whole-library summation on
    // every fire of this watch would be a real cost for nothing.
    if (byRecipe.isEmpty) return const {};
    final (nodes, nutrition) = await loadRecipeMacroNodes(_db);
    return {
      for (final entry in nodes.entries)
        if (byRecipe.containsKey(entry.key))
          entry.key: summarizeRecipeMacros(
            servingsBase: entry.value.servingsBase,
            // The seam, with this week's answer: an excluded line is gone, a
            // replaced one carries its absolute values, an added one is there.
            // The summation runs the seam again over what comes back and finds
            // nothing left to drop, which is why the two rules compose.
            lines: effectiveLines(
              entry.value.lines,
              overrides: byRecipe[entry.key] ?? const [],
            ).kept,
            nutritionOf: (id) => nutrition[id],
            // A component is summed as the recipe stands: the component graph
            // is read household-wide with no week, so a week's variant of a
            // sub-recipe would make it week-dependent (0043 D7).
            subRecipeOf: (id) => nodes[id],
          ),
    };
  }

  @override
  Future<void> saveOverrides(
    DateTime weekStart,
    String recipeId, {
    required List<LineOverride> overrides,
  }) async {
    final key = weekKeyOf(weekStart);
    final now = DateTime.now().toUtc().toIso8601String();
    await _db.writeTransaction((tx) async {
      final weekId = await getOrCreateWeekPlan(
        tx,
        weekKey: key,
        householdId: _householdId,
      );
      final stored = await tx.getAll(
        'SELECT id, recipe_line_item_id FROM week_recipe_line_override '
        'WHERE week_plan_id = ? AND recipe_id = ? AND deleted_at IS NULL',
        [weekId, recipeId],
      );
      // What is already standing, by the thing that identifies it: the recipe
      // line for a delta about one, the row's own id for an addition.
      final byLine = <String, String>{};
      final addIds = <String>{};
      for (final r in stored) {
        final line = r['recipe_line_item_id'] as String?;
        if (line == null) {
          addIds.add(r['id'] as String);
        } else {
          byLine[line] = r['id'] as String;
        }
      }

      final kept = <String>{};
      for (final override in overrides) {
        final line = override.recipeLineItemId;
        final existing = line == null
            ? (addIds.contains(override.id) ? override.id : null)
            : byLine[line];
        final id = existing ?? (line == null ? override.id : _uuid.v4());
        kept.add(id);
        final values = [
          override.action.name,
          line,
          override.ingredientId,
          override.subRecipeId,
          override.quantity,
          override.unit?.id,
          override.measureId,
          override.note,
          override.sortOrder,
          now,
        ];
        if (existing != null) {
          await tx.execute(
            'UPDATE week_recipe_line_override SET action = ?, '
            'recipe_line_item_id = ?, ingredient_id = ?, sub_recipe_id = ?, '
            'quantity = ?, unit = ?, measure_id = ?, note = ?, '
            'sort_order = ?, updated_at = ? WHERE id = ?',
            [...values, id],
          );
        } else {
          await tx.execute(
            'INSERT INTO week_recipe_line_override (id, household_id, '
            'week_plan_id, recipe_id, action, recipe_line_item_id, '
            'ingredient_id, sub_recipe_id, quantity, unit, measure_id, note, '
            'sort_order, created_at, updated_at) '
            'VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)',
            [
              id,
              _householdId,
              weekId,
              recipeId,
              override.action.name,
              line,
              override.ingredientId,
              override.subRecipeId,
              override.quantity,
              override.unit?.id,
              override.measureId,
              override.note,
              override.sortOrder,
              now,
              now,
            ],
          );
        }
      }

      for (final r in stored) {
        final id = r['id'] as String;
        if (kept.contains(id)) continue;
        await tx.execute(
          'UPDATE week_recipe_line_override SET deleted_at = ?, '
          'updated_at = ? WHERE id = ?',
          [now, now, id],
        );
      }
    });
  }
}
