/// The words and ids a timer is known by outside its chip: the sheet's line
/// under the count, and the notification id that must name the same timer
/// across launches.
library;

import 'package:ansi/features/timers/data/local_timer_platform.dart';
import 'package:ansi/features/timers/domain/cook_timer.dart';
import 'package:ansi/features/timers/presentation/timer_sheet.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('notificationIdFor', () {
    test('is the same number every launch, clear of the ongoing one', () {
      // Pinned: a changed hash would orphan a scheduled ring across an update.
      expect(notificationIdFor('h1:s3:t0'), notificationIdFor('h1:s3:t0'));
      for (final id in ['a:s0:t0', 'h1:s3:t0', 'x' * 200]) {
        final n = notificationIdFor(id);
        expect(n, greaterThanOrEqualTo(1000));
        expect(n, lessThan(1 << 31));
      }
    });

    test('tells two chips of one step apart', () {
      expect(
        notificationIdFor('h1:s3:t0'),
        isNot(notificationIdFor('h1:s3:t1')),
      );
    });
  });

  group("the sheet's line", () {
    final t0 = DateTime(2026, 10, 8, 18, 25);
    CookTimer timer({int low = 1200, int high = 1500}) => CookTimer.start(
      recipeId: 'r',
      recipeTitle: 'R',
      step: 0,
      ordinal: 0,
      lowSeconds: low,
      highSeconds: high,
      now: t0,
    );

    test('a range says what it is the middle of, and when it rings', () {
      expect(
        timerSheetLine(timer(), t0),
        'of 22:30, the middle of 20–25 min · rings at 18:47',
      );
    });

    test('a single time, or a nudged range, says only its total', () {
      expect(
        timerSheetLine(timer(low: 600, high: 600), t0),
        startsWith('of 10:00 ·'),
      );
      expect(
        timerSheetLine(timer().adjust(kTimerNudge, t0), t0),
        'of 23:30 · rings at 18:48',
      );
    });

    test('paused, and rung', () {
      expect(timerSheetLine(timer().pause(t0), t0), startsWith('paused · '));
      final due = t0.add(const Duration(minutes: 30));
      expect(timerSheetLine(timer(), due), 'rang at 18:47');
    });
  });
}
