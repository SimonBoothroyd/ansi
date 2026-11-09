/// When a batch was cooked, what it has left and until when; and the
/// household's leftovers, fridge and freezer, as those batches and what was
/// said about them make them. Pure Dart.
///
/// **No tick means you didn't eat it.** A batch — one meal [CookSession] — is
/// **cooked** on the earliest calendar day anybody ticked a meal it covers,
/// whatever order the ticks came in. A batch nobody ticked is not cooked yet
/// while any of its meals is still to come, and its cook day reads as the
/// first of those; once every meal is behind us it was never cooked and
/// leaves nothing ([cookDayOf]).
///
/// What it **made** is what was planned and bought for. What is **left** is
/// the portions of its meals already behind us that nobody ate, a skipped
/// meal before the cook day included, less the meals planned from it since.
/// It is good until the cook day plus the recipe's fridge life, that day
/// included, and never stretches to a later meal ([useByOf]); a recipe with
/// no stated fridge life keeps [kAssumedFridgeDays]. Freezer dates count from
/// the cook day too.
library;

import 'dart:math' show min;

import 'package:meta/meta.dart';

import 'cook_plan.dart';

/// The fridge life a recipe with none stated is taken to have, for a derived
/// and a stored row alike.
const kAssumedFridgeDays = 7;

/// Whether anybody ticked any meal [session] covers: proof it was cooked.
bool wasCooked(CookSession session) =>
    session.covers.any((m) => m.eatenPortions > 1e-9);

/// The date [day] of the week beginning [weekStart] names. [day] may run past
/// the week (a meal of the next week a batch folded in).
DateTime dateOfDay(DateTime weekStart, int day) =>
    DateTime(weekStart.year, weekStart.month, weekStart.day + day);

/// The day [session] — of the week beginning [weekStart] — is cooked, as an
/// offset from [weekStart], on [today].
///
/// The earliest covered day anybody ticked, in whatever order the ticks came;
/// with no tick, the first covered day not yet behind [today]. Null when no
/// meal was ticked and every one is behind: it was never cooked.
int? cookDayOf(CookSession session, DateTime weekStart, DateTime today) {
  int? earliest(Iterable<int> days) => days.isEmpty ? null : days.reduce(min);
  final ticked = earliest([
    for (final m in session.covers)
      if (m.eatenPortions > 1e-9) m.dayOfWeek,
  ]);
  if (ticked != null) return ticked;
  final day = _dateOnly(today);
  return earliest([
    for (final m in session.covers)
      if (!dateOfDay(weekStart, m.dayOfWeek).isBefore(day)) m.dayOfWeek,
  ]);
}

/// [session] cooked on its day by the ticks ([cookDayOf]) rather than its
/// planned one: what the week strip, the meal's sheet and Cook draw. Its
/// planned day when it was never cooked, and for a component batch.
CookSession sessionByTicks(
  CookSession session,
  DateTime weekStart,
  DateTime today,
) {
  if (session.isComponent) return session;
  final day = cookDayOf(session, weekStart, today);
  return day == null || day == session.cookDay
      ? session
      : session.copyWith(cookDay: day);
}

/// [session]'s fridge date in the week beginning [weekStart], on [today]: its
/// cook day ([cookDayOf]) plus its fridge life, that day included. Null when
/// it was never cooked.
DateTime? useByOf(CookSession session, DateTime weekStart, DateTime today) {
  final cookDay = cookDayOf(session, weekStart, today);
  if (cookDay == null) return null;
  return dateOfDay(
    weekStart,
    cookDay + (session.keepsForDays ?? kAssumedFridgeDays),
  );
}

/// The part of a batch that goes in the freezer for its later meals: the
/// `portions` to freeze, by `freezeBy` (its fridge date), for the meals on
/// `forDays`.
typedef FreezeShare = ({
  double portions,
  DateTime freezeBy,
  List<DateTime> forDays,
});

/// The meals of a freezable [session] past its fridge date ([useByOf]), which
/// it reaches from the freezer: `freeze 2 by Tue for Thu`. Null when it has
/// none, is not freezable, or was never cooked.
FreezeShare? freezeShareOf(
  CookSession session,
  DateTime weekStart,
  DateTime today,
) {
  if (!session.freezable || session.isComponent) return null;
  final until = useByOf(session, weekStart, today);
  if (until == null) return null;
  var portions = 0.0;
  final days = <DateTime>{};
  for (final m in session.covers) {
    final day = dateOfDay(weekStart, m.dayOfWeek);
    final still = m.portions - m.eatenPortions;
    if (!day.isAfter(until) || still <= 1e-9) continue;
    portions += still;
    days.add(day);
  }
  if (days.isEmpty) return null;
  return (portions: portions, freezeBy: until, forDays: days.toList()..sort());
}

/// Where a leftover is kept.
enum LeftoverPlace { fridge, freezer }

/// What is wrong with a meal planned from a leftover, on that meal's own day.
/// A warning, never an edit: the plan stays as the household made it.
enum LeftoverWarning {
  /// The meals planned from the row before it, and it, ask more than is
  /// left; or the food is not cooked yet on its day.
  notEnoughLeft,

  /// Its day is past the row's date, and freezing could not reach it.
  pastItsDate,
}

/// One meal served from a leftover row: planned from it (`leftover_of` or
/// `from_leftover`), or a later meal of the batch it came from ([own]).
@immutable
class LeftoverMeal {
  const LeftoverMeal({
    required this.day,
    required this.portions,
    this.entryId,
    this.place,
    this.freezeBy,
    this.warning,
    this.own = false,
  });

  /// The planned meal, where it has an id.
  final String? entryId;

  final DateTime day;

  /// What it takes from the row: its demand, less what its eaters already
  /// ate for one of the batch's own meals.
  final double portions;

  /// The shelf it is eaten from on [day]; null when nothing is good that day.
  final LeftoverPlace? place;

  /// Set when it is eaten from the freezer while the row is still in the
  /// fridge: the day to freeze it by, the row's fridge date.
  final DateTime? freezeBy;

  final LeftoverWarning? warning;

  /// One of the batch's own covered meals after its cook day, not a meal
  /// planned from the row.
  final bool own;

  @override
  String toString() =>
      'LeftoverMeal($entryId, $day, $portions, ${place?.name}'
      '${freezeBy == null ? '' : ', freeze by $freezeBy'}'
      '${warning == null ? '' : ', ${warning!.name}'})';
}

/// A recipe's name and shelf life, as a stored row's date reads them.
typedef LeftoverRecipe = ({
  String title,
  int? keepsForDays,
  int? freezerDays,
  bool freezable,
});

/// A meal planned from a leftover, as the reader hands it in: the planned
/// meal, its day and its demand.
typedef PlannedFromLeftover = ({String entryId, DateTime day, double portions});

/// One member's tick on a meal, as the reader hands it in: the share of the
/// meal it eats, and from when to when it stood (`until` null while it
/// stands). An untick ends it; a tick again is a new one.
typedef TickSpan = ({
  String memberId,
  double share,
  DateTime from,
  DateTime? until,
});

/// A `leftover` row as stored: what the household said is in the fridge or
/// the freezer. Exactly one of [recipeId] or [label].
@immutable
class StoredLeftover {
  const StoredLeftover({
    required this.id,
    required this.place,
    required this.portions,
    required this.since,
    required this.updatedAt,
    this.recipeId,
    this.label,
    this.batch,
    this.goneAt,
  }) : assert(
         (recipeId == null) != (label == null),
         'a recipe or words, never both (the server refuses it)',
       );

  final String id;
  final LeftoverPlace place;
  final String? recipeId;

  /// The household's own words for food the app has no recipe for.
  final String? label;

  /// What was said to be in the box, at [updatedAt]. For a row naming a
  /// cooked [batch], it is read as an adjustment to what the ticks made of
  /// the batch then, so every tick or untick after it still moves it.
  final double portions;

  /// The day it was cooked; for a freezer row stored before freezer dates
  /// counted from the cook day, the day it went in.
  final DateTime since;

  /// The cooked batch this row replaces ([CookSession.leftoverKey]), or null
  /// for a row added by hand.
  final String? batch;

  /// When it was said to be gone; null while it is still there.
  final DateTime? goneAt;

  /// When the count was said; which of two rows for one batch wins: the
  /// newest.
  final DateTime updatedAt;
}

/// One row of the household's leftovers: a cooked batch nobody has said
/// anything about yet (derived, [id] null) or a stored row.
@immutable
class Leftover {
  const Leftover({
    required this.place,
    required this.title,
    required this.since,
    required this.goodUntil,
    required this.portions,
    this.id,
    this.batch,
    this.recipeId,
    this.planned = 0,
    double? inBox,
    this.freezable = false,
    this.freezerUntil,
    this.freezeBy,
    this.meals = const [],
  }) : _inBox = inBox;

  /// The stored row's id; null for a row derived from a cooked batch.
  final String? id;

  /// The cooked batch it came from ([CookSession.leftoverKey]); null for a row
  /// added by hand.
  final String? batch;

  /// Where it is today. A fridge row with a meal planned from it past its
  /// fridge date is taken to have been frozen once that date is behind us.
  final LeftoverPlace place;

  /// The recipe, or null for a row in the household's own words.
  final String? recipeId;

  /// The recipe's title, or the household's words.
  final String title;

  /// The day it was cooked, which its fridge and freezer dates count from. A
  /// batch not cooked yet has the day it will be.
  final DateTime since;

  /// The last day it is good on [place], inclusive; null when there is no
  /// limit (a freezer with no `freezer_days`) or it is in words.
  final DateTime? goodUntil;

  /// The portions left, less the meals planned from it: never below zero.
  /// Zero while meals still to come take all of it ([planned]).
  final double portions;

  /// The portions of the meals still to come (today or later) that are
  /// served from it: in the box, spoken for, and not in [portions].
  final double planned;

  final double? _inBox;

  /// What is in the box today, spoken for or not: the `N left` the Leftovers
  /// page and Cook print, and what its stepper sets. Never below zero.
  double get inBox => _inBox ?? portions + planned;

  /// Whether the dish freezes.
  final bool freezable;

  /// For a freezable dish, the last day it is good frozen, counted from the
  /// cook day; null when the freezer has no limit or it does not freeze.
  final DateTime? freezerUntil;

  /// Set on a fridge row that has to be frozen for a meal past its fridge
  /// date (`freeze by Mon for Wed`): that date. Also set on a row the picker
  /// offers under Freezer for a day it will need freezing for.
  final DateTime? freezeBy;

  /// The meals served from it, in day order, each judged on its own day:
  /// planned from it, and a derived row's own later meals.
  final List<LeftoverMeal> meals;

  bool get isStored => id != null;

  /// Whether it has been cooked by [today]: a batch not cooked yet is offered
  /// for a day from its cook day on, but is not in the fridge.
  bool isCookedBy(DateTime today) => !since.isAfter(_dateOnly(today));

  /// The shelf it is eaten from on [day], or null when nothing of it is good
  /// then: before its cook day, or past every date it can reach. A fridge row
  /// of a freezable dish reaches past its fridge date from the freezer.
  LeftoverPlace? shelfOn(DateTime day) => _shelfOn(
    _dateOnly(day),
    since: since,
    place: place,
    goodUntil: goodUntil,
    freezable: freezable,
    freezerUntil: freezerUntil,
  );

  /// Whether its date is behind [today]. It stays until somebody says it is
  /// gone: nothing clears itself.
  bool pastItsDate(DateTime today) {
    final until = goodUntil;
    return until != null && _dateOnly(today).isAfter(until);
  }

  /// This row as the picker offers it for a day reached only from the
  /// freezer: under Freezer, good until its freezer date, to be frozen by
  /// its fridge date.
  Leftover frozenForLater() => Leftover(
    id: id,
    batch: batch,
    place: LeftoverPlace.freezer,
    recipeId: recipeId,
    title: title,
    since: since,
    goodUntil: freezerUntil,
    portions: portions,
    planned: planned,
    inBox: _inBox,
    freezable: freezable,
    freezerUntil: freezerUntil,
    freezeBy: goodUntil,
    meals: meals,
  );

  @override
  String toString() =>
      'Leftover(${place.name}: $title, $portions, since $since, '
      'until $goodUntil${isStored ? ', stored' : ''})';
}

/// [left] as the planning picker offers it for a meal on [day], or null when
/// it is not offered: a row in words, nothing left to plan, past its date on
/// [today], or not good on [day].
///
/// Freshness is judged on [day], not [today]. A fridge row good on [day] is
/// offered from the fridge. One past its fridge date by then, of a dish that
/// freezes and would be in date frozen, is offered under Freezer, to be
/// frozen by its fridge date ([Leftover.frozenForLater]).
Leftover? leftoverOfferOn(Leftover left, DateTime day, DateTime today) {
  if (left.recipeId == null ||
      left.portions <= 1e-9 ||
      left.pastItsDate(today)) {
    return null;
  }
  return switch (left.shelfOn(day)) {
    null => null,
    final shelf when shelf == left.place => left,
    _ => left.frozenForLater(),
  };
}

/// The household's leftovers on a day: the rows the Leftovers page and the
/// picker read, and every meal served from one, by its planned meal's id.
@immutable
class LeftoverShelves {
  const LeftoverShelves({this.rows = const [], this.meals = const {}});

  /// Fridge first, then freezer; within each, soonest to go off first and
  /// past its date last.
  final List<Leftover> rows;

  /// Each meal planned from a leftover (and each later meal of a cooked
  /// batch) judged on its own day, by `plan_entry` id: the Week's tag. A meal
  /// planned from a row that is gone or never cooked is here too, warned.
  final Map<String, LeftoverMeal> meals;
}

/// How far back a cooked batch is still read as a leftover: one cooked
/// earlier, with nothing said about it, is not shown.
const kLeftoverHorizon = Duration(days: 28);

/// The starts of the weeks that can hold a batch cooked inside
/// [kLeftoverHorizon] of a day in the week beginning [weekStart], oldest
/// first: the four before it and the week itself.
List<DateTime> leftoverWeekStarts(DateTime weekStart) => [
  for (var back = kLeftoverHorizon.inDays ~/ 7; back >= 0; back--)
    DateTime(weekStart.year, weekStart.month, weekStart.day - 7 * back),
];

/// The household's leftovers on [today].
///
/// [weeks] are the cooked weeks to read, each with its derived [CookPlan]
/// ([leftoverWeekStarts] names them); a batch cooked more than
/// [kLeftoverHorizon] before [today] is left out. [stored] are the live
/// `leftover` rows, and [recipes] the live recipes they name, by id.
///
/// - A stored row with a `batch` replaces that batch's derived row, gone or
///   not. Two rows for one batch (two phones, offline) read as the newest.
/// - A row is shown until its `gone_at`, however far past its date, while it
///   has portions left or meals still to come.
/// - Each row's portions fall by the meals planned from it: [fromBatch] by
///   batch key (`plan_entry.leftover_of`), and [fromRow] by stored row id
///   (`plan_entry.from_leftover`).
/// - A batch Cook was told about ([answers]: binned or eaten) reads as gone.
List<Leftover> householdLeftovers({
  required List<({DateTime weekStart, CookPlan plan})> weeks,
  required DateTime today,
  List<StoredLeftover> stored = const [],
  Map<String, LeftoverRecipe> recipes = const {},
  Map<String, LeftoverAnswer> answers = const {},
  Map<String, List<PlannedFromLeftover>> fromBatch = const {},
  Map<String, List<PlannedFromLeftover>> fromRow = const {},
  Map<String, List<TickSpan>> ticks = const {},
}) => readLeftovers(
  weeks: weeks,
  today: today,
  stored: stored,
  recipes: recipes,
  answers: answers,
  fromBatch: fromBatch,
  fromRow: fromRow,
  ticks: ticks,
).rows;

/// [householdLeftovers], with every meal served from a row judged on its own
/// day ([LeftoverShelves.meals]).
///
/// **A count set by hand is an adjustment.** A stored row naming a batch
/// reads as what the ticks make of the batch now, moved by what was said
/// against what they made of it when it was said ([StoredLeftover.portions]
/// at its `updated_at`): set to 1 where the ticks made 2, an untick of 2 then
/// reads 3, and a tick again 1. [ticks] (by `plan_entry` id, unticked ones
/// included) say what was ticked when; without them a count is taken against
/// the ticks as they stand. It never reads below nothing.
LeftoverShelves readLeftovers({
  required List<({DateTime weekStart, CookPlan plan})> weeks,
  required DateTime today,
  List<StoredLeftover> stored = const [],
  Map<String, LeftoverRecipe> recipes = const {},
  Map<String, LeftoverAnswer> answers = const {},
  Map<String, List<PlannedFromLeftover>> fromBatch = const {},
  Map<String, List<PlannedFromLeftover>> fromRow = const {},
  Map<String, List<TickSpan>> ticks = const {},
}) {
  final day = _dateOnly(today);
  final meals = <String, LeftoverMeal>{};
  final rows = <Leftover>[];

  void add(_Row? row) {
    if (row == null) return;
    for (final m in row.meals) {
      if (m.entryId case final id?) meals[id] = m;
    }
    if (row.shown) rows.add(row.left);
  }

  // Every batch of the weeks read, by key: a stored row naming one still
  // carries its later meals.
  final batches = <String, ({CookSession session, DateTime weekStart})>{};
  for (final week in weeks) {
    for (final recipe in week.plan.recipes) {
      for (final session in recipe.mealSessions) {
        if (session.leftoverKey case final key?) {
          batches[key] = (session: session, weekStart: week.weekStart);
        }
      }
    }
  }

  // One row per batch, the newest; every row added by hand stands alone. The
  // meals planned from a losing duplicate still come off the winner: it is
  // the same food.
  final byBatch = <String, List<StoredLeftover>>{};
  for (final row in stored) {
    final batch = row.batch;
    if (batch == null) {
      add(_storedRow(row, fromRow[row.id] ?? const [], recipes, day));
    } else {
      (byBatch[batch] ??= []).add(row);
    }
  }
  for (final MapEntry(key: key, value: group) in byBatch.entries) {
    final newest = group.reduce(
      (a, b) =>
          b.updatedAt.isAfter(a.updatedAt) ||
              (b.updatedAt == a.updatedAt && b.id.compareTo(a.id) > 0)
          ? b
          : a,
    );
    add(
      _storedRow(
        newest,
        [for (final r in group) ...?fromRow[r.id], ...?fromBatch[key]],
        recipes,
        day,
        batch: batches[key],
        ticks: ticks,
      ),
    );
  }

  final horizon = DateTime(
    day.year,
    day.month,
    day.day - kLeftoverHorizon.inDays,
  );
  for (final MapEntry(key: key, value: batch) in batches.entries) {
    if (byBatch.containsKey(key)) continue;
    add(
      _derivedRow(
        batch.session,
        key,
        weekStart: batch.weekStart,
        today: day,
        horizon: horizon,
        gone: _answered(answers[key]),
        planned: fromBatch[key] ?? const [],
      ),
    );
  }

  // Soonest to go off first, past its date last; a row with no date after
  // every dated one.
  rows.sort((a, b) {
    final place = a.place.index.compareTo(b.place.index);
    if (place != 0) return place;
    final past = (a.pastItsDate(day) ? 1 : 0) - (b.pastItsDate(day) ? 1 : 0);
    if (past != 0) return past;
    final until = switch ((a.goodUntil, b.goodUntil)) {
      (null, null) => 0,
      (null, _) => 1,
      (_, null) => -1,
      (final x?, final y?) => x.compareTo(y),
    };
    if (until != 0) return until;
    final since = a.since.compareTo(b.since);
    return since != 0 ? since : a.title.compareTo(b.title);
  });
  return LeftoverShelves(rows: List.unmodifiable(rows), meals: meals);
}

/// Whether Cook was told what became of a batch: binned or eaten.
bool _answered(LeftoverAnswer? answer) =>
    answer != null && answer.binned + answer.eaten > 1e-9;

/// One of a cooked batch's later meals: what it still takes from the batch,
/// its eaters' ticks taken off.
typedef _OwnMeal = ({String? entryId, DateTime day, double portions});

/// The meals of [session] (of the week beginning [weekStart]) after its cook
/// day, on [today]. None while it was never ticked.
List<_OwnMeal> _laterMeals(
  CookSession session,
  DateTime weekStart,
  DateTime today,
) {
  final cookDay = cookDayOf(session, weekStart, today);
  if (cookDay == null || !wasCooked(session)) return const [];
  return [
    for (final m in session.covers)
      if (m.dayOfWeek > cookDay)
        (
          entryId: m.entryId,
          day: dateOfDay(weekStart, m.dayOfWeek),
          portions: m.portions - m.eatenPortions,
        ),
  ];
}

/// A row's portions: `free` to plan from, `ahead` spoken for by meals still
/// to come, and `inBox` in all ([Leftover.inBox]).
typedef _Count = ({double free, double ahead, double inBox});

/// A row being read: the [Leftover] the page would draw, the meals it serves,
/// and whether it is shown at all.
typedef _Row = ({Leftover left, List<LeftoverMeal> meals, bool shown});

/// A cooked (or still to be cooked) batch's derived fridge row. Null when it
/// was never cooked or was cooked before [horizon]; a batch told gone, or
/// never cooked, still judges the meals planned from it.
_Row? _derivedRow(
  CookSession session,
  String key, {
  required DateTime weekStart,
  required DateTime today,
  required DateTime horizon,
  required bool gone,
  required List<PlannedFromLeftover> planned,
}) {
  final cookDay = cookDayOf(session, weekStart, today);
  final since = cookDay == null ? null : dateOfDay(weekStart, cookDay);
  if (since != null && since.isBefore(horizon)) return null;

  final left = _leftBehind(session, weekStart, today);
  final dates = _Dates(
    since: since,
    fridgeDays: session.keepsForDays ?? kAssumedFridgeDays,
    freezable: session.freezable,
    freezerDays: session.freezerDays,
  );
  return _read(
    dates,
    available: since == null || gone ? 0 : left,
    planned: planned,
    own: _laterMeals(session, weekStart, today),
    today: today,
    shown: since != null && !gone,
    build: (place, goodUntil, freezeBy, count, meals) => Leftover(
      place: place,
      batch: key,
      recipeId: session.recipeId,
      title: session.recipeTitle,
      since: since ?? today,
      goodUntil: goodUntil,
      portions: count.free,
      planned: count.ahead,
      inBox: count.inBox,
      freezable: session.freezable,
      freezerUntil: dates.freezerUntil,
      freezeBy: freezeBy,
      meals: meals,
    ),
  );
}

/// A stored row, read on [today]. Null for a row whose recipe is gone; a row
/// said gone still judges the meals planned from it.
///
/// Its count is what was said to be in the box, moved since by what the
/// ticks and the days did to its [batch]: the box the batch would derive now,
/// less the box it derived when the count was said ([_batchBox]). A row
/// with no batch read moves only by the meals planned from it since. Every
/// meal planned from it, and the batch's own later meals, ride on it.
_Row? _storedRow(
  StoredLeftover row,
  List<PlannedFromLeftover> planned,
  Map<String, LeftoverRecipe> recipes,
  DateTime today, {
  ({CookSession session, DateTime weekStart})? batch,
  Map<String, List<TickSpan>> ticks = const {},
}) {
  final since = _dateOnly(row.since);
  final recipeId = row.recipeId;
  final String title;
  final _Dates dates;
  final fridge = row.place == LeftoverPlace.fridge;
  if (recipeId == null) {
    // Words have no shelf life to read: in the fridge they keep the week a
    // recipe with none stated keeps; in the freezer, only an age.
    title = row.label!;
    dates = _Dates(
      since: since,
      fridgeDays: fridge ? kAssumedFridgeDays : null,
      inFreezer: !fridge,
    );
  } else {
    // A recipe deleted since (or not yet synced) takes its row with it, as it
    // takes its batches out of the cook plan.
    final recipe = recipes[recipeId];
    if (recipe == null) return null;
    title = recipe.title;
    dates = _Dates(
      since: since,
      fridgeDays: fridge ? recipe.keepsForDays ?? kAssumedFridgeDays : null,
      freezable: recipe.freezable,
      freezerDays: recipe.freezerDays,
      inFreezer: !fridge,
    );
  }
  final gone = row.goneAt != null;
  final said = row.updatedAt;
  // Never after today: a clock ahead of the household's does not move it.
  final saidLocal = _dateOnly(said.toLocal());
  final saidOn = saidLocal.isAfter(today) ? today : saidLocal;
  final own = batch == null
      ? const <_OwnMeal>[]
      : _laterMeals(batch.session, batch.weekStart, today);
  final double box;
  if (batch == null) {
    box =
        row.portions -
        _plannedBehind(planned, today) +
        _plannedBehind(planned, saidOn);
  } else {
    final then = _sessionAsOf(batch.session, said, ticks);
    box =
        row.portions +
        _batchBox(batch.session, batch.weekStart, today, planned) -
        _batchBox(then, batch.weekStart, saidOn, planned);
  }
  // What [_read] takes off and puts back to find the box.
  var ownAhead = 0.0;
  for (final m in own) {
    if (!m.day.isBefore(today) && m.portions > 1e-9) ownAhead += m.portions;
  }
  final available =
      (box > 1e-9 ? box : 0) + _plannedBehind(planned, today) - ownAhead;
  return _read(
    dates,
    available: gone ? 0 : available,
    planned: planned,
    own: own,
    today: today,
    shown: !gone,
    build: (place, goodUntil, freezeBy, count, meals) => Leftover(
      id: row.id,
      batch: row.batch,
      place: place,
      recipeId: recipeId,
      title: title,
      since: since,
      goodUntil: goodUntil,
      portions: count.free,
      planned: count.ahead,
      inBox: count.inBox,
      freezable: dates.freezable,
      freezerUntil: dates.freezerUntil,
      freezeBy: freezeBy,
      meals: meals,
    ),
  );
}

/// The portions of [session]'s meals behind [today] that nobody ate: made is
/// what was planned, so a skipped meal is left over, one before the cook
/// day included.
double _leftBehind(CookSession session, DateTime weekStart, DateTime today) {
  var left = 0.0;
  for (final m in session.covers) {
    if (dateOfDay(weekStart, m.dayOfWeek).isBefore(today)) {
      left += m.portions - m.eatenPortions;
    }
  }
  return left;
}

/// The portions of the meals planned from a row whose day is behind [today]:
/// eaten from it.
double _plannedBehind(List<PlannedFromLeftover> planned, DateTime today) {
  var behind = 0.0;
  for (final m in planned) {
    if (_dateOnly(m.day).isBefore(today)) behind += m.portions;
  }
  return behind;
}

/// What a derived row of [session] holds in its box on [today], with
/// [planned] meals from it, unclamped: its meals behind us nobody ate, less
/// the planned ones behind us, plus its own later meals still to come.
/// Nothing while it was never cooked.
double _batchBox(
  CookSession session,
  DateTime weekStart,
  DateTime today,
  List<PlannedFromLeftover> planned,
) {
  if (cookDayOf(session, weekStart, today) == null) return 0;
  var box =
      _leftBehind(session, weekStart, today) - _plannedBehind(planned, today);
  for (final m in _laterMeals(session, weekStart, today)) {
    if (!m.day.isBefore(today) && m.portions > 1e-9) box += m.portions;
  }
  return box;
}

/// [session] as it was ticked at [at], read off [ticks]; a meal with none
/// handed in keeps its ticks as they stand.
CookSession _sessionAsOf(
  CookSession session,
  DateTime at,
  Map<String, List<TickSpan>> ticks,
) {
  if (ticks.isEmpty) return session;
  return session.copyWith(
    covers: [
      for (final m in session.covers)
        if (ticks[m.entryId] case final spans?)
          m.copyWith(eatenPortions: _eatenAt(spans, at, m.portions))
        else
          m,
    ],
  );
}

/// The share of a meal of [portions] its eaters had ticked at [at]: each
/// member once, however many of their ticks stood.
double _eatenAt(List<TickSpan> spans, DateTime at, double portions) {
  final shares = <String, double>{};
  for (final t in spans) {
    final until = t.until;
    if (!t.from.isAfter(at) && (until == null || until.isAfter(at))) {
      shares[t.memberId] = t.share;
    }
  }
  final eaten = shares.values.fold<double>(0, (a, b) => a + b);
  return eaten > portions ? portions : eaten;
}

/// A row's dates: its cook day and how long it keeps where.
class _Dates {
  _Dates({
    required this.since,
    int? fridgeDays,
    this.freezable = false,
    int? freezerDays,
    this.inFreezer = false,
  }) : fridgeUntil = _plus(since, fridgeDays),
       freezerUntil = freezable || inFreezer ? _plus(since, freezerDays) : null;

  final DateTime? since;

  /// The last fridge day; null for a freezer row or one in words.
  final DateTime? fridgeUntil;

  final bool freezable;

  /// The last freezer day; null with no limit or for a dish that does not
  /// freeze.
  final DateTime? freezerUntil;

  /// Stored in the freezer, as said.
  final bool inFreezer;

  /// The shelf a meal on [day] is eaten from, as the row stands before any
  /// freeze is assumed.
  LeftoverPlace? shelfOn(DateTime day) {
    final from = since;
    if (from == null) return null;
    return _shelfOn(
      day,
      since: from,
      place: inFreezer ? LeftoverPlace.freezer : LeftoverPlace.fridge,
      goodUntil: inFreezer ? freezerUntil : fridgeUntil,
      freezable: freezable,
      freezerUntil: freezerUntil,
    );
  }

  static DateTime? _plus(DateTime? day, int? days) =>
      day == null || days == null
      ? null
      : DateTime(day.year, day.month, day.day + days);
}

LeftoverPlace? _shelfOn(
  DateTime day, {
  required DateTime since,
  required LeftoverPlace place,
  required DateTime? goodUntil,
  required bool freezable,
  required DateTime? freezerUntil,
}) {
  if (day.isBefore(since)) return null;
  final inDate = goodUntil == null || !day.isAfter(goodUntil);
  if (place == LeftoverPlace.freezer) return inDate ? place : null;
  if (inDate) return LeftoverPlace.fridge;
  if (freezable && (freezerUntil == null || !day.isAfter(freezerUntil))) {
    return LeftoverPlace.freezer;
  }
  return null;
}

/// Judges every meal served from a row on its own day, in day order, and
/// builds the row as it stands on [today].
///
/// [available] is what is free in the box before the meals planned from it
/// come off: neither those meals nor [own], a cooked batch's later meals,
/// whose portions still to come are spoken for on top of it. Once the fridge
/// date is behind [today], a row with a meal eaten past it from the freezer
/// is taken to have been frozen.
_Row _read(
  _Dates dates, {
  required double available,
  required List<PlannedFromLeftover> planned,
  required List<_OwnMeal> own,
  required DateTime today,
  required bool shown,
  required Leftover Function(
    LeftoverPlace place,
    DateTime? goodUntil,
    DateTime? freezeBy,
    _Count count,
    List<LeftoverMeal> meals,
  )
  build,
}) {
  final fridgeUntil = dates.inFreezer ? null : dates.fridgeUntil;
  DateTime? freezeByOf(LeftoverPlace? shelf) =>
      shelf == LeftoverPlace.freezer && !dates.inFreezer ? fridgeUntil : null;

  final sorted = [...planned]
    ..sort((a, b) {
      final d = a.day.compareTo(b.day);
      return d != 0 ? d : a.entryId.compareTo(b.entryId);
    });
  var rest = available;
  final meals = <LeftoverMeal>[];
  for (final m in sorted) {
    final day = _dateOnly(m.day);
    final shelf = dates.shelfOn(day);
    final notCooked = dates.since == null || day.isBefore(dates.since!);
    final warning = notCooked || m.portions > rest + 1e-9
        ? LeftoverWarning.notEnoughLeft
        : shelf == null
        ? LeftoverWarning.pastItsDate
        : null;
    rest -= m.portions;
    meals.add(
      LeftoverMeal(
        entryId: m.entryId,
        day: day,
        portions: m.portions,
        place: shelf,
        freezeBy: freezeByOf(shelf),
        warning: warning,
      ),
    );
  }
  for (final m in own) {
    final day = _dateOnly(m.day);
    final shelf = dates.shelfOn(day);
    meals.add(
      LeftoverMeal(
        entryId: m.entryId,
        day: day,
        portions: m.portions > 1e-9 ? m.portions : 0,
        place: shelf,
        freezeBy: freezeByOf(shelf),
        warning: shelf == null ? LeftoverWarning.pastItsDate : null,
        own: true,
      ),
    );
  }
  meals.sort((a, b) => a.day.compareTo(b.day));

  final ahead = [
    for (final m in meals)
      if (!m.day.isBefore(today)) m,
  ];
  final aheadPortions = ahead.fold<double>(0, (s, m) => s + m.portions);
  final left = rest > 1e-9 ? rest : 0.0;
  // In the box: what is free, less the planned meals already behind us,
  // plus the batch's own meals still to come.
  var inBox = available - _plannedBehind(sorted, today);
  for (final m in own) {
    if (!m.day.isBefore(today) && m.portions > 1e-9) inBox += m.portions;
  }
  if (inBox < 1e-9) inBox = 0;
  final count = (free: left, ahead: aheadPortions, inBox: inBox);

  // A meal eaten from the freezer past the fridge date says it was frozen.
  final frozenFor = [
    for (final m in meals)
      if (m.freezeBy != null) m,
  ];
  final LeftoverPlace place;
  final DateTime? goodUntil;
  DateTime? freezeBy;
  if (dates.inFreezer) {
    place = LeftoverPlace.freezer;
    goodUntil = dates.freezerUntil;
  } else if (fridgeUntil != null &&
      today.isAfter(fridgeUntil) &&
      frozenFor.isNotEmpty) {
    place = LeftoverPlace.freezer;
    goodUntil = dates.freezerUntil;
  } else {
    place = LeftoverPlace.fridge;
    goodUntil = fridgeUntil;
    if (ahead.any((m) => m.freezeBy != null)) freezeBy = fridgeUntil;
  }
  final judged = [
    for (final m in meals)
      if (place == LeftoverPlace.freezer && m.freezeBy != null)
        LeftoverMeal(
          entryId: m.entryId,
          day: m.day,
          portions: m.portions,
          place: m.place,
          warning: m.warning,
          own: m.own,
        )
      else
        m,
  ];
  return (
    left: build(place, goodUntil, freezeBy, count, List.unmodifiable(judged)),
    meals: judged,
    shown: shown && (inBox > 1e-9 || aheadPortions > 1e-9),
  );
}

DateTime _dateOnly(DateTime d) => DateTime(d.year, d.month, d.day);
