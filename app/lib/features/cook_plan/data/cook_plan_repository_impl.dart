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

import '../../planning/domain/planning.dart' show mondayOf;
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
    return _db
        .watch(
          'SELECT wp.id, pe.id, r.keeps_for_days FROM week_plan wp '
          'LEFT JOIN plan_entry pe '
          'ON pe.week_plan_id = wp.id AND pe.deleted_at IS NULL '
          'LEFT JOIN recipe r ON r.id = pe.recipe_id '
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
    return buildCookPlan(planned);
  }
}
