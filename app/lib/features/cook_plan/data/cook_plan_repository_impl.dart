/// [CookPlanRepository] over the local PowerSync SQLite. The plan is read,
/// never written.
///
/// The watch query must select a column from every joined table: SQLite drops a
/// LEFT JOIN with no selected column, and that table then never re-fires the
/// watch.
library;

import 'dart:convert';

import 'package:sqlite_async/sqlite_async.dart';

import '../../../core/units/recipe_measure.dart';
import '../../../core/units/units.dart';
import '../../../core/week_shape.dart';
import '../../planning/data/planning_repository_impl.dart' show loadMembers;
import '../../planning/data/week_variant_repository_impl.dart'
    show loadWeekOverrides;
import '../../planning/domain/planning.dart'
    show PlanEntry, eatersDemand, memberServings;
import '../../recipes/data/recipe_measure_repository_impl.dart'
    show loadRecipeMeasures;
import '../../recipes/domain/component_math.dart';
import '../domain/cook_plan.dart';
import '../domain/cook_plan_repository.dart';

class SqliteCookPlanRepository implements CookPlanRepository {
  const SqliteCookPlanRepository(this._db);

  final SqliteConnection _db;

  @override
  Stream<CookPlan> watchCookPlan(DateTime weekStart) {
    final key = isoDateOf(weekStart);
    // Every table whose change moves the plan is joined with a column selected:
    // week, entries, recipes, groups and line items (component lines and
    // yields), `household_member` (portion factors; cross-joined, it is not
    // tied to the week) and the week's line overrides. A watch re-runs on any
    // write to a table it reads, so the neighbouring weeks' meals and ticks,
    // which fold across the week edge, re-derive it too.
    return _db
        .watch(
          'SELECT wp.id, pe.id, r.keeps_for_days, g.id, li.id, hm.id, '
          'wro.id, rm.id, me.id '
          'FROM week_plan wp '
          'LEFT JOIN plan_entry pe '
          'ON pe.week_plan_id = wp.id AND pe.deleted_at IS NULL '
          // Who ate each meal moves what is left of its batch.
          'LEFT JOIN meal_eaten me ON me.plan_entry_id = pe.id '
          'LEFT JOIN week_recipe_line_override wro '
          'ON wro.week_plan_id = wp.id AND wro.deleted_at IS NULL '
          'LEFT JOIN recipe r ON r.id = pe.recipe_id '
          'LEFT JOIN ingredient_group g ON g.recipe_id = r.id '
          'LEFT JOIN recipe_line_item li ON li.group_id = g.id '
          // A recipe measure changes what a measured component line demands.
          // Not tied to the week, so cross-joined purely to be watched.
          'LEFT JOIN recipe_measure rm ON 1 = 1 '
          'LEFT JOIN household_member hm ON 1 = 1 '
          'WHERE wp.week_start_date = ? AND wp.deleted_at IS NULL LIMIT 1',
          parameters: [key],
        )
        .asyncMap((_) => _load(key));
  }

  Future<CookPlan> _load(String weekKey) => loadCookPlan(_db, weekKey);
}

/// The derived cook plan of the week keyed [weekKey], read once. Without
/// [components] the sub-recipes' sessions are left out: the leftovers read
/// only the meal batches.
Future<CookPlan> loadCookPlan(
  SqliteConnection db,
  String weekKey, {
  bool components = true,
}) async {
  final planned = await loadPlannedWeek(db, weekKey);
  // The graph as THIS week cooks it: an optional sub-recipe opens a session
  // only where the week ticked it in, and one the week left out opens none.
  return buildCookPlan(
    planned.recipes,
    components: components
        ? componentGraphForWeek(
            await loadComponentGraph(db),
            await loadWeekOverrides(db, weekKey),
          )
        : const {},
    foldedBack: planned.foldedBack,
  );
}

/// The week keyed [weekKey]'s recipe meals as its batches cook them, across
/// both week edges ([plannedAcrossWeeks]): the one read the cook plan and the
/// shop share, so a meal the week before cooks is skipped by both, and a meal
/// of the next week this week cooks is bought here.
///
/// [leaveOut] names meals to read as not planned, in this week or the next.
Future<({List<PlannedRecipe> recipes, Map<String, CookSession> foldedBack})>
loadPlannedWeek(
  SqliteConnection db,
  String weekKey, {
  Set<String> leaveOut = const {},
}) async {
  final start = DateTime.parse(weekKey);
  String keyOf(int weeks) =>
      isoDateOf(DateTime(start.year, start.month, start.day + 7 * weeks));
  final keys = [keyOf(-2), keyOf(-1), weekKey, keyOf(1)];
  final weeks = await _loadWeeksMeals(db, keys);
  List<PlannedRecipe> without(List<PlannedRecipe>? recipes) => [
    for (final r in recipes ?? const <PlannedRecipe>[])
      r.copyWith(
        meals: [
          for (final m in r.meals)
            if (!leaveOut.contains(m.entryId)) m,
        ],
      ),
  ];
  return plannedAcrossWeeks(
    twoWeeksBefore: weeks[keys[0]] ?? const [],
    weekBefore: weeks[keys[1]] ?? const [],
    week: without(weeks[weekKey]),
    weekAfter: without(weeks[keys[3]]),
  );
}

/// The cooked recipe meals of each week in [weekKeys], grouped by recipe and
/// keyed by week, each with what its eaters said they ate.
Future<Map<String, List<PlannedRecipe>>> _loadWeeksMeals(
  SqliteConnection db,
  List<String> weekKeys,
) async {
  final marks = List.filled(weekKeys.length, '?').join(', ');
  // One row per planned recipe meal with its recipe's shelf life. Ingredient
  // meals and meals out are not cooked; `recipe_id IS NOT NULL` states that
  // explicitly beside the inner join.
  final rows = await db.getAll(
    'SELECT pe.id, wp.week_start_date, pe.day_of_week, pe.meal_slot, '
    'pe.eaters, pe.portions, '
    'r.id AS recipe_id, r.title, r.servings_base, r.keeps_for_days, '
    'r.freezable, r.freezer_days '
    'FROM week_plan wp '
    'JOIN plan_entry pe ON pe.week_plan_id = wp.id AND pe.deleted_at IS NULL '
    'JOIN recipe r ON r.id = pe.recipe_id AND r.deleted_at IS NULL '
    'WHERE wp.week_start_date IN ($marks) AND wp.deleted_at IS NULL '
    'AND pe.recipe_id IS NOT NULL '
    // What a member had instead of a meal was never cooked, and a meal from
    // a leftover (a batch or a fridge or freezer row) was cooked already.
    'AND pe.instead_of IS NULL AND pe.leftover_of IS NULL '
    'AND pe.from_leftover IS NULL '
    'ORDER BY pe.day_of_week, pe.sort_order, pe.created_at',
    weekKeys,
  );
  // Who said they ate each meal, for what is left of its batch.
  final ticks = <String, Set<String>>{};
  for (final t in await db.getAll(
    'SELECT me.plan_entry_id, me.member_id FROM meal_eaten me '
    'JOIN plan_entry pe ON pe.id = me.plan_entry_id '
    'JOIN week_plan wp ON wp.id = pe.week_plan_id '
    'WHERE wp.week_start_date IN ($marks) AND me.deleted_at IS NULL',
    weekKeys,
  )) {
    (ticks[t['plan_entry_id'] as String] ??= {}).add(t['member_id'] as String);
  }

  // A meal's demand is the sum of its eaters' portion factors unless the
  // entry overrides it: the same `eatersDemand` the Week reads.
  final members = {for (final m in await loadMembers(db)) m.id: m};

  // Group meals by week and recipe, preserving first-seen recipe order
  // (buildCookPlan re-orders by cook day anyway).
  final byRecipe = <String, Map<String, PlannedRecipe>>{};
  final meals = <String, Map<String, List<CoveredMeal>>>{};
  for (final row in rows) {
    final week = row['week_start_date'] as String;
    final recipeId = row['recipe_id'] as String;
    final eaters = (jsonDecode(row['eaters'] as String? ?? '[]') as List)
        .cast<String>();
    final portions =
        (row['portions'] as int?)?.toDouble() ?? eatersDemand(eaters, members);
    (byRecipe[week] ??= {})[recipeId] ??= PlannedRecipe(
      recipeId: recipeId,
      title: row['title'] as String,
      servingsBase: (row['servings_base'] as num).toDouble(),
      keepsForDays: row['keeps_for_days'] as int?,
      freezable: (row['freezable'] as int? ?? 0) == 1,
      freezerDays: row['freezer_days'] as int?,
    );
    // The share each eater who ticked it ate — the lens's own rule.
    final entry = PlanEntry(
      id: row['id'] as String,
      dayOfWeek: row['day_of_week'] as int,
      mealSlot: row['meal_slot'] as String,
      eaterIds: eaters,
      portions: row['portions'] as int?,
    );
    final eaten = [
      for (final m in eaters)
        if (ticks[entry.id]?.contains(m) ?? false)
          memberServings(entry, m, members),
    ].fold<double>(0, (a, b) => a + b);
    ((meals[week] ??= {})[recipeId] ??= []).add(
      CoveredMeal(
        dayOfWeek: entry.dayOfWeek,
        mealSlot: entry.mealSlot,
        portions: portions,
        entryId: entry.id,
        eatenPortions: eaten > portions ? portions : eaten,
      ),
    );
  }

  return {
    for (final MapEntry(key: week, value: recipes) in byRecipe.entries)
      week: [
        for (final entry in recipes.entries)
          entry.value.copyWith(meals: meals[week]?[entry.key] ?? const []),
      ],
  };
}

/// The household's component graph: every live recipe keyed by id, with its
/// yields and component lines. Shared by the cook-plan and shopping
/// repositories.
///
/// Read whole rather than per edge. A recipe with no component lines still
/// appears, as a possible target. The graph is week-blind: callers pass it to
/// [componentGraphForWeek].
Future<Map<String, ComponentRecipe>> loadComponentGraph(
  SqliteConnection db,
) async {
  final componentRows = await db.getAll(
    'SELECT g.recipe_id, li.id, li.sub_recipe_id, li.quantity, li.unit, '
    'li.recipe_measure_id, li.optional '
    'FROM recipe_line_item li '
    'JOIN ingredient_group g ON g.id = li.group_id AND g.deleted_at IS NULL '
    'WHERE li.deleted_at IS NULL AND li.sub_recipe_id IS NOT NULL '
    'ORDER BY li.sort_order, li.created_at',
  );
  final componentsByRecipe = <String, List<ComponentLine>>{};
  for (final row in componentRows) {
    // An unknown persisted unit id is NOT defaulted to anything: a `pieces`
    // fallback would invent the semantics the whole resolver exists to refuse.
    final recipeMeasureId = row['recipe_measure_id'] as String?;
    final unit = recipeMeasureId != null
        ? null
        : unitById(row['unit'] as String? ?? '');
    // Neither a unit nor a word: the line derives nothing. A line said in one
    // of the target's words must flow through, to resolve or surface as
    // `ComponentMeasureMissing`.
    if (unit == null && recipeMeasureId == null) continue;
    (componentsByRecipe[row['recipe_id'] as String] ??= []).add((
      id: row['id'] as String,
      subRecipeId: row['sub_recipe_id'] as String,
      quantity: (row['quantity'] as num?)?.toDouble(),
      unit: unit,
      recipeMeasureId: recipeMeasureId,
      optional: (row['optional'] as int? ?? 0) == 1,
    ));
  }

  final measuresByRecipe = await loadRecipeMeasures(db);
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
        // This recipe's own words, which a parent's line resolves through.
        measures: measuresByRecipe[r['id']] ?? const <RecipeMeasure>[],
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
