/// Which day the household's week begins on, and what follows from it (pure
/// Dart).
///
/// A week is addressed by the date of its first day ([WeekShape.keyOf]) and a
/// meal's `day_of_week` is the offset from that key, never a calendar
/// weekday. Only this file indexes the weekday tables in `words.dart`; see
/// `test/structure/weekday_labels_go_through_the_shape_test.dart`.
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

  /// The default.
  static const monday = WeekShape(DateTime.monday);

  /// The other start the Account control offers.
  static const sunday = WeekShape(DateTime.sunday);

  /// ISO weekday the week begins on, 1=Mon … 7=Sun.
  final int startsOn;

  /// The first day (date-only, UTC) of the week containing [date].
  DateTime weekStartOf(DateTime date) {
    final d = DateTime.utc(date.year, date.month, date.day);
    return d.subtract(Duration(days: offsetOf(d)));
  }

  /// The key the week containing [date] is addressed by: its first day as
  /// `YYYY-MM-DD`. It is the `week_start_date` column and the `?week=` param.
  ///
  /// Must agree with the database's `week_key_for(date, starts_on)` for every
  /// date and start day; `week_shape_test.dart` holds that.
  String keyOf(DateTime date) => isoDateOf(weekStartOf(date));

  /// Where [date] sits in its own week, 0 to 6: the stored `day_of_week`.
  int offsetOf(DateTime date) => (date.weekday - startsOn + 7) % 7;

  /// The date of [offset] within the week beginning [weekStart].
  DateTime dateFor(DateTime weekStart, int offset) =>
      weekStart.add(Duration(days: offset));

  /// `Sun`, `Mon`, … for an [offset] within the week.
  String labelShort(int offset) => kWeekdayShort[_isoIndex(offset)];

  /// `Sunday`, `Monday`, … for an [offset] within the week.
  String labelFull(int offset) => kWeekdayFull[_isoIndex(offset)];

  /// The seven short labels in this week's own order.
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

/// A bare `YYYY-MM-DD` for [date]: the wire form of a week key and of any
/// date-only column.
String isoDateOf(DateTime date) {
  final mm = date.month.toString().padLeft(2, '0');
  final dd = date.day.toString().padLeft(2, '0');
  return '${date.year}-$mm-$dd';
}
