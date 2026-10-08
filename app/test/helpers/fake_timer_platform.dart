import 'package:ansi/features/timers/data/timer_providers.dart';
import 'package:ansi/features/timers/domain/cook_timer.dart';
import 'package:ansi/features/timers/domain/timer_platform.dart';
// Riverpod 3 exposes the `Override` type via the misc.dart barrel.
import 'package:hooks_riverpod/misc.dart' show Override;

/// A [TimerPlatform] that records what it was asked, for tests.
class FakeTimerPlatform implements TimerPlatform {
  FakeTimerPlatform({this.isWeb = false, this.ringsItself = false});

  @override
  final bool isWeb;

  @override
  bool ringsItself;

  void Function(TimerAction action)? onAction;
  int asked = 0;
  int buzzes = 0;
  int chimes = 0;
  int hushes = 0;
  bool chiming = false;
  bool? awake;
  final announced = <String>[];

  /// What the last [sync] was handed.
  List<CookTimer> synced = const [];

  @override
  Future<void> init({
    required void Function(TimerAction action) onAction,
  }) async => this.onAction = onAction;

  @override
  Future<void> askOnce() async => asked++;

  @override
  Future<void> sync(List<CookTimer> timers, DateTime now) async =>
      synced = timers;

  @override
  Future<void> announceDue(CookTimer timer) async => announced.add(timer.id);

  @override
  Future<void> chime() async {
    chimes++;
    chiming = true;
  }

  @override
  Future<void> hush() async {
    hushes++;
    chiming = false;
  }

  @override
  Future<void> buzz() async => buzzes++;

  @override
  Future<void> keepAwake({required bool on}) async => awake = on;
}

/// A [CookTimerStore] in memory.
class MemoryCookTimerStore implements CookTimerStore {
  MemoryCookTimerStore([List<CookTimer> initial = const []])
    : timers = [...initial];

  List<CookTimer> timers;

  @override
  Future<List<CookTimer>> read() async => [...timers];

  @override
  Future<void> write(List<CookTimer> timers) async => this.timers = [...timers];
}

/// The overrides a screen with timers on it needs: the fakes above, and a
/// clock the test owns.
List<Override> timerOverrides({
  required FakeTimerPlatform platform,
  MemoryCookTimerStore? store,
  DateTime Function()? clock,
}) => [
  timerPlatformProvider.overrideWithValue(platform),
  cookTimerStoreProvider.overrideWithValue(store ?? MemoryCookTimerStore()),
  if (clock != null) timerClockProvider.overrideWithValue(clock),
];
