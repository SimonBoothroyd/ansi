/// [WeekVariantRepository] over the local PowerSync SQLite.
///
/// Writes go through the local views, which reject UPSERT, so a save reads what
/// is stored, then UPDATEs rows that stay, INSERTs new ones and tombstones the
/// rest. A row that stays keeps its id, so the unique key `(week_plan, recipe,
/// line)` never races its own tombstones. The watch query selects a column from
/// every joined table: SQLite drops an unselected LEFT JOIN, and PowerSync
/// never fires on a dropped table.
library;

import 'package:sqlite3/common.dart' show Row;
import 'package:sqlite_async/sqlite_async.dart';
import 'package:uuid/uuid.dart';

import '../../../core/units/macros.dart';
import '../../../core/units/measure.dart';
import '../../../core/units/units.dart';
import '../../../core/week_shape.dart';
import '../../ingredients/data/price_repository_impl.dart'
    show loadLatestPrices;
import '../../recipes/data/recipe_repository_impl.dart'
    show loadRecipeMacroNodes, pricingResolver;
import '../../recipes/domain/effective_lines.dart';
import '../../recipes/domain/line_override.dart';
import '../../recipes/domain/recipe_cost.dart';
import '../../recipes/domain/recipe_macros.dart';
import '../domain/week_variant_repository.dart';
import 'planning_repository_impl.dart' show getOrCreateWeekPlan;

const _uuid = Uuid();

class SqliteWeekVariantRepository implements WeekVariantRepository {
  const SqliteWeekVariantRepository(this._db, {required String householdId})
    : _householdId = householdId;

  final SqliteConnection _db;

  /// The household stamped on rows this repo writes.
  final String _householdId;

  @override
  Stream<Map<String, List<LineOverride>>> watchWeekOverrides(
    DateTime weekStart,
  ) {
    final key = isoDateOf(weekStart);
    return _weekChanges(key).asyncMap((_) => _loadByRecipe(key));
  }

  /// Every table the two loads read, each contributing a selected column so
  /// SQLite keeps the join. The recipe tables are here because a varied recipe
  /// is re-summed off its own lines.
  Stream<void> _weekChanges(String weekKey) => _db.watch(
    'SELECT wp.id, wro.id, r.id, g.id, li.id, i.id, im.id, rm.id '
    'FROM week_plan wp '
    'LEFT JOIN week_recipe_line_override wro '
    'ON wro.week_plan_id = wp.id AND wro.deleted_at IS NULL '
    'LEFT JOIN recipe r ON 1 = 1 '
    'LEFT JOIN ingredient_group g ON g.recipe_id = r.id '
    'LEFT JOIN recipe_line_item li ON li.group_id = g.id '
    'LEFT JOIN ingredient i ON 1 = 1 '
    'LEFT JOIN ingredient_measure im ON 1 = 1 '
    // A recipe measure's weight changes what every measured component line
    // comes to.
    'LEFT JOIN recipe_measure rm ON 1 = 1 '
    'WHERE wp.week_start_date = ? AND wp.deleted_at IS NULL LIMIT 1',
    parameters: [weekKey],
  );

  @override
  Future<List<LineOverride>> loadOverrides(
    DateTime weekStart,
    String recipeId,
  ) async =>
      (await _loadByRecipe(isoDateOf(weekStart)))[recipeId] ??
      const <LineOverride>[];

  @override
  Stream<Map<String, RecipeMacroSummary>> watchVariantRecipeMacros(
    DateTime weekStart,
  ) {
    final key = isoDateOf(weekStart);
    return _weekChanges(key).asyncMap((_) => _loadVariantRecipeMacros(key));
  }

  @override
  Stream<Map<String, RecipeCostSummary>> watchVariantRecipeCosts(
    DateTime weekStart,
  ) {
    final key = isoDateOf(weekStart);
    // Prices ride the same watch: a new receipt changes a varied recipe's cost.
    return _priceChanges(key).asyncMap((_) => _loadVariantRecipeCosts(key));
  }

  /// [_weekChanges]'s tables plus the receipt rows a cost reads.
  Stream<void> _priceChanges(String weekKey) => _db.watch(
    'SELECT wp.id, wro.id, r.id, g.id, li.id, i.id, im.id, rm.id, '
    'rl.id, rc.id '
    'FROM week_plan wp '
    'LEFT JOIN week_recipe_line_override wro '
    'ON wro.week_plan_id = wp.id AND wro.deleted_at IS NULL '
    'LEFT JOIN recipe r ON 1 = 1 '
    'LEFT JOIN ingredient_group g ON g.recipe_id = r.id '
    'LEFT JOIN recipe_line_item li ON li.group_id = g.id '
    'LEFT JOIN ingredient i ON 1 = 1 '
    'LEFT JOIN ingredient_measure im ON 1 = 1 '
    'LEFT JOIN recipe_measure rm ON 1 = 1 '
    'LEFT JOIN receipt_line rl ON 1 = 1 '
    'LEFT JOIN receipt rc ON 1 = 1 '
    'WHERE wp.week_start_date = ? AND wp.deleted_at IS NULL LIMIT 1',
    parameters: [weekKey],
  );

  Future<Map<String, RecipeCostSummary>> _loadVariantRecipeCosts(
    String weekKey,
  ) async {
    final byRecipe = await _loadByRecipe(weekKey);
    if (byRecipe.isEmpty) return const {};
    final (nodes, nutrition) = await loadRecipeMacroNodes(_db);
    final pricingOf = pricingResolver(nutrition, await loadLatestPrices(_db));
    return {
      for (final entry in nodes.entries)
        if (byRecipe.containsKey(entry.key))
          entry.key: summarizeRecipeCost(
            servingsBase: entry.value.servingsBase,
            lines: effectiveLines(
              entry.value.lines,
              overrides: byRecipe[entry.key] ?? const [],
            ).kept,
            pricingOf: pricingOf,
            // A component is costed as the recipe stands, as its macros are.
            subRecipeOf: (id) => nodes[id],
          ),
    };
  }

  Future<Map<String, List<LineOverride>>> _loadByRecipe(String weekKey) =>
      loadWeekOverrides(_db, weekKey);

  Future<Map<String, RecipeMacroSummary>> _loadVariantRecipeMacros(
    String weekKey,
  ) async {
    final byRecipe = await _loadByRecipe(weekKey);
    // Most weeks have no variant; skip the whole-library summation.
    if (byRecipe.isEmpty) return const {};
    final (nodes, nutrition) = await loadRecipeMacroNodes(_db);
    return {
      for (final entry in nodes.entries)
        if (byRecipe.containsKey(entry.key))
          entry.key: summarizeRecipeMacros(
            servingsBase: entry.value.servingsBase,
            // Excluded lines gone, replaced lines carrying their values, added
            // lines present.
            lines: effectiveLines(
              entry.value.lines,
              overrides: byRecipe[entry.key] ?? const [],
            ).kept,
            nutritionOf: (id) => nutrition[id],
            // A component is summed as the recipe stands: a variant is per
            // (week, recipe), so a sub-recipe's own variant belongs to its own
            // figure.
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
    final key = isoDateOf(weekStart);
    // Refused before anything is written: a row the server's
    // `week_recipe_line_override_amount_pair` rejects makes the connector drop
    // the whole crud transaction.
    for (final override in overrides) {
      if (override.recipeMeasureId != null && override.quantity == null) {
        throw WordlessOverrideError(
          overrideId: override.id,
          recipeMeasureId: override.recipeMeasureId!,
        );
      }
    }
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
      // What is stored, keyed by recipe line for a delta and by row id for an
      // addition.
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
        // A word is only sayable about a component, and the unit column is then
        // null (the server's pair rule). Resolved once so both statements bind
        // the same values.
        final recipeMeasureId = override.subRecipeId == null
            ? null
            : override.recipeMeasureId;
        final unitId = recipeMeasureId != null ? null : override.unit?.id;
        final values = [
          override.action.name,
          line,
          override.ingredientId,
          override.subRecipeId,
          override.quantity,
          unitId,
          override.measureId,
          recipeMeasureId,
          override.note,
          override.sortOrder,
          now,
        ];
        if (existing != null) {
          await tx.execute(
            'UPDATE week_recipe_line_override SET action = ?, '
            'recipe_line_item_id = ?, ingredient_id = ?, sub_recipe_id = ?, '
            'quantity = ?, unit = ?, measure_id = ?, recipe_measure_id = ?, '
            'note = ?, sort_order = ?, updated_at = ? WHERE id = ?',
            [...values, id],
          );
        } else {
          await tx.execute(
            'INSERT INTO week_recipe_line_override (id, household_id, '
            'week_plan_id, recipe_id, action, recipe_line_item_id, '
            'ingredient_id, sub_recipe_id, quantity, unit, measure_id, '
            'recipe_measure_id, note, '
            'sort_order, created_at, updated_at) '
            'VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)',
            // The same [values] the UPDATE binds (last element is the
            // `updated_at` stamp), so the two statements cannot drift.
            [id, _householdId, weekId, recipeId, ...values, now],
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

  @override
  Future<void> setLineIncluded(
    DateTime weekStart,
    String recipeId,
    String lineId, {
    required bool included,
  }) async {
    final stored = await loadOverrides(weekStart, recipeId);
    final next = _lineIncluded(stored, lineId, included: included);
    // Nothing to change, so nothing is written.
    if (next == null) return;
    await saveOverrides(weekStart, recipeId, overrides: next);
  }
}

/// [stored] with one line's `include` row added or removed, or null when
/// nothing changes. An include replaces an exclusion of the same line. A
/// `replace` row is left alone: it already keeps the line, and overwriting it
/// would drop its stated amount.
List<LineOverride>? _lineIncluded(
  List<LineOverride> stored,
  String lineId, {
  required bool included,
}) {
  final standing = stored
      .where((o) => o.recipeLineItemId == lineId)
      .firstOrNull;
  if (included) {
    if (standing != null &&
        (standing.action == LineOverrideAction.include ||
            standing.carriesValues)) {
      return null;
    }
    return [
      for (final o in stored)
        if (o.recipeLineItemId != lineId) o,
      LineOverride(
        action: LineOverrideAction.include,
        recipeLineItemId: lineId,
      ),
    ];
  }
  if (standing?.action != LineOverrideAction.include) return null;
  return [
    for (final o in stored)
      if (o.recipeLineItemId != lineId) o,
  ];
}

/// One week's whole variant, by recipe id. Shared by the shop, the cook plan
/// and this repository.
Future<Map<String, List<LineOverride>>> loadWeekOverrides(
  SqliteConnection db,
  String weekKey,
) async {
  final rows = await db.getAll(
    // `wp.week_start_date` is selected as well as filtered on, so SQLite keeps
    // the join and the watch fires for it.
    'SELECT wp.week_start_date, '
    'wro.id, wro.recipe_id, wro.recipe_line_item_id, wro.action, '
    'wro.ingredient_id, wro.sub_recipe_id, wro.quantity, wro.unit, '
    'wro.note, wro.sort_order, wro.measure_id, wro.recipe_measure_id, '
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
  final recipeMeasureId = r['recipe_measure_id'] as String?;
  return LineOverride(
    id: r['id'] as String,
    action: _actionOf(r['action'] as String),
    recipeLineItemId: r['recipe_line_item_id'] as String?,
    ingredientId: r['ingredient_id'] as String?,
    // Empty until the vocab row syncs; the line then reads as the recipe's own
    // name.
    ingredientName: r['ing_name'] as String? ?? '',
    subRecipeId: r['sub_recipe_id'] as String?,
    quantity: (r['quantity'] as num?)?.toDouble(),
    // An unknown unit id stays null, never a `pieces` fallback a total could
    // sum. Null beside a word too: `recipe_measure_id` means the amount is in
    // the target's word, and the word is read first.
    unit: recipeMeasureId != null ? null : unitById(r['unit'] as String? ?? ''),
    measureId: measureId,
    // Absolute, like every value here: re-weighing the word later leaves this
    // week's count alone.
    recipeMeasureId: recipeMeasureId,
    measure: measureId == null || measureLabel == null || measureAmount == null
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

/// An action this client does not know reads as `include`, which changes no
/// total. Never a guess at what a newer client meant.
LineOverrideAction _actionOf(String stored) => switch (stored) {
  'exclude' => LineOverrideAction.exclude,
  'replace' => LineOverrideAction.replace,
  'add' => LineOverrideAction.add,
  _ => LineOverrideAction.include,
};
