/// Cookings in the local PowerSync SQLite: the one flat read the shelves and
/// the writes share ([loadCookingInputs]), and the write a tick and the
/// carry-over make ([ensureCookingFor]).
///
/// Local tables are views, so a write is a SELECT then an INSERT or UPDATE,
/// never an UPSERT. A birth checks for its id first: the other phone may have
/// born the same cooking, under the same id, and synced it here already.
library;

import 'dart:convert';

import 'package:sqlite3/common.dart' show Row;
import 'package:sqlite_async/sqlite_async.dart';
import 'package:uuid/uuid.dart';

import '../../../core/week_shape.dart';
import '../../planning/data/planning_repository_impl.dart' show loadMembers;
import '../../planning/domain/planning.dart'
    show Member, PlanEntry, eatersDemand, memberServings;
import '../domain/cooking.dart';
import '../domain/leftovers.dart';

const _uuid = Uuid();

/// A meal's demand: its portions override, else its eaters' factors.
double demandOfRow(Row r, Map<String, Member> members) =>
    (r['portions'] as int?)?.toDouble() ?? eatersDemand(_eatersOf(r), members);

List<String> _eatersOf(Row r) =>
    (jsonDecode(r['eaters'] as String? ?? '[]') as List).cast<String>();

/// A meal row as much of a [PlanEntry] as a share needs.
PlanEntry _entryOf(Row r) => PlanEntry(
  id: r['id'] as String,
  dayOfWeek: r['day_of_week'] as int,
  mealSlot: '',
  eaterIds: _eatersOf(r),
  portions: r['portions'] as int?,
);

/// What the members who ticked a meal ate of it: each eater their share, and
/// one taken off the meal since they ticked their usual portion. Duplicate
/// ticks of one member count once.
double eatenOf(Row r, Set<String> tickedBy, Map<String, Member> members) {
  if (tickedBy.isEmpty) return 0;
  final entry = _entryOf(r);
  var eaten = 0.0;
  for (final m in tickedBy) {
    eaten += entry.eaterIds.contains(m)
        ? memberServings(entry, m, members)
        : members[m]?.portionFactor ?? 1;
  }
  return eaten;
}

/// The portions of a meal's eaters who have not ticked it yet: its demand
/// less the shares of the eaters who did ([CookingMeal.unticked]). A member
/// taken off the meal who ticked frees nobody's portion.
double untickedOf(Row r, Set<String> tickedBy, Map<String, Member> members) {
  final demand = demandOfRow(r, members);
  if (tickedBy.isEmpty) return demand;
  final entry = _entryOf(r);
  var left = demand;
  for (final m in tickedBy) {
    left -= memberServings(entry, m, members);
  }
  return left > 1e-9 ? left : 0;
}

/// Who ticked each of the meals the query [fromWhere] selects (`pe` its
/// `plan_entry`), live ticks only, by `plan_entry` id.
Future<Map<String, Set<String>>> loadTicks(
  SqliteReadContext db,
  String fromWhere, [
  List<Object?> parameters = const [],
]) async {
  final ticks = <String, Set<String>>{};
  for (final t in await db.getAll(
    'SELECT me.plan_entry_id, me.member_id FROM meal_eaten me '
    'JOIN plan_entry pe ON pe.id = me.plan_entry_id '
    'WHERE me.deleted_at IS NULL AND $fromWhere',
    parameters,
  )) {
    (ticks[t['plan_entry_id'] as String] ??= {}).add(t['member_id'] as String);
  }
  return ticks;
}

/// The SQL date of a meal: its week's first day plus its offset.
const _mealDate = "date(wp.week_start_date, '+' || pe.day_of_week || ' days')";

/// Every live cooking with its linked meals, their ticks, its changes and
/// its recipe's shelf life: what [readCookings] reads. One flat read, no walk
/// over weeks.
///
/// - A linked meal removed after somebody ticked it is read too
///   ([CookingMeal.removed]): what was eaten was eaten.
/// - A cooking not cooked yet also holds the unlinked meals of its week that
///   join it ([loadJoiners]), unless [joiners] is false.
/// - A cooking whose cook chose the whole batch rounds what it made up to
///   whole batches ([Cooking.wholeBatchOf]).
///
/// [ids] narrows it to those cookings. With [today], a cooking said gone off
/// is read only while a meal from it is still to come, which it warns, or
/// while a freezer part of it could still be in date (a dish that freezes,
/// or food said by hand into the freezer).
Future<List<CookingInput>> loadCookingInputs(
  SqliteReadContext db, {
  Set<String>? ids,
  DateTime? today,
  bool joiners = true,
}) async {
  final idList = ids?.toList() ?? const <String>[];
  if (ids != null && ids.isEmpty) return const [];
  final marks = List.filled(idList.length, '?').join(', ');
  final onlyThese = ids == null ? '' : 'AND c.id IN ($marks) ';
  // Gone off: read only for the meals still to come from it, which it
  // warns, or for a freezer part that may outlive the fridge part.
  final stillWarns = today == null
      ? ''
      : "AND (c.gone_at IS NULL OR c.place = 'freezer' "
            'OR EXISTS (SELECT 1 FROM recipe fr WHERE fr.id = c.recipe_id '
            'AND fr.freezable = 1) '
            'OR EXISTS (SELECT 1 FROM plan_entry pe '
            'JOIN week_plan wp ON wp.id = pe.week_plan_id '
            'WHERE pe.cooking = c.id AND pe.deleted_at IS NULL '
            'AND $_mealDate >= ?)) ';
  final cookingRows = await db.getAll(
    'SELECT c.id, c.recipe_id, c.label, c.made, c.place, c.since, c.gone_at '
    'FROM cooking c WHERE c.deleted_at IS NULL $onlyThese$stillWarns'
    'ORDER BY c.id',
    [...idList, if (today != null) isoDateOf(today)],
  );
  if (cookingRows.isEmpty) return const [];

  final linked = ids == null
      ? 'pe.cooking IS NOT NULL'
      : 'pe.cooking IN ($marks)';
  // A meal removed after somebody ticked it still counts what was eaten.
  final mealRows = await db.getAll(
    'SELECT pe.id, pe.cooking, pe.eaters, pe.portions, pe.day_of_week, '
    'pe.deleted_at, wp.week_start_date FROM plan_entry pe '
    'JOIN week_plan wp ON wp.id = pe.week_plan_id AND wp.deleted_at IS NULL '
    'WHERE pe.instead_of IS NULL AND $linked AND (pe.deleted_at IS NULL '
    'OR EXISTS (SELECT 1 FROM meal_eaten t WHERE t.plan_entry_id = pe.id '
    'AND t.deleted_at IS NULL))',
    idList,
  );
  final ticks = await loadTicks(db, linked, idList);
  final members = {for (final m in await loadMembers(db)) m.id: m};
  final meals = <String, List<CookingMeal>>{};
  for (final r in mealRows) {
    final weekStart = DateTime.parse(r['week_start_date'] as String);
    (meals[r['cooking'] as String] ??= []).add(
      CookingMeal(
        entryId: r['id'] as String,
        weekStart: weekStart,
        day: dateOfDay(weekStart, r['day_of_week'] as int),
        portions: demandOfRow(r, members),
        eaten: eatenOf(r, ticks[r['id']] ?? const {}, members),
        unticked: untickedOf(r, ticks[r['id']] ?? const {}, members),
        removed: r['deleted_at'] != null,
      ),
    );
  }

  final changes = {
    for (final r in await db.getAll(
      'SELECT cooking_id, SUM(fridge) AS fridge, SUM(freezer) AS freezer '
      'FROM cooking_change WHERE deleted_at IS NULL '
      '${ids == null ? '' : 'AND cooking_id IN ($marks) '}'
      'GROUP BY cooking_id',
      idList,
    ))
      r['cooking_id'] as String: (
        fridge: (r['fridge'] as num? ?? 0).toDouble(),
        freezer: (r['freezer'] as num? ?? 0).toDouble(),
      ),
  };
  final recipeRows = await db.getAll(
    'SELECT id, title, keeps_for_days, freezable, freezer_days, '
    'servings_base FROM recipe WHERE deleted_at IS NULL AND id IN '
    '(SELECT recipe_id FROM cooking WHERE deleted_at IS NULL)',
  );
  final lives = {
    for (final r in recipeRows)
      r['id'] as String: (
        title: r['title'] as String,
        keepsForDays: r['keeps_for_days'] as int?,
        freezable: (r['freezable'] as int? ?? 0) == 1,
        freezerDays: r['freezer_days'] as int?,
      ),
  };
  final servings = {
    for (final r in recipeRows)
      r['id'] as String: (r['servings_base'] as num?)?.toDouble(),
  };
  final whole = await loadWholeBatches(db, [
    for (final r in cookingRows) r['id'] as String,
  ]);
  final inputs = [
    for (final r in cookingRows)
      (
        cooking: cookingOf(
          r,
          wholeBatchOf: whole.contains(r['id'])
              ? servings[r['recipe_id']]
              : null,
        ),
        life: lives[r['recipe_id']],
        meals: meals[r['id']] ?? const <CookingMeal>[],
        changes: changes[r['id']] ?? (fridge: 0.0, freezer: 0.0),
      ),
  ];
  if (!joiners) return inputs;

  final joined = await loadJoiners(db, [
    for (final input in inputs) ?joinCandidateOf(input),
  ]);
  if (joined.isEmpty) return inputs;
  return [
    for (final input in inputs)
      (
        cooking: input.cooking,
        life: input.life,
        meals: [
          ...input.meals,
          for (final r in joined[input.cooking.id] ?? const <Row>[])
            CookingMeal(
              entryId: r['id'] as String,
              weekStart: DateTime.parse(r['week_start_date'] as String),
              day: dateOfDay(
                DateTime.parse(r['week_start_date'] as String),
                r['day_of_week'] as int,
              ),
              portions: demandOfRow(r, members),
            ),
        ],
        changes: input.changes,
      ),
  ];
}

/// The id of the change row that says the cook chose the whole batch for
/// [cookingId]: it moves no portions, and every phone computes the same id,
/// so choosing it twice is one row and switching back soft-deletes it.
String wholeBatchChangeId(String cookingId) =>
    _uuid.v5(Namespace.url.value, 'ansi:cooking:$cookingId:whole-batch');

/// Which of the cookings [ids] the cook chose to make as a whole batch.
Future<Set<String>> loadWholeBatches(
  SqliteReadContext db,
  List<String> ids,
) async {
  final found = <String>{};
  // Kept well under SQLite's bound-parameter limit.
  for (var i = 0; i < ids.length; i += 500) {
    final chunk = ids.sublist(i, i + 500 > ids.length ? ids.length : i + 500);
    final byFlag = {for (final id in chunk) wholeBatchChangeId(id): id};
    final marks = List.filled(byFlag.length, '?').join(', ');
    for (final r in await db.getAll(
      'SELECT id FROM cooking_change WHERE deleted_at IS NULL '
      'AND id IN ($marks)',
      byFlag.keys.toList(),
    )) {
      found.add(byFlag[r['id']]!);
    }
  }
  return found;
}

/// A cooking that unlinked meals can join: its id, recipe, the week it is
/// bought in and its meals' days there.
typedef JoinCandidate = ({
  String id,
  String recipeId,
  DateTime weekStart,
  List<int> days,
});

/// [input] as a cooking meals can still join, or null: one cooked (a live
/// tick on any meal, a removed one's too), said by hand, said gone off, of
/// no recipe, or with no planned meal.
JoinCandidate? joinCandidateOf(CookingInput input) {
  final cooking = input.cooking;
  if (cooking.saidByHand || cooking.goneAt != null) return null;
  if (input.meals.any((m) => m.ticked)) return null;
  final String recipeId;
  if (cooking.recipeId case final id?) {
    recipeId = id;
  } else {
    return null;
  }
  final week = boughtIn(cooking, input.meals);
  if (week == null) return null;
  return (
    id: cooking.id,
    recipeId: recipeId,
    weekStart: week,
    days: [
      for (final m in input.meals)
        if (!m.removed && _dateOnly(m.weekStart) == week)
          _daysFrom(week, m.day),
    ],
  );
}

/// The unlinked meals that join each of [candidates], by cooking id: each
/// week's unlinked recipe meals grouped with the cookings bought there
/// ([joinersOf]). One read of the weeks named, each row with its id, eaters,
/// portions, day, slot and week.
Future<Map<String, List<Row>>> loadJoiners(
  SqliteReadContext db,
  List<JoinCandidate> candidates,
) async {
  if (candidates.isEmpty) return const {};
  final recipes = {for (final c in candidates) c.recipeId}.toList();
  final weeks = {for (final c in candidates) isoDateOf(c.weekStart)}.toList();
  String marks(List<Object> of) => List.filled(of.length, '?').join(', ');
  final rows = await db.getAll(
    'SELECT pe.id, pe.recipe_id, pe.eaters, pe.portions, pe.day_of_week, '
    'pe.meal_slot, wp.week_start_date FROM plan_entry pe '
    'JOIN week_plan wp ON wp.id = pe.week_plan_id AND wp.deleted_at IS NULL '
    'WHERE pe.deleted_at IS NULL AND pe.instead_of IS NULL '
    'AND pe.cooking IS NULL AND pe.recipe_id IN (${marks(recipes)}) '
    'AND wp.week_start_date IN (${marks(weeks)}) '
    'ORDER BY wp.week_start_date, pe.day_of_week, pe.sort_order, '
    'pe.created_at, pe.id',
    [...recipes, ...weeks],
  );
  if (rows.isEmpty) return const {};
  final lives = {
    for (final r in await db.getAll(
      'SELECT id, keeps_for_days, freezable, freezer_days FROM recipe '
      'WHERE id IN (${marks(recipes)})',
      recipes,
    ))
      r['id'] as String: r,
  };
  String key(String recipeId, DateTime week) => '$recipeId ${isoDateOf(week)}';
  final unlinked = <String, List<Row>>{};
  for (final r in rows) {
    final week = DateTime.parse(r['week_start_date'] as String);
    (unlinked[key(r['recipe_id'] as String, week)] ??= []).add(r);
  }
  final pots = <String, List<JoinCandidate>>{};
  for (final c in candidates) {
    (pots[key(c.recipeId, c.weekStart)] ??= []).add(c);
  }
  final joined = <String, List<Row>>{};
  for (final MapEntry(key: k, value: group) in pots.entries) {
    final meals = unlinked[k];
    if (meals == null) continue;
    final life = lives[group.first.recipeId];
    final joins = joinersOf(
      unlinked: [
        for (final r in meals)
          (entryId: r['id'] as String, dayOfWeek: r['day_of_week'] as int),
      ],
      uncooked: [for (final c in group) (id: c.id, days: c.days)],
      keepsForDays: life?['keeps_for_days'] as int?,
      freezable: (life?['freezable'] as int? ?? 0) == 1,
      freezerDays: life?['freezer_days'] as int?,
    );
    for (final r in meals) {
      if (joins[r['id']] case final cookingId?) {
        (joined[cookingId] ??= []).add(r);
      }
    }
  }
  return joined;
}

/// Links the unlinked meals that join the cooking [id] while it is not
/// cooked yet ([loadJoiners]): its next write makes the join stick. A
/// cooking whose made is already fixed (unticked into nothing since) makes
/// the joiners' portions too.
Future<void> linkJoiners(SqliteWriteContext tx, String id) async {
  final inputs = await loadCookingInputs(tx, ids: {id}, joiners: false);
  if (inputs.isEmpty) return;
  final candidate = joinCandidateOf(inputs.single);
  if (candidate == null) return;
  final rows = (await loadJoiners(tx, [candidate]))[id];
  if (rows == null || rows.isEmpty) return;
  final now = _now();
  final marks = List.filled(rows.length, '?').join(', ');
  await tx.execute(
    'UPDATE plan_entry SET cooking = ?, updated_at = ? '
    'WHERE id IN ($marks) AND cooking IS NULL',
    [id, now, for (final r in rows) r['id']],
  );
  final made = inputs.single.cooking.made;
  if (made == null) return;
  final members = {for (final m in await loadMembers(tx)) m.id: m};
  final more = rows.fold<double>(0, (s, r) => s + demandOfRow(r, members));
  await tx.execute('UPDATE cooking SET made = ?, updated_at = ? WHERE id = ?', [
    made + more,
    now,
    id,
  ]);
}

/// The cooking not cooked yet that the unlinked recipe meal [entryId] joins
/// ([joinersOf]), linked with every other meal joining it; null when it
/// joins none. Read before a tick lands, while the pot is still uncooked.
Future<String?> joinUncookedCooking(
  SqliteWriteContext tx,
  String entryId,
) async {
  final meal = await tx.getOptional(
    'SELECT pe.recipe_id, pe.cooking, wp.week_start_date FROM plan_entry pe '
    'JOIN week_plan wp ON wp.id = pe.week_plan_id '
    'WHERE pe.id = ? AND pe.deleted_at IS NULL AND pe.instead_of IS NULL',
    [entryId],
  );
  if (meal == null || meal['recipe_id'] is! String) return null;
  if (meal['cooking'] case final String linked) {
    await linkJoiners(tx, linked);
    return linked;
  }
  // The cookings of the recipe with a meal in this meal's week.
  final ids = {
    for (final r in await tx.getAll(
      'SELECT DISTINCT pe.cooking FROM plan_entry pe '
      'JOIN week_plan wp ON wp.id = pe.week_plan_id AND wp.deleted_at IS NULL '
      'WHERE wp.week_start_date = ? AND pe.recipe_id = ? '
      'AND pe.cooking IS NOT NULL AND pe.deleted_at IS NULL',
      [meal['week_start_date'], meal['recipe_id']],
    ))
      r['cooking'] as String,
  };
  if (ids.isEmpty) return null;
  final candidates = [
    for (final input in await loadCookingInputs(tx, ids: ids, joiners: false))
      ?joinCandidateOf(input),
  ];
  final joins = await loadJoiners(tx, candidates);
  for (final MapEntry(key: id, value: rows) in joins.entries) {
    if (rows.any((r) => r['id'] == entryId)) {
      await linkJoiners(tx, id);
      return id;
    }
  }
  return null;
}

/// Every planned recipe meal from [today] on that no cooking holds yet, in
/// day order, with its recipe's shelf life: what the pots not born yet are
/// read from ([plannedPots]). One flat read by date, no walk over weeks.
Future<List<UnbornMeal>> loadUnbornMeals(
  SqliteReadContext db,
  DateTime today,
) async {
  final rows = await db.getAll(
    'SELECT pe.id, pe.recipe_id, pe.day_of_week, wp.week_start_date, '
    'r.title, r.keeps_for_days, r.freezable, r.freezer_days '
    'FROM plan_entry pe '
    'JOIN week_plan wp ON wp.id = pe.week_plan_id AND wp.deleted_at IS NULL '
    'JOIN recipe r ON r.id = pe.recipe_id AND r.deleted_at IS NULL '
    'WHERE pe.deleted_at IS NULL AND pe.instead_of IS NULL '
    'AND pe.cooking IS NULL AND pe.recipe_id IS NOT NULL '
    'AND $_mealDate >= ? '
    'ORDER BY wp.week_start_date, pe.day_of_week, pe.sort_order, '
    'pe.created_at, pe.id',
    [isoDateOf(today)],
  );
  return [
    for (final r in rows)
      (
        entryId: r['id'] as String,
        recipeId: r['recipe_id'] as String,
        weekStart: DateTime.parse(r['week_start_date'] as String),
        dayOfWeek: r['day_of_week'] as int,
        life: (
          title: r['title'] as String,
          keepsForDays: r['keeps_for_days'] as int?,
          freezable: (r['freezable'] as int? ?? 0) == 1,
          freezerDays: r['freezer_days'] as int?,
        ),
      ),
  ];
}

/// A `cooking` row as a [Cooking]; [wholeBatchOf] when its cook chose the
/// whole batch.
Cooking cookingOf(Row r, {double? wholeBatchOf}) => Cooking(
  id: r['id'] as String,
  recipeId: r['recipe_id'] as String?,
  label: r['label'] as String?,
  made: (r['made'] as num?)?.toDouble(),
  place: switch (r['place']) {
    'freezer' => LeftoverPlace.freezer,
    'fridge' => LeftoverPlace.fridge,
    _ => null,
  },
  since: switch (r['since']) {
    final String since => DateTime.parse(since),
    _ => null,
  },
  goneAt: switch (r['gone_at']) {
    final String at => DateTime.parse(at),
    _ => null,
  },
  wholeBatchOf: wholeBatchOf,
);

/// What the cooking [id] holds on [today], read inside [tx] with every other
/// cooking of its dish ([readDishes]): a share it gives another cooking's
/// meal is out of its box, as the page drew it.
Future<CookingRead?> readCookingIn(
  SqliteReadContext tx,
  String id,
  DateTime today,
) async {
  final dish = {
    id,
    for (final r in await tx.getAll(
      'SELECT o.id FROM cooking c JOIN cooking o '
      'ON o.recipe_id = c.recipe_id AND o.deleted_at IS NULL '
      'WHERE c.id = ?',
      [id],
    ))
      r['id'] as String,
  };
  final inputs = await loadCookingInputs(tx, ids: dish);
  return readDishes(inputs, today)[id];
}

/// Writes one change row to the cooking [cookingId]: [fridge] and [freezer]
/// portions added (negative: taken). Returns its id. With [id], a row of that
/// id already there is left as it is: a carried-over answer, written once.
Future<String> insertCookingChange(
  SqliteWriteContext tx, {
  required String householdId,
  required String cookingId,
  double fridge = 0,
  double freezer = 0,
  String? id,
}) async {
  final changeId = id ?? _uuid.v4();
  if (id != null &&
      await tx.getOptional('SELECT id FROM cooking_change WHERE id = ?', [
            id,
          ]) !=
          null) {
    return changeId;
  }
  final now = _now();
  await tx.execute(
    'INSERT INTO cooking_change (id, household_id, cooking_id, fridge, '
    'freezer, created_at, updated_at) VALUES (?, ?, ?, ?, ?, ?, ?)',
    [changeId, householdId, cookingId, fridge, freezer, now, now],
  );
  return changeId;
}

/// Makes sure the recipe meal [entryId] is in a cooking, and fixes what that
/// cooking made once it has a tick: the write behind a tick. Returns the
/// cooking's id, or null for a meal that is no recipe meal.
///
/// A meal already linked keeps its cooking (born here if the row has not
/// synced yet). Otherwise its group ([cookingGroupOf]: its week's unlinked
/// meals of the recipe, by shelf life) is born into one cooking
/// ([birthIdFor]) and linked whole. A group the old fridge rows name
/// (`leftover.batch`) joins the cooking that row became, and a change row
/// keeps the count that row said ([_carryNamedRow]).
///
/// **Made** is fixed from the live sum of the cooking's meals the first time
/// one of them has a live tick, and never again.
Future<String?> ensureCookingFor(
  SqliteWriteContext tx,
  String entryId, {
  required String householdId,
  required DateTime today,
}) async {
  final meal = await tx.getOptional(
    'SELECT id, recipe_id, week_plan_id, cooking FROM plan_entry '
    'WHERE id = ? AND deleted_at IS NULL AND instead_of IS NULL',
    [entryId],
  );
  // Only a recipe meal is cooked: an ingredient's or one eaten out is not.
  final recipeId = meal?['recipe_id'];
  if (meal == null || recipeId is! String) return null;
  final now = _now();

  // An unlinked meal grouped with a cooking not cooked yet joins it.
  var id = meal['cooking'] as String? ?? await joinUncookedCooking(tx, entryId);
  if (id == null) {
    final life = await tx.getOptional(
      'SELECT keeps_for_days, freezable, freezer_days FROM recipe WHERE id = ?',
      [recipeId],
    );
    final unlinked = await tx.getAll(
      'SELECT id, day_of_week FROM plan_entry '
      'WHERE week_plan_id = ? AND recipe_id = ? AND deleted_at IS NULL '
      'AND instead_of IS NULL AND cooking IS NULL '
      'ORDER BY day_of_week, sort_order, created_at, id',
      [meal['week_plan_id'], recipeId],
    );
    final group = cookingGroupOf(
      entryId,
      unlinked: [
        for (final r in unlinked)
          (entryId: r['id'] as String, dayOfWeek: r['day_of_week'] as int),
      ],
      keepsForDays: life?['keeps_for_days'] as int?,
      freezable: (life?['freezable'] as int? ?? 0) == 1,
      freezerDays: life?['freezer_days'] as int?,
    );
    final marks = List.filled(group.length, '?').join(', ');
    final named = await tx.getOptional(
      'SELECT lo.id FROM leftover lo JOIN cooking c ON c.id = lo.id '
      'WHERE lo.batch IN ($marks) AND lo.deleted_at IS NULL '
      'AND c.deleted_at IS NULL '
      'ORDER BY lo.updated_at DESC, lo.id DESC LIMIT 1',
      group,
    );
    if (named != null) {
      id = named['id'] as String;
      await _carryNamedRow(
        tx,
        id,
        group,
        householdId: householdId,
        today: today,
      );
    } else {
      final known = {
        for (final r in await tx.getAll(
          'SELECT id FROM cooking WHERE id IN ($marks)',
          group,
        ))
          r['id'] as String,
      };
      id = birthIdFor(group, cookingIds: known);
      await _linkGroup(tx, id, group, recipeId, householdId, now);
    }
  } else {
    await _bornIfMissing(tx, id, recipeId, householdId, now);
  }

  // Made is fixed at the first tick, from what its meals planned then.
  final cooking = await tx.get('SELECT made, since FROM cooking WHERE id = ?', [
    id,
  ]);
  if (cooking['made'] == null && cooking['since'] == null) {
    final ticked = await tx.getOptional(
      'SELECT 1 FROM meal_eaten me '
      'JOIN plan_entry pe ON pe.id = me.plan_entry_id '
      'WHERE pe.cooking = ? AND pe.deleted_at IS NULL '
      'AND me.deleted_at IS NULL LIMIT 1',
      [id],
    );
    if (ticked != null) {
      final members = {for (final m in await loadMembers(tx)) m.id: m};
      final rows = await tx.getAll(
        'SELECT eaters, portions FROM plan_entry '
        'WHERE cooking = ? AND deleted_at IS NULL AND instead_of IS NULL',
        [id],
      );
      final made = rows.fold<double>(0, (s, r) => s + demandOfRow(r, members));
      await tx.execute(
        'UPDATE cooking SET made = ?, updated_at = ? WHERE id = ?',
        [made, now, id],
      );
    }
  }
  return id;
}

/// The cooking a meal picked from [pot] joins: [pot] itself when a cooking
/// of that id is here; else, when [pot] names a planned meal (a pot not born
/// yet, named by one of its meals), that meal's group born into one now
/// ([ensureCookingFor]). A cooking not cooked yet makes the picked meal's
/// portions too, since what it made is still the live sum.
Future<String> cookingForPick(
  SqliteWriteContext tx,
  String pot, {
  required String householdId,
  required DateTime today,
}) async {
  if (await tx.getOptional('SELECT id FROM cooking WHERE id = ?', [pot]) !=
      null) {
    // A write to a cooking not cooked yet makes its joiners' join stick.
    await linkJoiners(tx, pot);
    return pot;
  }
  return await ensureCookingFor(
        tx,
        pot,
        householdId: householdId,
        today: today,
      ) ??
      pot;
}

/// Inserts the cooking [id] unless a row of that id is here already.
Future<void> _bornIfMissing(
  SqliteWriteContext tx,
  String id,
  String recipeId,
  String householdId,
  String now,
) async {
  if (await tx.getOptional('SELECT id FROM cooking WHERE id = ?', [id]) !=
      null) {
    return;
  }
  await tx.execute(
    'INSERT INTO cooking (id, household_id, recipe_id, created_at, '
    'updated_at) VALUES (?, ?, ?, ?, ?)',
    [id, householdId, recipeId, now, now],
  );
}

/// Births [id] if need be and links every meal of [group] not yet linked.
Future<void> _linkGroup(
  SqliteWriteContext tx,
  String id,
  List<String> group,
  String recipeId,
  String householdId,
  String now,
) async {
  await _bornIfMissing(tx, id, recipeId, householdId, now);
  final marks = List.filled(group.length, '?').join(', ');
  await tx.execute(
    'UPDATE plan_entry SET cooking = ?, updated_at = ? '
    'WHERE id IN ($marks) AND cooking IS NULL',
    [id, now, ...group],
  );
}

/// Links [group] to the cooking an old fridge row became ([id], dated by its
/// `since`), with one change row so its count reads what the row said: what
/// the newly linked meals take is put back once. The change's id follows
/// from the cooking's, so two phones carrying the same row write one.
Future<void> _carryNamedRow(
  SqliteWriteContext tx,
  String id,
  List<String> group, {
  required String householdId,
  required DateTime today,
}) async {
  final before = await readCookingIn(tx, id, today);
  final recipe = await tx.get('SELECT recipe_id FROM cooking WHERE id = ?', [
    id,
  ]);
  await _linkGroup(
    tx,
    id,
    group,
    recipe['recipe_id'] as String,
    householdId,
    _now(),
  );
  final after = await readCookingIn(tx, id, today);
  if (before == null || after == null) return;
  final fridge = before.fridge - after.fridge;
  final freezer = before.freezer - after.freezer;
  if (fridge.abs() < 1e-9 && freezer.abs() < 1e-9) return;
  await insertCookingChange(
    tx,
    householdId: householdId,
    cookingId: id,
    fridge: fridge,
    freezer: freezer,
    id: _uuid.v5(Namespace.url.value, 'ansi:cooking:$id:carried-row'),
  );
}

/// The carry-over from the fridge rows and answers of the last release, run
/// once per launch of this release: idempotent, with ids every phone
/// computes alike.
///
/// - Every group with a meal ticked within the last 28 days and not yet in a
///   cooking is born into one ([ensureCookingFor]): what today's page showed
///   stays on it.
/// - Every group a converted cooking names (by a meal's id, or an old row's
///   `batch`) is linked to it, ticked or not.
/// - An old answer that a batch was binned or eaten (`batch_leftover`) is a
///   change row that takes its cooking to nothing, once.
Future<void> carryOverCookings(
  SqliteConnection db, {
  required String householdId,
  required DateTime today,
}) => db.writeTransaction((tx) async {
  final day = DateTime(today.year, today.month, today.day);
  final from = DateTime(day.year, day.month, day.day - 28);
  final ticked = await tx.getAll(
    'SELECT DISTINCT pe.id, wp.week_start_date, pe.day_of_week, '
    'pe.sort_order, pe.created_at FROM meal_eaten me '
    'JOIN plan_entry pe ON pe.id = me.plan_entry_id '
    'JOIN week_plan wp ON wp.id = pe.week_plan_id AND wp.deleted_at IS NULL '
    'WHERE me.deleted_at IS NULL AND pe.deleted_at IS NULL '
    'AND pe.cooking IS NULL AND pe.recipe_id IS NOT NULL '
    'AND pe.instead_of IS NULL AND $_mealDate BETWEEN ? AND ? '
    'ORDER BY wp.week_start_date, pe.day_of_week, pe.sort_order, '
    'pe.created_at, pe.id',
    [isoDateOf(from), isoDateOf(day)],
  );
  final named = await tx.getAll(
    'SELECT pe.id FROM plan_entry pe '
    'WHERE pe.cooking IS NULL AND pe.deleted_at IS NULL '
    'AND pe.recipe_id IS NOT NULL AND pe.instead_of IS NULL '
    'AND (pe.id IN (SELECT id FROM cooking WHERE deleted_at IS NULL) '
    'OR pe.id IN (SELECT batch FROM leftover WHERE deleted_at IS NULL))',
  );
  for (final r in [...ticked, ...named]) {
    await ensureCookingFor(
      tx,
      r['id'] as String,
      householdId: householdId,
      today: day,
    );
  }

  // The newest answer per batch, as the last release read them.
  final answers = <String, Row>{
    for (final r in await tx.getAll(
      'SELECT plan_entry_id, binned, eaten FROM batch_leftover '
      'WHERE deleted_at IS NULL ORDER BY updated_at, id',
    ))
      r['plan_entry_id'] as String: r,
  };
  for (final MapEntry(key: entryId, value: answer) in answers.entries) {
    final gone =
        (answer['binned'] as num? ?? 0) + (answer['eaten'] as num? ?? 0);
    if (gone <= 1e-9) continue;
    final linked = await tx.getOptional(
      'SELECT cooking FROM plan_entry WHERE id = ? AND cooking IS NOT NULL',
      [entryId],
    );
    final cookingId = linked?['cooking'] as String?;
    if (cookingId == null) continue;
    final changeId = _uuid.v5(
      Namespace.url.value,
      'ansi:cooking:$cookingId:answered:$entryId',
    );
    if (await tx.getOptional('SELECT id FROM cooking_change WHERE id = ?', [
          changeId,
        ]) !=
        null) {
      continue;
    }
    final read = await readCookingIn(tx, cookingId, day);
    if (read == null) continue;
    await insertCookingChange(
      tx,
      householdId: householdId,
      cookingId: cookingId,
      fridge: read.fridge > 0 ? -read.fridge : 0,
      freezer: read.freezer > 0 ? -read.freezer : 0,
      id: changeId,
    );
  }
});

String _now() => DateTime.now().toUtc().toIso8601String();

DateTime _dateOnly(DateTime d) => DateTime(d.year, d.month, d.day);

/// Whole days from [from] to [to], by the calendar.
int _daysFrom(DateTime from, DateTime to) => DateTime.utc(
  to.year,
  to.month,
  to.day,
).difference(DateTime.utc(from.year, from.month, from.day)).inDays;
