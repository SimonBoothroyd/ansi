/// Which day the household's week begins on, and everything that follows from
/// it — PURE DART.
///
/// A week is addressed by the **date of its own first day**
/// ([WeekShape.keyOf]), and a meal's `day_of_week` is the **offset from that
/// key**, never a calendar weekday. Those two facts are what make the shape a
/// value rather than a migration: `key + offset days` is the meal's real date
/// under any start day, so moving the start moves the address and leaves the
/// arithmetic alone.
///
/// This is the ONLY file that indexes the weekday tables in `words.dart`.
/// Indexing them anywhere else is indexing a Monday-first list with an offset
/// that may not count from Monday, which is the bug this type exists to make
/// unwritable; `test/structure/weekday_labels_go_through_the_shape_test.dart`
/// holds the rule.
library;

import 'package:meta/meta.dart';

import 'words.dart';

/// A household's week: the ISO weekday it starts on (1=Mon … 7=Sun, matching
/// [DateTime.weekday] and Postgres `isodow`), and the derivations that follow.
@immutable
class WeekShape {
  const WeekShape(this.startsOn)
    : assert(
        startsOn >= DateTime.monday && startsOn <= DateTime.sunday,
        'startsOn is an ISO weekday, 1=Mon..7=Sun',
      );

  /// The default, and what every household has until it says otherwise.
  static const monday = WeekShape(DateTime.monday);

  /// The other one the Account control offers — the household that shops and
  /// plans on a Sunday, so that Sunday's dinner is the week's first meal.
  static const sunday = WeekShape(DateTime.sunday);

  /// ISO weekday the week begins on, 1=Mon … 7=Sun.
  final int startsOn;

  /// The first day (date-only, UTC) of the week containing [date].
  DateTime weekStartOf(DateTime date) {
    final d = DateTime.utc(date.year, date.month, date.day);
    return d.subtract(Duration(days: offsetOf(d)));
  }

  /// The key the week containing [date] is ADDRESSED by — its first day as a
  /// bare ISO date, `YYYY-MM-DD`. It is the `week_start_date` column, the
  /// `?week=` param the recipe editor's week mode is opened with, and the
  /// string three repositories join on.
  ///
  /// **The exact twin of the database's `week_key_for(date, starts_on)`**,
  /// which the server's re-home uses to decide which week every meal lands in.
  /// Both are `date - ((isodow(date) - starts_on + 7) % 7)`, and Dart's
  /// [DateTime.weekday] is Postgres's `isodow`. They must agree for every date
  /// and every start day, or a flip would re-file meals under keys this app
  /// does not look them up by; `week_shape_test.dart` tabulates a fortnight
  /// across all seven start days to hold that.
  String keyOf(DateTime date) => isoDateOf(weekStartOf(date));

  /// Where [date] sits in its own week, 0 (the first day) to 6 (the last) —
  /// the `day_of_week` a meal planned on that date is stored under.
  int offsetOf(DateTime date) => (date.weekday - startsOn + 7) % 7;

  /// The date of [offset] within the week beginning [weekStart].
  DateTime dateFor(DateTime weekStart, int offset) =>
      weekStart.add(Duration(days: offset));

  /// `Sun`, `Mon`, … for an [offset] within the week.
  String labelShort(int offset) => kWeekdayShort[_isoIndex(offset)];

  /// `Sunday`, `Monday`, … for an [offset] within the week.
  String labelFull(int offset) => kWeekdayFull[_isoIndex(offset)];

  /// The seven short labels in this week's own order — for the data layer,
  /// which labels days without reaching up into presentation for a word.
  List<String> get shortLabels => [for (var i = 0; i < 7; i++) labelShort(i)];

  /// What the household calls its first day: `Sunday`, `Monday`, …
  String get startsOnName => labelFull(0);

  /// Offset 0..6 → index into the Monday-first tables.
  int _isoIndex(int offset) => (startsOn - 1 + offset) % 7;

  @override
  bool operator ==(Object other) =>
      other is WeekShape && other.startsOn == startsOn;

  @override
  int get hashCode => startsOn.hashCode;

  @override
  String toString() => 'WeekShape($startsOnName)';
}

/// A bare `YYYY-MM-DD` for [date] — the wire form of a week key and of any
/// date-only column. Snaps nothing: a caller that holds a week's first day
/// already holds the day the key names.
String isoDateOf(DateTime date) {
  final mm = date.month.toString().padLeft(2, '0');
  final dd = date.day.toString().padLeft(2, '0');
  return '${date.year}-$mm-$dd';
}
