import 'package:ansi/core/week_shape.dart';
import 'package:flutter_test/flutter_test.dart';

/// Sun 6 Sep 2026 … Sat 12 Sep 2026 — one calendar week to reason over, with
/// its Monday (7 Sep) and its Sunday (13 Sep) either side.
DateTime _d(int day) => DateTime.utc(2026, 9, day);

void main() {
  group('weekStartOf', () {
    test('Monday start: every day of Mon 7 – Sun 13 keys to Mon 7', () {
      for (var day = 7; day <= 13; day++) {
        expect(
          WeekShape.monday.weekStartOf(_d(day)),
          _d(7),
          reason: 'day $day',
        );
      }
    });

    test('Sunday start: Sun 13 begins its OWN week, not ends the last', () {
      expect(WeekShape.sunday.weekStartOf(_d(13)), _d(13));
      expect(WeekShape.sunday.weekStartOf(_d(12)), _d(6));
      for (var day = 13; day <= 19; day++) {
        expect(
          WeekShape.sunday.weekStartOf(_d(day)),
          _d(13),
          reason: 'day $day',
        );
      }
    });

    test('every start day resolves its own weekday to offset 0', () {
      for (
        var startsOn = DateTime.monday;
        startsOn <= DateTime.sunday;
        startsOn++
      ) {
        final shape = WeekShape(startsOn);
        for (var day = 1; day <= 30; day++) {
          final start = shape.weekStartOf(_d(day));
          expect(start.weekday, startsOn, reason: 'start=$startsOn day=$day');
          expect(shape.offsetOf(start), 0);
          // The week start is never after the date, and never more than six
          // days before it.
          final back = _d(day).difference(start).inDays;
          expect(back, inInclusiveRange(0, 6));
        }
      }
    });

    test('drops the time of day and answers in UTC', () {
      const shape = WeekShape.sunday;
      final start = shape.weekStartOf(DateTime(2026, 9, 16, 23, 45));
      expect(start, DateTime.utc(2026, 9, 13));
      expect(start.isUtc, isTrue);
    });
  });

  group('offsetOf / dateFor', () {
    test('Monday start puts Sunday last', () {
      expect(WeekShape.monday.offsetOf(_d(7)), 0);
      expect(WeekShape.monday.offsetOf(_d(13)), 6);
    });

    test('Sunday start puts Sunday first and Saturday last', () {
      expect(WeekShape.sunday.offsetOf(_d(13)), 0);
      expect(WeekShape.sunday.offsetOf(_d(19)), 6);
    });

    test('dateFor is offsetOf run backwards, for every start day', () {
      for (
        var startsOn = DateTime.monday;
        startsOn <= DateTime.sunday;
        startsOn++
      ) {
        final shape = WeekShape(startsOn);
        for (var day = 1; day <= 21; day++) {
          final date = _d(day);
          final start = shape.weekStartOf(date);
          expect(shape.dateFor(start, shape.offsetOf(date)), date);
        }
      }
    });
  });

  group('keyOf', () {
    test('is the week start as a bare ISO date', () {
      expect(WeekShape.monday.keyOf(_d(9)), '2026-09-07');
      expect(WeekShape.sunday.keyOf(_d(9)), '2026-09-06');
    });

    test('pads month and day', () {
      expect(WeekShape.monday.keyOf(DateTime.utc(2026, 1, 8)), '2026-01-05');
    });

    test('every household keys the same date to a start of its own day', () {
      for (
        var startsOn = DateTime.monday;
        startsOn <= DateTime.sunday;
        startsOn++
      ) {
        final key = WeekShape(startsOn).keyOf(_d(9));
        expect(DateTime.parse(key).weekday, startsOn);
      }
    });
  });

  group('labels', () {
    test('Monday start reads Mon..Sun', () {
      expect(WeekShape.monday.shortLabels, [
        'Mon',
        'Tue',
        'Wed',
        'Thu',
        'Fri',
        'Sat',
        'Sun',
      ]);
      expect(WeekShape.monday.labelFull(0), 'Monday');
      expect(WeekShape.monday.labelFull(6), 'Sunday');
    });

    test('Sunday start reads Sun..Sat', () {
      expect(WeekShape.sunday.shortLabels, [
        'Sun',
        'Mon',
        'Tue',
        'Wed',
        'Thu',
        'Fri',
        'Sat',
      ]);
      expect(WeekShape.sunday.labelFull(0), 'Sunday');
      expect(WeekShape.sunday.labelFull(6), 'Saturday');
    });

    test('a label always names the day the offset actually falls on', () {
      for (
        var startsOn = DateTime.monday;
        startsOn <= DateTime.sunday;
        startsOn++
      ) {
        final shape = WeekShape(startsOn);
        final start = shape.weekStartOf(_d(9));
        for (var offset = 0; offset < 7; offset++) {
          final date = shape.dateFor(start, offset);
          expect(
            shape.labelFull(offset),
            WeekShape.monday.labelFull(date.weekday - 1),
            reason: 'start=$startsOn offset=$offset',
          );
        }
      }
    });

    test('startsOnName is the first day', () {
      expect(WeekShape.monday.startsOnName, 'Monday');
      expect(WeekShape.sunday.startsOnName, 'Sunday');
      expect(const WeekShape(DateTime.wednesday).startsOnName, 'Wednesday');
    });
  });

  group('value semantics', () {
    test('two shapes with the same start day are equal', () {
      // Built from a stored column value, the way the repository builds it —
      // not the named constant, which would compare a thing to itself.
      // ignore: prefer_const_constructors
      final stored = WeekShape(DateTime.sunday);
      expect(stored, WeekShape.sunday);
      expect(stored.hashCode, WeekShape.sunday.hashCode);
      expect(WeekShape.monday == WeekShape.sunday, isFalse);
    });

    test('refuses a start day that is not an ISO weekday', () {
      expect(() => WeekShape(0), throwsA(isA<AssertionError>()));
      expect(() => WeekShape(8), throwsA(isA<AssertionError>()));
    });
  });

  group('isoDateOf', () {
    test('spells a date and snaps nothing', () {
      expect(isoDateOf(DateTime.utc(2026, 9, 9)), '2026-09-09');
      expect(isoDateOf(DateTime.utc(2026, 12, 31)), '2026-12-31');
    });
  });

  group("the database's week_key_for, tabulated", () {
    // A fortnight of dates against every start day, written out rather than
    // computed: the point is to pin the SAME answers the server's
    // `week_key_for(date, starts_on)` gives, so a table derived from the Dart
    // formula would prove nothing. Sun 6 Sep 2026 to Sat 19 Sep 2026, which
    // straddles two week boundaries under every shape — one `MM-DD` key per
    // day, all of them in 2026.
    const table = <int, String>{
      1:
          '08-31 09-07 09-07 09-07 09-07 09-07 09-07 '
          '09-07 09-14 09-14 09-14 09-14 09-14 09-14',
      2:
          '09-01 09-01 09-08 09-08 09-08 09-08 09-08 '
          '09-08 09-08 09-15 09-15 09-15 09-15 09-15',
      3:
          '09-02 09-02 09-02 09-09 09-09 09-09 09-09 '
          '09-09 09-09 09-09 09-16 09-16 09-16 09-16',
      4:
          '09-03 09-03 09-03 09-03 09-10 09-10 09-10 '
          '09-10 09-10 09-10 09-10 09-17 09-17 09-17',
      5:
          '09-04 09-04 09-04 09-04 09-04 09-11 09-11 '
          '09-11 09-11 09-11 09-11 09-11 09-18 09-18',
      6:
          '09-05 09-05 09-05 09-05 09-05 09-05 09-12 '
          '09-12 09-12 09-12 09-12 09-12 09-12 09-19',
      7:
          '09-06 09-06 09-06 09-06 09-06 09-06 09-06 '
          '09-13 09-13 09-13 09-13 09-13 09-13 09-13',
    };

    test('keyOf answers what week_key_for answers, for all seven', () {
      for (final MapEntry(key: startsOn, value: row) in table.entries) {
        final shape = WeekShape(startsOn);
        final keys = row.split(' ');
        for (var n = 0; n < keys.length; n++) {
          final date = DateTime.utc(2026, 9, 6).add(Duration(days: n));
          expect(
            shape.keyOf(date),
            '2026-${keys[n]}',
            reason: 'startsOn=$startsOn date=${isoDateOf(date)}',
          );
        }
      }
    });

    test('a key is its own key — the residue check the server runs', () {
      // `week_start_date = week_key_for(week_start_date, starts_on)` is how
      // the re-home asks "is this week at the right residue?", so the Dart
      // side has to be idempotent in exactly the same way.
      for (final MapEntry(key: startsOn, value: row) in table.entries) {
        final shape = WeekShape(startsOn);
        for (final key in row.split(' ').map((d) => '2026-$d').toSet()) {
          expect(shape.keyOf(DateTime.parse(key)), key);
        }
      }
    });
  });
}
