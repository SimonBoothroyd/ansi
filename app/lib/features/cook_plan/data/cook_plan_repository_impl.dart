/// [CookPlanRepository] over the local PowerSync SQLite. The plan is read,
/// never written: one week's meals, and the cookings they are in.
///
/// The watch query must select a column from every joined table: SQLite drops a
/// LEFT JOIN with no selected column, and that table then never re-fires the
/// watch.
library;

import 'package:sqlite3/common.dart' show Row;
import 'package:sqlite_async/sqlite_async.dart';

import '../../../core/units/recipe_measure.dart';
import '../../../core/units/units.dart';
import '../../../core/week_shape.dart';
import '../../planning/data/planning_repository_impl.dart' show loadMembers;
import '../../planning/data/week_variant_repository_impl.dart'
    show loadWeekOverrides;
import '../../planning/domain/planning.dart' show Member;
import '../../recipes/data/recipe_measure_repository_impl.dart'
    show loadRecipeMeasures;
import '../../recipes/domain/component_math.dart';
import '../domain/cook_plan.dart';
import '../domain/cook_plan_repository.dart';
import '../domain/cooking.dart';
import '../domain/leftovers.dart' show dateOfDay;
import 'cooking_store.dart';

class SqliteCookPlanRepository implements CookPlanRepository {
  const SqliteCookPlanRepository(this._db);

  final SqliteConnection _db;

  @override
  Stream<CookPlan> watchCookPlan(DateTime weekStart) {
    final key = isoDateOf(weekStart);
    // Every table whose change moves the plan is joined with a column selected:
    // week, entries, recipes, groups and line items (component lines and
    // yields), `household_member` (portion factors; cross-joined, it is not
    // tied to the week), the week's line overrides and the cookings its meals
    // are in. A watch re-runs on any write to a table it reads, so a tick or
    // a meal of a cooking in another week re-derives it too.
    return _db
        .watch(
          'SELECT wp.id, pe.id, r.keeps_for_days, g.id, li.id, hm.id, '
          'wro.id, rm.id, me.id, c.id '
          'FROM week_plan wp '
          'LEFT JOIN plan_entry pe '
          'ON pe.week_plan_id = wp.id AND pe.deleted_at IS NULL '
          // Who ate each meal moves when its cooking was cooked.
          'LEFT JOIN meal_eaten me ON me.plan_entry_id = pe.id '
          // What a cooking made is what it is bought for.
          'LEFT JOIN cooking c ON c.id = pe.cooking '
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
    eatenFromEarlier: planned.eatenFromEarlier,
  );
}

/// The week keyed [weekKey]'s recipe meals as they are cooked: the one read
/// the cook plan and the shop share, so both buy a meal in one week only.
///
/// - Its meals not yet in a cooking, by recipe ([PlannedRecipe.meals]), to
///   group by shelf life within the week.
/// - Each cooking bought this week (its earliest linked meal is here) with
///   every live meal linked to it, whatever week ([PlannedRecipe.cookings]),
///   bought for what it made.
/// - Its meals of a cooking bought in an earlier week, by entry id, with that
///   cooking's session (`eatenFromEarlier`): bought and costed there. A meal of
///   food said by hand buys nothing anywhere.
///
/// Days count from this week's first day. [leaveOut] names meals to read as
/// not planned.
Future<
  ({List<PlannedRecipe> recipes, Map<String, CookSession> eatenFromEarlier})
>
loadPlannedWeek(
  SqliteConnection db,
  String weekKey, {
  Set<String> leaveOut = const {},
}) async {
  final weekStart = DateTime.parse(weekKey);
  // One row per planned recipe meal with its recipe's shelf life. Ingredient
  // meals and meals out are not cooked; `recipe_id IS NOT NULL` states that
  // explicitly beside the inner join. What a member had instead of a meal
  // was never cooked.
  final rows = await db.getAll(
    'SELECT pe.id, pe.day_of_week, pe.meal_slot, pe.eaters, pe.portions, '
    'pe.cooking, r.id AS recipe_id, r.title, r.servings_base, '
    'r.keeps_for_days, r.freezable, r.freezer_days '
    'FROM week_plan wp '
    'JOIN plan_entry pe ON pe.week_plan_id = wp.id AND pe.deleted_at IS NULL '
    'JOIN recipe r ON r.id = pe.recipe_id AND r.deleted_at IS NULL '
    'WHERE wp.week_start_date = ? AND wp.deleted_at IS NULL '
    'AND pe.recipe_id IS NOT NULL AND pe.instead_of IS NULL '
    'ORDER BY pe.day_of_week, pe.sort_order, pe.created_at',
    [weekKey],
  );
  final ticks = await loadTicks(
    db,
    'pe.deleted_at IS NULL AND pe.week_plan_id IN '
    '(SELECT id FROM week_plan WHERE week_start_date = ? '
    'AND deleted_at IS NULL)',
    [weekKey],
  );
  // A meal's demand is the sum of its eaters' portion factors unless the
  // entry overrides it: the same `eatersDemand` the Week reads.
  final members = {for (final m in await loadMembers(db)) m.id: m};

  final recipes = <String, PlannedRecipe>{};
  final unlinked = <String, List<CoveredMeal>>{};
  final cookingIds = <String>{};
  for (final row in rows) {
    final recipeId = row['recipe_id'] as String;
    recipes[recipeId] ??= PlannedRecipe(
      recipeId: recipeId,
      title: row['title'] as String,
      servingsBase: (row['servings_base'] as num).toDouble(),
      keepsForDays: row['keeps_for_days'] as int?,
      freezable: (row['freezable'] as int? ?? 0) == 1,
      freezerDays: row['freezer_days'] as int?,
    );
    if (row['cooking'] case final String cooking) {
      cookingIds.add(cooking);
      continue;
    }
    if (leaveOut.contains(row['id'])) continue;
    (unlinked[recipeId] ??= []).add(
      _covered(row, row['day_of_week'] as int, ticks, members),
    );
  }

  // Every cooking a meal of the week is in, with all its meals.
  final cookings = <String, List<PlannedCooking>>{};
  final eatenFromEarlier = <String, CookSession>{};
  if (cookingIds.isNotEmpty) {
    final ids = cookingIds.toList();
    final marks = List.filled(ids.length, '?').join(', ');
    final stored = {
      for (final r in await db.getAll(
        'SELECT id, recipe_id, label, made, place, since, gone_at, deleted_at '
        'FROM cooking WHERE id IN ($marks)',
        ids,
      ))
        r['id'] as String: r,
    };
    final linked = await db.getAll(
      'SELECT pe.id, pe.cooking, pe.day_of_week, pe.meal_slot, pe.eaters, '
      'pe.portions, pe.recipe_id, wp.week_start_date FROM plan_entry pe '
      'JOIN week_plan wp ON wp.id = pe.week_plan_id AND wp.deleted_at IS NULL '
      'WHERE pe.deleted_at IS NULL AND pe.instead_of IS NULL '
      'AND pe.cooking IN ($marks) '
      'ORDER BY wp.week_start_date, pe.day_of_week, pe.sort_order, '
      'pe.created_at',
      ids,
    );
    final linkedTicks = await loadTicks(
      db,
      'pe.deleted_at IS NULL AND pe.cooking IN ($marks)',
      ids,
    );
    final byCooking = <String, List<Row>>{};
    for (final r in linked) {
      if (leaveOut.contains(r['id'])) continue;
      (byCooking[r['cooking'] as String] ??= []).add(r);
    }
    final whole = await loadWholeBatches(db, ids);
    // The cookings bought this week, before the meals that join them.
    final boughtHere = <({String recipeId, PlannedCooking cooking})>[];
    final candidates = <JoinCandidate>[];
    for (final MapEntry(key: id, value: meals) in byCooking.entries) {
      final row = stored[id];
      // Food said by hand was bought already, and a cooking taken away is
      // bought nowhere: their meals pass over the shop and the cost.
      if (row != null && (row['since'] != null || row['deleted_at'] != null)) {
        continue;
      }
      final recipeId =
          row?['recipe_id'] as String? ?? meals.first['recipe_id'] as String;
      final recipe = recipes[recipeId];
      if (recipe == null) continue;
      // Days from this week's first day: a later week's meal reads 7 or more,
      // an earlier week's below 0.
      final covers = [
        for (final r in meals)
          _covered(
            r,
            _daysBetween(
              weekStart,
              dateOfDay(
                DateTime.parse(r['week_start_date'] as String),
                r['day_of_week'] as int,
              ),
            ),
            linkedTicks,
            members,
          ),
      ];
      final cooking = PlannedCooking(
        id: id,
        made: (row?['made'] as num?)?.toDouble(),
        wholeBatch: whole.contains(id),
        meals: covers,
      );
      final buyWeek = boughtIn(Cooking(id: id, recipeId: recipeId), [
        for (final r in meals)
          CookingMeal(
            entryId: r['id'] as String,
            weekStart: DateTime.parse(r['week_start_date'] as String),
            day: dateOfDay(
              DateTime.parse(r['week_start_date'] as String),
              r['day_of_week'] as int,
            ),
            portions: 0,
          ),
      ]);
      if (buyWeek != null && _daysBetween(weekStart, buyWeek) == 0) {
        boughtHere.add((recipeId: recipeId, cooking: cooking));
        // Not cooked yet (nobody ticked a meal of it, nor said it gone): the
        // week's meals it groups with join it.
        final ticked = meals.any(
          (r) => (linkedTicks[r['id']] ?? const {}).isNotEmpty,
        );
        if (!ticked && row?['gone_at'] == null) {
          candidates.add((
            id: id,
            recipeId: recipeId,
            weekStart: weekStart,
            days: [
              for (final m in covers)
                if (m.dayOfWeek >= 0 && m.dayOfWeek <= 6) m.dayOfWeek,
            ],
          ));
        }
        continue;
      }
      // Bought in another week: this week's meals of it eat from there.
      final session = clusterSessions(
        recipe.copyWith(meals: const [], cookings: [cooking]),
      ).single;
      for (final m in covers) {
        if (m.dayOfWeek >= 0 && m.dayOfWeek < 7) {
          eatenFromEarlier[m.entryId!] = session;
        }
      }
    }

    final joined = await loadJoiners(db, candidates);
    for (final (:recipeId, :cooking) in boughtHere) {
      final joiners = [
        for (final r in joined[cooking.id] ?? const <Row>[])
          if (!leaveOut.contains(r['id'])) r,
      ];
      final ids = {for (final r in joiners) r['id']};
      unlinked[recipeId]?.removeWhere((m) => ids.contains(m.entryId));
      (cookings[recipeId] ??= []).add(
        joiners.isEmpty
            ? cooking
            : cooking.copyWith(
                meals: [
                  ...cooking.meals,
                  for (final r in joiners)
                    _covered(r, r['day_of_week'] as int, ticks, members),
                ],
              ),
      );
    }
  }

  return (
    recipes: [
      for (final MapEntry(key: id, value: recipe) in recipes.entries)
        if ((unlinked[id] ?? const []).isNotEmpty ||
            (cookings[id] ?? const []).isNotEmpty)
          recipe.copyWith(
            meals: unlinked[id] ?? const [],
            cookings: cookings[id] ?? const [],
          ),
    ],
    eatenFromEarlier: eatenFromEarlier,
  );
}

/// One planned meal row as a [CoveredMeal] on [day], with what its eaters
/// said they ate (never more than its portions).
CoveredMeal _covered(
  Row row,
  int day,
  Map<String, Set<String>> ticks,
  Map<String, Member> members,
) {
  final portions = demandOfRow(row, members);
  final eaten = eatenOf(row, ticks[row['id']] ?? const {}, members);
  return CoveredMeal(
    dayOfWeek: day,
    mealSlot: row['meal_slot'] as String,
    portions: portions,
    entryId: row['id'] as String,
    eatenPortions: eaten > portions ? portions : eaten,
  );
}

/// Whole days from [from] to [to], by the calendar.
int _daysBetween(DateTime from, DateTime to) => DateTime.utc(
  to.year,
  to.month,
  to.day,
).difference(DateTime.utc(from.year, from.month, from.day)).inDays;

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
