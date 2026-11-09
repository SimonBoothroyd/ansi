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

/// What the members who ticked a meal ate of it: each eater their share, and
/// one taken off the meal since they ticked their usual portion. Duplicate
/// ticks of one member count once.
double eatenOf(Row r, Set<String> tickedBy, Map<String, Member> members) {
  if (tickedBy.isEmpty) return 0;
  final entry = PlanEntry(
    id: r['id'] as String,
    dayOfWeek: r['day_of_week'] as int,
    mealSlot: '',
    eaterIds: _eatersOf(r),
    portions: r['portions'] as int?,
  );
  var eaten = 0.0;
  for (final m in tickedBy) {
    eaten += entry.eaterIds.contains(m)
        ? memberServings(entry, m, members)
        : members[m]?.portionFactor ?? 1;
  }
  return eaten;
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

/// Every live cooking with its live linked meals, their ticks, its changes
/// and its recipe's shelf life: what [readCookings] reads. One flat read, no
/// walk over weeks.
///
/// [ids] narrows it to those cookings. With [today], a cooking said gone is
/// read only while a meal from it is still to come, which it warns.
Future<List<CookingInput>> loadCookingInputs(
  SqliteReadContext db, {
  Set<String>? ids,
  DateTime? today,
}) async {
  final idList = ids?.toList() ?? const <String>[];
  if (ids != null && ids.isEmpty) return const [];
  final marks = List.filled(idList.length, '?').join(', ');
  final onlyThese = ids == null ? '' : 'AND c.id IN ($marks) ';
  // Gone: read only for the meals still to come from it, which it warns.
  final stillWarns = today == null
      ? ''
      : 'AND (c.gone_at IS NULL OR EXISTS (SELECT 1 FROM plan_entry pe '
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
  final mealRows = await db.getAll(
    'SELECT pe.id, pe.cooking, pe.eaters, pe.portions, pe.day_of_week, '
    'wp.week_start_date FROM plan_entry pe '
    'JOIN week_plan wp ON wp.id = pe.week_plan_id AND wp.deleted_at IS NULL '
    'WHERE pe.deleted_at IS NULL AND pe.instead_of IS NULL AND $linked',
    idList,
  );
  final ticks = await loadTicks(
    db,
    'pe.deleted_at IS NULL AND $linked',
    idList,
  );
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
  final lives = {
    for (final r in await db.getAll(
      'SELECT id, title, keeps_for_days, freezable, freezer_days FROM recipe '
      'WHERE deleted_at IS NULL AND id IN '
      '(SELECT recipe_id FROM cooking WHERE deleted_at IS NULL)',
    ))
      r['id'] as String: (
        title: r['title'] as String,
        keepsForDays: r['keeps_for_days'] as int?,
        freezable: (r['freezable'] as int? ?? 0) == 1,
        freezerDays: r['freezer_days'] as int?,
      ),
  };
  return [
    for (final r in cookingRows)
      (
        cooking: cookingOf(r),
        life: lives[r['recipe_id']],
        meals: meals[r['id']] ?? const <CookingMeal>[],
        changes: changes[r['id']] ?? (fridge: 0.0, freezer: 0.0),
      ),
  ];
}

/// A `cooking` row as a [Cooking].
Cooking cookingOf(Row r) => Cooking(
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
);

/// What the cooking [id] holds on [today], read inside [tx].
Future<CookingRead?> readCookingIn(
  SqliteReadContext tx,
  String id,
  DateTime today,
) async {
  final inputs = await loadCookingInputs(tx, ids: {id});
  return inputs.isEmpty ? null : readCooking(inputs.single, today);
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

  var id = meal['cooking'] as String?;
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
