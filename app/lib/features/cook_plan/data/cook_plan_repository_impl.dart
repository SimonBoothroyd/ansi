/// [CookPlanRepository] over the local PowerSync SQLite (offline in step 5).
///
/// Read-only: the cook plan is derived, so this class never writes. It watches
/// the week's `plan_entry` rows joined to `recipe` shelf life, assembles one
/// [PlannedRecipe] per recipe, and hands them to the pure [buildCookPlan]. The
/// watch query names every table the load reads (and selects a column from each
/// joined one) so PowerSync re-fires on any relevant change — the LEFT JOIN
/// pitfall the planner hit ([[mise-powersync-watch-left-join]]).
library;

import 'dart:convert';

import 'package:sqlite_async/sqlite_async.dart';

import '../../../core/units/units.dart';
import '../../planning/domain/planning.dart' show mondayOf;
import '../../recipes/domain/component_math.dart';
import '../domain/cook_plan.dart';
import '../domain/cook_plan_repository.dart';

class SqliteCookPlanRepository implements CookPlanRepository {
  const SqliteCookPlanRepository(this._db);

  final SqliteConnection _db;

  String _weekKey(DateTime weekStart) {
    final m = mondayOf(weekStart);
    final mm = m.month.toString().padLeft(2, '0');
    final dd = m.day.toString().padLeft(2, '0');
    return '${m.year}-$mm-$dd';
  }

  @override
  Stream<CookPlan> watchCookPlan(DateTime weekStart) {
    final key = _weekKey(weekStart);
    // Reference week_plan + plan_entry + recipe and select a column from each,
    // so a change to any (including a recipe's shelf life) re-derives the plan.
    // Since 8.6 the groups and line items join too: a component line — or the
    // yield it resolves against — moves the derived component sessions, so a
    // change to either must re-fire.
    return _db
        .watch(
          'SELECT wp.id, pe.id, r.keeps_for_days, g.id, li.id '
          'FROM week_plan wp '
          'LEFT JOIN plan_entry pe '
          'ON pe.week_plan_id = wp.id AND pe.deleted_at IS NULL '
          'LEFT JOIN recipe r ON r.id = pe.recipe_id '
          'LEFT JOIN ingredient_group g ON g.recipe_id = r.id '
          'LEFT JOIN recipe_line_item li ON li.group_id = g.id '
          'WHERE wp.week_start_date = ? AND wp.deleted_at IS NULL LIMIT 1',
          parameters: [key],
        )
        .asyncMap((_) => _load(key));
  }

  Future<CookPlan> _load(String weekKey) async {
    // One row per planned meal, carrying its recipe's shelf life. A meal whose
    // recipe was deleted (r.id null) can't be cooked, so it's filtered out.
    final rows = await _db.getAll(
      'SELECT pe.day_of_week, pe.meal_slot, pe.eaters, pe.portions, '
      'r.id AS recipe_id, r.title, r.servings_base, r.keeps_for_days, '
      'r.freezable, r.freezer_days '
      'FROM week_plan wp '
      'JOIN plan_entry pe ON pe.week_plan_id = wp.id AND pe.deleted_at IS NULL '
      'JOIN recipe r ON r.id = pe.recipe_id AND r.deleted_at IS NULL '
      'WHERE wp.week_start_date = ? AND wp.deleted_at IS NULL '
      'ORDER BY pe.day_of_week, pe.sort_order, pe.created_at',
      [weekKey],
    );

    // Group meals by recipe, preserving first-seen recipe order (buildCookPlan
    // re-orders by cook day anyway).
    final byRecipe = <String, PlannedRecipe>{};
    final meals = <String, List<CoveredMeal>>{};
    for (final row in rows) {
      final recipeId = row['recipe_id'] as String;
      final eaters = jsonDecode(row['eaters'] as String? ?? '[]') as List;
      final portions = (row['portions'] as int?) ?? eaters.length;
      byRecipe[recipeId] ??= PlannedRecipe(
        recipeId: recipeId,
        title: row['title'] as String,
        servingsBase: (row['servings_base'] as num).toDouble(),
        keepsForDays: row['keeps_for_days'] as int?,
        freezable: (row['freezable'] as int? ?? 0) == 1,
        freezerDays: row['freezer_days'] as int?,
      );
      (meals[recipeId] ??= []).add(
        CoveredMeal(
          dayOfWeek: row['day_of_week'] as int,
          mealSlot: row['meal_slot'] as String,
          portions: portions,
        ),
      );
    }

    final planned = [
      for (final entry in byRecipe.entries)
        entry.value.copyWith(meals: meals[entry.key] ?? const []),
    ];
    return buildCookPlan(planned, components: await loadComponentGraph(_db));
  }
}

/// The household's component graph (step 8.6 / D3): every LIVE recipe keyed by
/// id, with its yields and the component lines it is built from.
///
/// Read whole rather than walked query-by-query: the walk is depth-first over
/// a graph a household holds entirely in local SQLite, and two round trips
/// beat one per edge. Shared by the cook-plan and shopping repositories, which
/// derive the same sessions from the same rows.
///
/// A recipe with no component lines still appears — it is a possible *target*,
/// and its yields are what a referencing line resolves against.
Future<Map<String, ComponentRecipe>> loadComponentGraph(
  SqliteConnection db,
) async {
  final componentRows = await db.getAll(
    'SELECT g.recipe_id, li.sub_recipe_id, li.quantity, li.unit '
    'FROM recipe_line_item li '
    'JOIN ingredient_group g ON g.id = li.group_id AND g.deleted_at IS NULL '
    'WHERE li.deleted_at IS NULL AND li.sub_recipe_id IS NOT NULL '
    'ORDER BY li.sort_order, li.created_at',
  );
  final componentsByRecipe = <String, List<ComponentLine>>{};
  for (final row in componentRows) {
    // An unknown persisted unit id is NOT defaulted to anything: a `pieces`
    // fallback would invent the semantics the whole resolver exists to refuse.
    // The line simply derives nothing (invariant 3).
    final unit = unitById(row['unit'] as String? ?? '');
    if (unit == null) continue;
    (componentsByRecipe[row['recipe_id'] as String] ??= []).add((
      subRecipeId: row['sub_recipe_id'] as String,
      quantity: (row['quantity'] as num?)?.toDouble(),
      unit: unit,
    ));
  }

  final recipeRows = await db.getAll(
    'SELECT r.id, r.title, r.servings_base, r.keeps_for_days, r.freezable, '
    'r.freezer_days, r.yield_qty, r.yield_unit, r.yield_qty_2, r.yield_unit_2 '
    'FROM recipe r WHERE r.deleted_at IS NULL',
  );
  return {
    for (final r in recipeRows)
      r['id'] as String: (
        title: r['title'] as String,
        servingsBase: (r['servings_base'] as num).toDouble(),
        keepsForDays: r['keeps_for_days'] as int?,
        freezable: (r['freezable'] as int? ?? 0) == 1,
        freezerDays: r['freezer_days'] as int?,
        yields: yieldDenominations(
          (r['yield_qty'] as num?)?.toDouble(),
          unitById(r['yield_unit'] as String? ?? ''),
          (r['yield_qty_2'] as num?)?.toDouble(),
          unitById(r['yield_unit_2'] as String? ?? ''),
        ),
        components: componentsByRecipe[r['id']] ?? const <ComponentLine>[],
      ),
  };
}
