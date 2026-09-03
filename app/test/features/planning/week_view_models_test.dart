/// [Today] and [currentWeekStart] across a midnight, on a scripted clock.
///
/// The clock is `start + fakeAsync.elapsed`, so advancing fake time IS the
/// clock moving; the expected waits are computed from the machine's own local
/// midnight rather than hardcoded, which keeps the test honest in any zone
/// (including one whose DST shifts on the test dates).
library;

import 'package:ansi/features/planning/domain/planning.dart';
import 'package:ansi/features/planning/presentation/week_view_models.dart';
import 'package:fake_async/fake_async.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

void main() {
  // [Today] registers an [AppLifecycleListener], which needs a binding.
  TestWidgetsFlutterBinding.ensureInitialized();

  /// A container whose clock reads [start] plus whatever [async] has elapsed.
  ProviderContainer scripted(FakeAsync async, DateTime start) {
    final container = ProviderContainer(
      overrides: [
        clockProvider.overrideWithValue(() => start.add(async.elapsed)),
      ],
    );
    addTearDown(container.dispose);
    return container;
  }

  /// The machine-local midnight that ends the day containing [at].
  DateTime midnightAfter(DateTime at) =>
      DateTime(at.year, at.month, at.day + 1);

  group('Today', () {
    test('re-fires at the next local midnight, and not a second before', () {
      fakeAsync((async) {
        final start = DateTime(2026, 9, 2, 22); // Wednesday
        final midnight = midnightAfter(start);
        final container = scripted(async, start);
        final fired = <DateTime>[];
        container.listen(todayProvider, (_, next) => fired.add(next));

        expect(container.read(todayProvider), DateTime(2026, 9, 2));

        async.elapse(midnight.difference(start) - const Duration(seconds: 1));
        expect(fired, isEmpty);
        expect(container.read(todayProvider), DateTime(2026, 9, 2));

        async.elapse(const Duration(seconds: 1));
        expect(fired, [DateTime(2026, 9, 3)]);
        expect(container.read(todayProvider), DateTime(2026, 9, 3));
      });
    });

    test('re-arms itself for the midnight after that', () {
      fakeAsync((async) {
        final start = DateTime(2026, 9, 2, 23, 30);
        final container = scripted(async, start);
        final fired = <DateTime>[];
        container.listen(todayProvider, (_, next) => fired.add(next));

        final first = midnightAfter(start);
        final second = midnightAfter(first);
        async.elapse(second.difference(start) - const Duration(minutes: 1));
        expect(fired, [DateTime(2026, 9, 3)]);

        async.elapse(const Duration(minutes: 1));
        expect(fired, [DateTime(2026, 9, 3), DateTime(2026, 9, 4)]);
      });
    });

    test('holds exactly one timer, cancelled when the container goes', () {
      fakeAsync((async) {
        final start = DateTime(2026, 9, 2, 12);
        final container = ProviderContainer(
          overrides: [
            clockProvider.overrideWithValue(() => start.add(async.elapsed)),
          ],
        )..read(todayProvider);
        expect(async.pendingTimers, hasLength(1));

        container.dispose();
        expect(async.pendingTimers, isEmpty);
      });
    });

    test(
      'catches up on resume when the phone slept through midnight',
      () async {
        // A clock the test moves by hand: no timer fires, only the lifecycle.
        var now = DateTime(2026, 9, 2, 23);
        final container = ProviderContainer(
          overrides: [clockProvider.overrideWithValue(() => now)],
        );
        addTearDown(container.dispose);
        final fired = <DateTime>[];
        container.listen(todayProvider, (_, next) => fired.add(next));
        expect(container.read(todayProvider), DateTime(2026, 9, 2));

        now = DateTime(2026, 9, 5, 9);
        await _setLifecycle(AppLifecycleState.inactive);
        await _setLifecycle(AppLifecycleState.resumed);

        expect(fired, [DateTime(2026, 9, 5)]);
        expect(container.read(todayProvider), DateTime(2026, 9, 5));
      },
    );

    test('a resume on the same day is silent', () async {
      var now = DateTime(2026, 9, 2, 9);
      final container = ProviderContainer(
        overrides: [clockProvider.overrideWithValue(() => now)],
      );
      addTearDown(container.dispose);
      final fired = <DateTime>[];
      container.listen(todayProvider, (_, next) => fired.add(next));
      expect(container.read(todayProvider), DateTime(2026, 9, 2));

      now = DateTime(2026, 9, 2, 15);
      await _setLifecycle(AppLifecycleState.inactive);
      await _setLifecycle(AppLifecycleState.resumed);

      expect(fired, isEmpty);
    });
  });

  group('currentWeekStart', () {
    test('moves to the next Monday across a Sunday midnight', () {
      fakeAsync((async) {
        final start = DateTime(2026, 9, 6, 23, 59); // Sunday
        final container = scripted(async, start);
        final fired = <DateTime>[];
        container.listen(
          currentWeekStartProvider,
          (_, next) => fired.add(next),
        );

        expect(container.read(currentWeekStartProvider), mondayOf(start));
        expect(mondayOf(start), DateTime.utc(2026, 8, 31));

        async.elapse(midnightAfter(start).difference(start));
        expect(fired, [DateTime.utc(2026, 9, 7)]);
        expect(
          container.read(currentWeekStartProvider),
          DateTime.utc(2026, 9, 7),
        );
      });
    });

    test('is quiet across a mid-week midnight — the Monday has not moved', () {
      fakeAsync((async) {
        final start = DateTime(2026, 9, 2, 23, 59); // Wednesday
        final container = scripted(async, start);
        final fired = <DateTime>[];
        container.listen(
          currentWeekStartProvider,
          (_, next) => fired.add(next),
        );
        expect(
          container.read(currentWeekStartProvider),
          DateTime.utc(2026, 8, 31),
        );

        async.elapse(midnightAfter(start).difference(start));
        expect(container.read(todayProvider), DateTime(2026, 9, 3));
        expect(fired, isEmpty);
        expect(
          container.read(currentWeekStartProvider),
          DateTime.utc(2026, 8, 31),
        );
      });
    });

    test('does not move the viewed week', () {
      fakeAsync((async) {
        final start = DateTime(2026, 9, 6, 23, 59); // Sunday
        final container = scripted(async, start);
        final viewedBefore = container.read(viewedWeekStartProvider);

        async.elapse(midnightAfter(start).difference(start));
        expect(
          container.read(currentWeekStartProvider),
          DateTime.utc(2026, 9, 7),
        );
        expect(container.read(viewedWeekStartProvider), viewedBefore);
      });
    });
  });
}

/// Drives the binding's lifecycle the way the platform does, over the
/// `flutter/lifecycle` channel; the handler itself is `@protected`.
Future<void> _setLifecycle(AppLifecycleState state) {
  return TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .handlePlatformMessage(
        'flutter/lifecycle',
        const StringCodec().encodeMessage(state.toString()),
        (_) {},
      );
}
