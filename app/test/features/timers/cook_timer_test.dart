import 'package:ansi/features/timers/domain/cook_timer.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final t0 = DateTime.utc(2026, 10, 8, 18, 25);

  CookTimer simmer({DateTime? at}) => CookTimer.start(
    recipeId: 'r1',
    recipeTitle: 'Harissa Chicken & Butter Beans',
    step: 3,
    ordinal: 0,
    lowSeconds: 20 * 60,
    highSeconds: 25 * 60,
    now: at ?? t0,
  );

  group('start', () {
    test('a range runs to its middle', () {
      final t = simmer();
      expect(t.total, const Duration(minutes: 22, seconds: 30));
      expect(t.endsAt, t0.add(const Duration(minutes: 22, seconds: 30)));
      expect(formatTimerClock(t.left(t0)), '22:30');
    });

    test('a single time runs to itself', () {
      expect(midpointSeconds(600, 600), 600);
    });

    test('one id per chip', () {
      expect(simmer().id, 'r1:s3:t0');
    });
  });

  group('state', () {
    test('runs, then is due, and rings for a minute only', () {
      final t = simmer();
      expect(t.stateAt(t0), CookTimerState.running);
      final due = t.endsAt!;
      expect(t.stateAt(due), CookTimerState.due);
      expect(t.ringingAt(due), isTrue);
      expect(t.ringingAt(due.add(const Duration(seconds: 59))), isTrue);
      expect(t.ringingAt(due.add(const Duration(minutes: 1))), isFalse);
      // Silent is not stopped: still due, still counting.
      final later = due.add(const Duration(minutes: 3));
      expect(t.stateAt(later), CookTimerState.due);
      expect(formatTimerClock(t.left(later)), '+3:00');
    });

    test('the wash drains from 1 to 0', () {
      final t = simmer();
      expect(t.remainingShare(t0), 1);
      expect(
        t.remainingShare(t0.add(const Duration(minutes: 11, seconds: 15))),
        closeTo(.5, 1e-9),
      );
      expect(t.remainingShare(t.endsAt!.add(const Duration(hours: 1))), 0);
    });
  });

  group('pause', () {
    test('holds what was left, across any wait', () {
      final at = t0.add(const Duration(minutes: 10));
      final p = simmer().pause(at);
      expect(p.paused, isTrue);
      expect(
        p.stateAt(at.add(const Duration(hours: 2))),
        CookTimerState.paused,
      );
      expect(
        formatTimerClock(p.left(at.add(const Duration(hours: 2)))),
        '12:30',
      );
    });

    test('resume counts on from what was left', () {
      final at = t0.add(const Duration(minutes: 10));
      final later = at.add(const Duration(minutes: 30));
      final r = simmer().pause(at).resume(later);
      expect(r.endsAt, later.add(const Duration(minutes: 12, seconds: 30)));
    });

    test('a due timer is not paused', () {
      final t = simmer();
      final after = t.endsAt!.add(const Duration(seconds: 5));
      expect(t.pause(after), same(t));
    });
  });

  group('adjust', () {
    test('a minute either way moves the end and the total', () {
      final t = simmer();
      final plus = t.adjust(kTimerNudge, t0);
      expect(plus.endsAt, t.endsAt!.add(kTimerNudge));
      expect(plus.total, const Duration(minutes: 23, seconds: 30));
      final minus = t.adjust(-kTimerNudge, t0);
      expect(minus.total, const Duration(minutes: 21, seconds: 30));
    });

    test('taking off more than is left makes it due, never negative', () {
      final at = simmer().endsAt!.subtract(const Duration(seconds: 30));
      final minus = simmer().adjust(-kTimerNudge, at);
      expect(minus.stateAt(at), CookTimerState.due);
      expect(minus.left(at), Duration.zero);
    });

    test('a due timer given a minute runs a fresh minute', () {
      final over = simmer().endsAt!.add(const Duration(seconds: 42));
      final plus = simmer().adjust(kTimerNudge, over);
      expect(plus.stateAt(over), CookTimerState.running);
      expect(plus.left(over), kTimerNudge);
      expect(plus.total, kTimerNudge);
      expect(plus.remainingShare(over), 1);
    });

    test('a paused timer stays paused', () {
      final at = t0.add(const Duration(minutes: 10));
      final p = simmer().pause(at).adjust(kTimerNudge, at);
      expect(p.paused, isTrue);
      expect(p.left(at), const Duration(minutes: 13, seconds: 30));
    });
  });

  test('json round-trips, running and paused', () {
    final running = simmer();
    expect(CookTimer.fromJson(running.toJson()), running);
    final paused = running.pause(t0.add(const Duration(minutes: 1)));
    expect(CookTimer.fromJson(paused.toJson()), paused);
  });

  test('the dock lists what needs you first', () {
    CookTimer at(int step, int minutes) => CookTimer.start(
      recipeId: 'r',
      recipeTitle: 'R',
      step: step,
      ordinal: 0,
      lowSeconds: minutes * 60,
      highSeconds: minutes * 60,
      now: t0,
    );
    final now = t0.add(const Duration(minutes: 5));
    final due = at(0, 2);
    final dueLonger = at(1, 1);
    final soon = at(2, 6);
    final later = at(3, 30);
    final paused = at(4, 3).pause(t0);
    expect(
      dockOrder([later, paused, soon, due, dueLonger], now).map((t) => t.step),
      [1, 0, 2, 3, 4],
    );
  });

  group('the clock', () {
    test('minutes, hours, and overtime', () {
      expect(formatTimerClock(const Duration(minutes: 4, seconds: 5)), '4:05');
      expect(
        formatTimerClock(const Duration(hours: 1, minutes: 12)),
        '1:12:00',
      );
      expect(formatTimerClock(const Duration(seconds: -42)), '+0:42');
    });

    test('reads 0:01 until it is due, never 0:00 early', () {
      expect(formatTimerClock(const Duration(milliseconds: 400)), '0:01');
      expect(formatTimerClock(Duration.zero), '0:00');
    });
  });
}
