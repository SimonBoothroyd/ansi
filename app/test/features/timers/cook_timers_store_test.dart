/// The app's one set of timers ([CookTimers]), on a scripted clock.
library;

import 'package:ansi/features/timers/data/timer_providers.dart';
import 'package:ansi/features/timers/domain/cook_timer.dart';
import 'package:ansi/features/timers/domain/timer_platform.dart';
import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

import '../../helpers/fake_timer_platform.dart';

void main() {
  // [KeepScreenOn] registers an [AppLifecycleListener], which needs a binding.
  TestWidgetsFlutterBinding.ensureInitialized();

  final start = DateTime.utc(2026, 10, 8, 18, 25);

  ({
    ProviderContainer container,
    FakeTimerPlatform platform,
    MemoryCookTimerStore store,
  })
  scripted(
    FakeAsync async, {
    FakeTimerPlatform? platform,
    MemoryCookTimerStore? store,
  }) {
    final device = platform ?? FakeTimerPlatform();
    final kept = store ?? MemoryCookTimerStore();
    final container = ProviderContainer(
      overrides: timerOverrides(
        platform: device,
        store: kept,
        clock: () => start.add(async.elapsed),
      ),
    );
    addTearDown(container.dispose);
    // Keep the notifier alive and listened, as the shell does.
    container.listen(cookTimersProvider, (_, _) {});
    async.flushMicrotasks();
    return (container: container, platform: device, store: kept);
  }

  void startSimmer(ProviderContainer c, {int step = 3}) => c
      .read(cookTimersProvider.notifier)
      .start(
        recipeId: 'r1',
        recipeTitle: 'Harissa Chicken & Butter Beans',
        step: step,
        ordinal: 0,
        lowSeconds: 20 * 60,
        highSeconds: 25 * 60,
      );

  test('a start runs to the middle, is kept, scheduled and asks once', () {
    fakeAsync((async) {
      final (:container, :platform, :store) = scripted(async);
      startSimmer(container);
      async.flushMicrotasks();
      final timer = container.read(cookTimersProvider)['r1:s3:t0']!;
      expect(timer.endsAt, start.add(const Duration(minutes: 22, seconds: 30)));
      expect(store.timers, [timer]);
      expect(platform.synced, [timer]);
      expect(platform.asked, 1);
      // Starting a chip that already runs leaves it be.
      async.elapse(const Duration(minutes: 1));
      startSimmer(container);
      expect(container.read(cookTimersProvider)['r1:s3:t0'], timer);
      container.read(cookTimersProvider.notifier).stop('r1:s3:t0');
    });
  });

  test('the tick moves now; due buzzes once and chimes for a minute', () {
    fakeAsync((async) {
      final (:container, :platform, store: _) = scripted(async);
      startSimmer(container);
      async.elapse(const Duration(minutes: 10));
      expect(
        container.read(cookTimersProvider).now,
        start.add(const Duration(minutes: 10)),
      );
      expect(platform.buzzes, 0);

      async.elapse(const Duration(minutes: 12, seconds: 31));
      expect(container.read(cookTimersProvider).due.single.id, 'r1:s3:t0');
      expect(platform.buzzes, 1);
      expect(platform.chiming, isTrue);
      expect(platform.chimes, 1);

      // Silent after a minute, still due.
      async.elapse(const Duration(minutes: 1));
      expect(platform.chiming, isFalse);
      expect(platform.buzzes, 1);
      expect(container.read(cookTimersProvider).due, isNotEmpty);

      container.read(cookTimersProvider.notifier).stop('r1:s3:t0');
      expect(container.read(cookTimersProvider).isEmpty, isTrue);
      expect(platform.synced, isEmpty);
    });
  });

  test('where the device rings itself, the app does not chime over it', () {
    fakeAsync((async) {
      final (:container, :platform, store: _) = scripted(
        async,
        platform: FakeTimerPlatform(ringsItself: true),
      );
      startSimmer(container);
      async.elapse(const Duration(minutes: 23));
      expect(platform.buzzes, 1);
      expect(platform.chimes, 0);
      container.read(cookTimersProvider.notifier).stop('r1:s3:t0');
    });
  });

  test('stopping a ringing timer hushes the chime', () {
    fakeAsync((async) {
      final (:container, :platform, store: _) = scripted(async);
      startSimmer(container);
      async.elapse(const Duration(minutes: 22, seconds: 40));
      expect(platform.chiming, isTrue);
      container.read(cookTimersProvider.notifier).stop('r1:s3:t0');
      expect(platform.chiming, isFalse);
    });
  });

  test('timers come back from the store after a relaunch', () {
    fakeAsync((async) {
      final kept = CookTimer.start(
        recipeId: 'r1',
        recipeTitle: 'Harissa',
        step: 1,
        ordinal: 0,
        lowSeconds: 600,
        highSeconds: 600,
        now: start.subtract(const Duration(minutes: 4)),
      );
      final (:container, :platform, store: _) = scripted(
        async,
        store: MemoryCookTimerStore([kept]),
      );
      final state = container.read(cookTimersProvider);
      expect(state[kept.id], kept);
      expect(formatTimerClock(kept.left(state.now)), '6:00');
      expect(platform.synced, [kept]);
      container.read(cookTimersProvider.notifier).stop(kept.id);
    });
  });

  test("a notification's Stop, +1 min and tap reach the timers", () {
    fakeAsync((async) {
      final (:container, :platform, store: _) = scripted(async);
      startSimmer(container);
      const id = 'r1:s3:t0';
      final before = container.read(cookTimersProvider)[id]!.endsAt!;
      platform.onAction!(const TimerAction(TimerActionKind.addMinute, id));
      expect(
        container.read(cookTimersProvider)[id]!.endsAt,
        before.add(kTimerNudge),
      );
      platform.onAction!(const TimerAction(TimerActionKind.open, id));
      expect(container.read(timerOpenRequestProvider)?.id, id);
      platform.onAction!(const TimerAction(TimerActionKind.stop, id));
      expect(container.read(cookTimersProvider).isEmpty, isTrue);
    });
  });

  test('on the web a start keeps the screen on', () {
    fakeAsync((async) {
      final (:container, :platform, store: _) = scripted(
        async,
        platform: FakeTimerPlatform(isWeb: true),
      );
      startSimmer(container);
      expect(container.read(keepScreenOnProvider), isTrue);
      expect(platform.awake, isTrue);
      container.read(cookTimersProvider.notifier).stop('r1:s3:t0');
    });
  });
}
