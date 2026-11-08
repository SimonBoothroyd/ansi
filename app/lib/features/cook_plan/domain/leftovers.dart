/// What a cooked batch has left, and until when; and the household's
/// leftovers, fridge and freezer, as those batches and what was said about
/// them make them. Pure Dart.
///
/// A batch — one meal [CookSession] — counts as **cooked** once anybody ticked
/// any meal it covers; the household ticks reliably, so a batch nobody ticked
/// was never cooked and its ingredients are spare food instead (never a
/// leftover). A cooked batch's **leftover** is the portions of its meals
/// already behind us that nobody ate, less the meals planned from it since. It
/// is good until its **use-by**: the cook day plus the recipe's fridge life,
/// never before the batch's own last meal.
library;

import 'package:meta/meta.dart';

import 'cook_plan.dart';

/// One cooked batch's leftover, on one day.
@immutable
class BatchLeftover {
  const BatchLeftover({
    required this.key,
    required this.recipeId,
    required this.title,
    required this.cookDate,
    required this.useBy,
    required this.portions,
  });

  /// The batch's key: its first covered meal ([CookSession.leftoverKey]), the
  /// same key `batch_leftover` and `plan_entry.leftover_of` name.
  final String key;

  final String recipeId;
  final String title;

  /// The day the batch was cooked.
  final DateTime cookDate;

  /// The last day it is good, inclusive.
  final DateTime useBy;

  /// The portions still left: never zero or less.
  final double portions;

  @override
  bool operator ==(Object other) =>
      other is BatchLeftover &&
      other.key == key &&
      other.recipeId == recipeId &&
      other.title == title &&
      other.cookDate == cookDate &&
      other.useBy == useBy &&
      other.portions == portions;

  @override
  int get hashCode =>
      Object.hash(key, recipeId, title, cookDate, useBy, portions);

  @override
  String toString() =>
      'BatchLeftover($title, $portions left, good until $useBy)';
}

/// Whether anybody ticked any meal [session] covers: proof it was cooked.
bool wasCooked(CookSession session) =>
    session.covers.any((m) => m.eatenPortions > 1e-9);

/// The date [day] (0..6) of the week beginning [weekStart] names.
DateTime dateOfDay(DateTime weekStart, int day) =>
    DateTime(weekStart.year, weekStart.month, weekStart.day + day);

/// [session]'s use-by in the week beginning [weekStart]: its cook day plus its
/// fridge life, but never before its own last meal (a freezer share can reach
/// past the fridge window). An unknown fridge life is the last meal's day, so
/// such a batch is past its date as soon as its days are over.
DateTime useByOf(CookSession session, DateTime weekStart) {
  final last = dateOfDay(weekStart, session.lastCoveredDay);
  final keeps = session.keepsForDays;
  if (keeps == null) return last;
  final fridge = dateOfDay(weekStart, session.cookDay + keeps);
  return fridge.isAfter(last) ? fridge : last;
}

/// The cooked batches of [plan] — the week beginning [weekStart] — that still
/// have portions left on [today].
///
/// Only meals on a day before [today] can have been left: today's and later
/// ones are still to be eaten. [plannedFrom] is the demand of the meals
/// planned from each batch since, keyed by batch.
List<BatchLeftover> batchLeftovers(
  CookPlan plan, {
  required DateTime weekStart,
  required DateTime today,
  Map<String, double> plannedFrom = const {},
}) {
  final day = _dateOnly(today);
  return [
    for (final recipe in plan.recipes)
      for (final session in recipe.mealSessions)
        if (_leftoverOf(
              session,
              weekStart: weekStart,
              today: day,
              plannedFrom: plannedFrom,
            )
            case final left?)
          left,
  ];
}

BatchLeftover? _leftoverOf(
  CookSession session, {
  required DateTime weekStart,
  required DateTime today,
  required Map<String, double> plannedFrom,
}) {
  final key = session.leftoverKey;
  if (key == null || !wasCooked(session)) return null;
  final uneaten = session.covers
      .where((m) => dateOfDay(weekStart, m.dayOfWeek).isBefore(today))
      .fold<double>(0, (sum, m) => sum + (m.portions - m.eatenPortions));
  final left = uneaten - (plannedFrom[key] ?? 0);
  if (left <= 1e-9) return null;
  return BatchLeftover(
    key: key,
    recipeId: session.recipeId,
    title: session.recipeTitle,
    cookDate: dateOfDay(weekStart, session.cookDay),
    useBy: useByOf(session, weekStart),
    portions: left,
  );
}

/// Where a leftover is kept.
enum LeftoverPlace { fridge, freezer }

/// A recipe's name and shelf life, as a stored row's date reads them.
typedef LeftoverRecipe = ({String title, int? keepsForDays, int? freezerDays});

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

  /// The portions as said, before the meals planned from the row.
  final double portions;

  /// The day it was cooked (fridge) or went into the freezer.
  final DateTime since;

  /// The cooked batch this row replaces ([CookSession.leftoverKey]), or null
  /// for a row added by hand.
  final String? batch;

  /// When it was said to be gone; null while it is still there.
  final DateTime? goneAt;

  /// Which of two rows for one batch wins: the newest.
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
  });

  /// The stored row's id; null for a row derived from a cooked batch.
  final String? id;

  /// The cooked batch it came from ([CookSession.leftoverKey]); null for a row
  /// added by hand.
  final String? batch;

  final LeftoverPlace place;

  /// The recipe, or null for a row in the household's own words.
  final String? recipeId;

  /// The recipe's title, or the household's words.
  final String title;

  /// The day it was cooked (fridge) or frozen (freezer).
  final DateTime since;

  /// The last day it is good, inclusive; null when there is no limit (a
  /// freezer with no `freezer_days`), no known shelf life, or it is in words.
  final DateTime? goodUntil;

  /// The portions left, less the meals planned from it: never zero or less.
  final double portions;

  /// The portions of the meals planned from it on today or later: still in
  /// the box, spoken for, and not in [portions].
  final double planned;

  bool get isStored => id != null;

  /// Whether a meal on [day] can be planned from it: a fridge row from its
  /// cook day until its date, a freezer row on any day.
  bool isGoodOn(DateTime day) {
    if (place == LeftoverPlace.freezer) return true;
    final d = _dateOnly(day);
    final until = goodUntil;
    return !d.isBefore(since) && (until == null || !d.isAfter(until));
  }

  /// Whether its date is behind [today]. It stays until somebody says it is
  /// gone: nothing clears itself.
  bool pastItsDate(DateTime today) {
    final until = goodUntil;
    return until != null && _dateOnly(today).isAfter(until);
  }

  @override
  String toString() =>
      'Leftover(${place.name}: $title, $portions, since $since, '
      'until $goodUntil${isStored ? ', stored' : ''})';
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

/// The household's leftovers on [today], fridge first, then freezer, oldest
/// first within each.
///
/// [weeks] are the cooked weeks to read, each with its derived [CookPlan]
/// ([leftoverWeekStarts] names them); a batch cooked more than
/// [kLeftoverHorizon] before [today] is left out. [stored] are the live
/// `leftover` rows, and [recipes] the live recipes they name, by id.
///
/// - A stored row with a `batch` replaces that batch's derived row, gone or
///   not. Two rows for one batch (two phones, offline) read as the newest.
/// - A row is shown until its `gone_at`, however far past its date.
/// - Each row's portions fall by the meals planned from it:
///   [plannedFromBatch] by batch key (`plan_entry.leftover_of`), and
///   [plannedFromRow] by stored row id (`plan_entry.from_leftover`). A row
///   with nothing left is not shown.
/// - A batch Cook was told about ([answers]: binned or eaten) reads as gone.
/// - [aheadFromBatch] and [aheadFromRow], keyed the same way, are the part of
///   those meals still to come (today or later): each row's [Leftover.planned].
List<Leftover> householdLeftovers({
  required List<({DateTime weekStart, CookPlan plan})> weeks,
  required DateTime today,
  List<StoredLeftover> stored = const [],
  Map<String, LeftoverRecipe> recipes = const {},
  Map<String, LeftoverAnswer> answers = const {},
  Map<String, double> plannedFromBatch = const {},
  Map<String, double> plannedFromRow = const {},
  Map<String, double> aheadFromBatch = const {},
  Map<String, double> aheadFromRow = const {},
}) {
  final day = _dateOnly(today);

  // One row per batch, the newest; every row added by hand stands alone. The
  // meals planned from a losing duplicate still come off the winner: it is
  // the same food.
  final byBatch = <String, List<StoredLeftover>>{};
  final rows = <(StoredLeftover, double, double)>[];
  for (final row in stored) {
    final batch = row.batch;
    if (batch == null) {
      rows.add((row, plannedFromRow[row.id] ?? 0, aheadFromRow[row.id] ?? 0));
    } else {
      (byBatch[batch] ??= []).add(row);
    }
  }
  for (final group in byBatch.values) {
    final newest = group.reduce(
      (a, b) =>
          b.updatedAt.isAfter(a.updatedAt) ||
              (b.updatedAt == a.updatedAt && b.id.compareTo(a.id) > 0)
          ? b
          : a,
    );
    final planned = group.fold<double>(
      0,
      (sum, r) => sum + (plannedFromRow[r.id] ?? 0),
    );
    final ahead = group.fold<double>(
      0,
      (sum, r) => sum + (aheadFromRow[r.id] ?? 0),
    );
    rows.add((newest, planned, ahead));
  }

  final horizon = DateTime(
    day.year,
    day.month,
    day.day - kLeftoverHorizon.inDays,
  );
  final derived = [
    for (final week in weeks)
      for (final left in batchLeftovers(
        week.plan,
        weekStart: week.weekStart,
        today: day,
        plannedFrom: plannedFromBatch,
      ))
        if (!byBatch.containsKey(left.key) &&
            !_answered(answers[left.key]) &&
            !left.cookDate.isBefore(horizon))
          Leftover(
            place: LeftoverPlace.fridge,
            batch: left.key,
            recipeId: left.recipeId,
            title: left.title,
            since: left.cookDate,
            goodUntil: left.useBy,
            portions: left.portions,
            planned: aheadFromBatch[left.key] ?? 0,
          ),
  ];

  final said = [
    for (final (row, planned, ahead) in rows)
      if (_storedLeftover(row, planned, ahead, recipes) case final left?) left,
  ];

  return [...derived, ...said]..sort((a, b) {
    final place = a.place.index.compareTo(b.place.index);
    if (place != 0) return place;
    final since = a.since.compareTo(b.since);
    return since != 0 ? since : a.title.compareTo(b.title);
  });
}

/// Whether Cook was told what became of a batch: binned or eaten. A `kept`
/// answer is an older kind and says nothing.
bool _answered(LeftoverAnswer? answer) =>
    answer != null && answer.binned + answer.eaten > 1e-9;

Leftover? _storedLeftover(
  StoredLeftover row,
  double planned,
  double ahead,
  Map<String, LeftoverRecipe> recipes,
) {
  if (row.goneAt != null) return null;
  final left = row.portions - planned;
  if (left <= 1e-9) return null;
  final since = _dateOnly(row.since);
  final recipeId = row.recipeId;
  final String title;
  final DateTime? goodUntil;
  if (recipeId == null) {
    // Words have no shelf life to read: only an age.
    title = row.label!;
    goodUntil = null;
  } else {
    // A recipe deleted since (or not yet synced) takes its row with it, as it
    // takes its batches out of the cook plan.
    final recipe = recipes[recipeId];
    if (recipe == null) return null;
    title = recipe.title;
    final days = switch (row.place) {
      LeftoverPlace.fridge => recipe.keepsForDays,
      LeftoverPlace.freezer => recipe.freezerDays,
    };
    goodUntil = days == null
        ? null
        : DateTime(since.year, since.month, since.day + days);
  }
  return Leftover(
    id: row.id,
    batch: row.batch,
    place: row.place,
    recipeId: recipeId,
    title: title,
    since: since,
    goodUntil: goodUntil,
    portions: left,
    planned: ahead,
  );
}

DateTime _dateOnly(DateTime d) => DateTime(d.year, d.month, d.day);
