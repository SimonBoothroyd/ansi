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

  /// The household stamped on rows this repo writes (injected — the app passes
  /// the signed-in household, tests pass their own).
  final String _householdId;

  @override
  Stream<Map<String, List<LineOverride>>> watchWeekOverrides(
    DateTime weekStart,
  ) {
    final key = isoDateOf(weekStart);
    return _weekChanges(key).asyncMap((_) => _loadByRecipe(key));
  }

  /// Every table the two loads read, each contributing a SELECTed column so
  /// SQLite keeps its join and PowerSync registers it as a trigger. The
  /// recipe/group/line tables are in here for the macro summation, which
  /// re-sums a varied recipe off its own lines.
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
    // A recipe's own words: re-stating `blob` moves what every measured
    // component line comes to, so a varied recipe's re-summation has to
    // re-run for it exactly as it does for a changed line.
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
    // The prices ride the same watch: a receipt landing changes what a varied
    // recipe costs this week exactly as an override does.
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
            // A component is costed as the recipe stands, for the reason its
            // macros are summed that way.
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
            // A component is summed as the recipe stands. A variant is one set
            // per (week, recipe), so a sub-recipe's own set belongs to the
            // sub-recipe's figure, not to this one; re-targeting the link here
            // would make a week's total disagree with the page it came from.
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
    // Refused before anything is written, for the reason `saveRecipe` states:
    // `week_recipe_line_override_amount_pair` rejects the upload, and a
    // rejected upload makes the connector drop the WHOLE crud transaction —
    // so one malformed delta would take every write queued beside it.
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
        // A word is only sayable about a COMPONENT, and beside it the unit
        // column goes null: 0048's pair rule, resolved here so the two
        // statements below cannot read the delta differently. `include` and
        // `exclude` carry no target at all (0040's `action_shape`), so they
        // can never carry a word either.
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
            // The same [values] the UPDATE binds, whose last element is the
            // `updated_at` stamp — so the two statements cannot drift on which
            // columns a delta carries, which is how `recipe_measure_id` came
            // to be missing from one of them in the first place.
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
    // Nothing to say: the week already reads the way the tap asked for, and a
    // save would tombstone and re-insert rows for no change at all.
    if (next == null) return;
    await saveOverrides(weekStart, recipeId, overrides: next);
  }
}

/// [stored] with one line's `include` row added or removed — or null when the
/// set already says what the tap asked for.
///
/// A one-tap door hands the repository a decision, not a diff, so this is the
/// whole edit: an optional line the recipe would drop gains an
/// [LineOverrideAction.include]; the same tap on a line the week EXCLUDES
/// replaces that exclusion, which is the other side of the same question.
///
/// A row that carries values of its own is left alone: a `replace` already
/// keeps the line this week, and overwriting it with a bare include would
/// throw away the amount somebody stated.
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

/// One week's whole variant, by recipe id — the loader the shop, the cook plan
/// and this repository share, so the three derivations cannot read the week's
/// deltas three slightly different ways.
///
/// One query: a week holds a handful of changed lines, so there is nothing to
/// page and nothing to narrow.
Future<Map<String, List<LineOverride>>> loadWeekOverrides(
  SqliteConnection db,
  String weekKey,
) async {
  final rows = await db.getAll(
    // `wp.week_start_date` is selected as well as filtered on: an unselected
    // join is one SQLite drops, and a dropped join is a table the watch never
    // fires for.
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
    // The vocab row's name, or nothing: a row that has not synced leaves the
    // line reading as the recipe's own name rather than as an empty cell.
    ingredientName: r['ing_name'] as String? ?? '',
    subRecipeId: r['sub_recipe_id'] as String?,
    quantity: (r['quantity'] as num?)?.toDouble(),
    // An unknown persisted unit id stays null — never a `pieces` fallback,
    // which would let a total sum an invented unit (invariant 3). It is null
    // on purpose beside a word, too: `recipe_measure_id` set means the amount
    // is said in the target's own word and in no unit at all (0048's pair
    // rule), and the word is asked first so a row carrying both is read as
    // the word rather than the unit.
    unit: recipeMeasureId != null ? null : unitById(r['unit'] as String? ?? ''),
    measureId: measureId,
    // This week's own word for the amount — absolute like every other value
    // here: the recipe re-stating `blob` later leaves this week at the count
    // somebody asked for.
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

/// An action this client does not know is not a delta it can apply, so the row
/// is read as an exclusion of nothing: `include` on a line it is about changes
/// no total. Never a guess at what a newer client meant.
LineOverrideAction _actionOf(String stored) => switch (stored) {
  'exclude' => LineOverrideAction.exclude,
  'replace' => LineOverrideAction.replace,
  'add' => LineOverrideAction.add,
  _ => LineOverrideAction.include,
};
