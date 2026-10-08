// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'timer_providers.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning
/// The device: notifications, chime, haptics, wake lock.

@ProviderFor(timerPlatform)
const timerPlatformProvider = TimerPlatformProvider._();

/// The device: notifications, chime, haptics, wake lock.

final class TimerPlatformProvider
    extends $FunctionalProvider<TimerPlatform, TimerPlatform, TimerPlatform>
    with $Provider<TimerPlatform> {
  /// The device: notifications, chime, haptics, wake lock.
  const TimerPlatformProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'timerPlatformProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$timerPlatformHash();

  @$internal
  @override
  $ProviderElement<TimerPlatform> $createElement($ProviderPointer pointer) =>
      $ProviderElement(pointer);

  @override
  TimerPlatform create(Ref ref) {
    return timerPlatform(ref);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(TimerPlatform value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<TimerPlatform>(value),
    );
  }
}

String _$timerPlatformHash() => r'bd54c082e2fa0861aafca5dc1df814c897ef0541';

/// Where the timers survive a killed app.

@ProviderFor(cookTimerStore)
const cookTimerStoreProvider = CookTimerStoreProvider._();

/// Where the timers survive a killed app.

final class CookTimerStoreProvider
    extends $FunctionalProvider<CookTimerStore, CookTimerStore, CookTimerStore>
    with $Provider<CookTimerStore> {
  /// Where the timers survive a killed app.
  const CookTimerStoreProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'cookTimerStoreProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$cookTimerStoreHash();

  @$internal
  @override
  $ProviderElement<CookTimerStore> $createElement($ProviderPointer pointer) =>
      $ProviderElement(pointer);

  @override
  CookTimerStore create(Ref ref) {
    return cookTimerStore(ref);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(CookTimerStore value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<CookTimerStore>(value),
    );
  }
}

String _$cookTimerStoreHash() => r'dfc3bbbade182ed670b635b9d5c199148260a928';

/// What time it is. Tests pin it.

@ProviderFor(timerClock)
const timerClockProvider = TimerClockProvider._();

/// What time it is. Tests pin it.

final class TimerClockProvider
    extends
        $FunctionalProvider<
          DateTime Function(),
          DateTime Function(),
          DateTime Function()
        >
    with $Provider<DateTime Function()> {
  /// What time it is. Tests pin it.
  const TimerClockProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'timerClockProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$timerClockHash();

  @$internal
  @override
  $ProviderElement<DateTime Function()> $createElement(
    $ProviderPointer pointer,
  ) => $ProviderElement(pointer);

  @override
  DateTime Function() create(Ref ref) {
    return timerClock(ref);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(DateTime Function() value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<DateTime Function()>(value),
    );
  }
}

String _$timerClockHash() => r'9e9c9604e382917f9636d71910f8bff2d7fc9557';

/// A request to open a timer's step, from its notification. The shell
/// navigates and clears it.

@ProviderFor(TimerOpenRequest)
const timerOpenRequestProvider = TimerOpenRequestProvider._();

/// A request to open a timer's step, from its notification. The shell
/// navigates and clears it.
final class TimerOpenRequestProvider
    extends $NotifierProvider<TimerOpenRequest, CookTimer?> {
  /// A request to open a timer's step, from its notification. The shell
  /// navigates and clears it.
  const TimerOpenRequestProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'timerOpenRequestProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$timerOpenRequestHash();

  @$internal
  @override
  TimerOpenRequest create() => TimerOpenRequest();

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(CookTimer? value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<CookTimer?>(value),
    );
  }
}

String _$timerOpenRequestHash() => r'e683c3d484242ef6399470cbd1850c54f8cb3a8c';

/// A request to open a timer's step, from its notification. The shell
/// navigates and clears it.

abstract class _$TimerOpenRequest extends $Notifier<CookTimer?> {
  CookTimer? build();
  @$mustCallSuper
  @override
  void runBuild() {
    final created = build();
    final ref = this.ref as $Ref<CookTimer?, CookTimer?>;
    final element =
        ref.element
            as $ClassProviderElement<
              AnyNotifier<CookTimer?, CookTimer?>,
              CookTimer?,
              Object?,
              Object?
            >;
    element.handleValue(ref, created);
  }
}

@ProviderFor(MethodStepFocus)
const methodStepFocusProvider = MethodStepFocusProvider._();

final class MethodStepFocusProvider
    extends $NotifierProvider<MethodStepFocus, StepFocus?> {
  const MethodStepFocusProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'methodStepFocusProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$methodStepFocusHash();

  @$internal
  @override
  MethodStepFocus create() => MethodStepFocus();

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(StepFocus? value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<StepFocus?>(value),
    );
  }
}

String _$methodStepFocusHash() => r'aa87909452c7a0d04787cdfba8f3987a855f023f';

abstract class _$MethodStepFocus extends $Notifier<StepFocus?> {
  StepFocus? build();
  @$mustCallSuper
  @override
  void runBuild() {
    final created = build();
    final ref = this.ref as $Ref<StepFocus?, StepFocus?>;
    final element =
        ref.element
            as $ClassProviderElement<
              AnyNotifier<StepFocus?, StepFocus?>,
              StepFocus?,
              Object?,
              Object?
            >;
    element.handleValue(ref, created);
  }
}

/// Whether the dock says the web's one limit — a closed tab cannot ring.
/// Said the first time a timer starts in this browser, and not again.

@ProviderFor(WebTabNote)
const webTabNoteProvider = WebTabNoteProvider._();

/// Whether the dock says the web's one limit — a closed tab cannot ring.
/// Said the first time a timer starts in this browser, and not again.
final class WebTabNoteProvider extends $NotifierProvider<WebTabNote, bool> {
  /// Whether the dock says the web's one limit — a closed tab cannot ring.
  /// Said the first time a timer starts in this browser, and not again.
  const WebTabNoteProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'webTabNoteProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$webTabNoteHash();

  @$internal
  @override
  WebTabNote create() => WebTabNote();

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(bool value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<bool>(value),
    );
  }
}

String _$webTabNoteHash() => r'd0dab379779e860d2f7b8a6d855ae8ec786ada7e';

/// Whether the dock says the web's one limit — a closed tab cannot ring.
/// Said the first time a timer starts in this browser, and not again.

abstract class _$WebTabNote extends $Notifier<bool> {
  bool build();
  @$mustCallSuper
  @override
  void runBuild() {
    final created = build();
    final ref = this.ref as $Ref<bool, bool>;
    final element =
        ref.element
            as $ClassProviderElement<
              AnyNotifier<bool, bool>,
              bool,
              Object?,
              Object?
            >;
    element.handleValue(ref, created);
  }
}

@ProviderFor(CookTimers)
const cookTimersProvider = CookTimersProvider._();

final class CookTimersProvider
    extends $NotifierProvider<CookTimers, CookTimersState> {
  const CookTimersProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'cookTimersProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$cookTimersHash();

  @$internal
  @override
  CookTimers create() => CookTimers();

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(CookTimersState value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<CookTimersState>(value),
    );
  }
}

String _$cookTimersHash() => r'0c5a1ae441a763dc10b87217300afb7936d122b4';

abstract class _$CookTimers extends $Notifier<CookTimersState> {
  CookTimersState build();
  @$mustCallSuper
  @override
  void runBuild() {
    final created = build();
    final ref = this.ref as $Ref<CookTimersState, CookTimersState>;
    final element =
        ref.element
            as $ClassProviderElement<
              AnyNotifier<CookTimersState, CookTimersState>,
              CookTimersState,
              Object?,
              Object?
            >;
    element.handleValue(ref, created);
  }
}

/// What the cook has ticked off in each recipe's method: positional keys,
/// `s2` for a step and `s2:c0` for its first chip.
///
/// Never stored, never synced. A recipe's ticks are dropped when its page
/// closes, unless one of its timers is still held; then they wait for that
/// timer, so coming back through the dock finds the page as it was left.

@ProviderFor(MethodTicks)
const methodTicksProvider = MethodTicksProvider._();

/// What the cook has ticked off in each recipe's method: positional keys,
/// `s2` for a step and `s2:c0` for its first chip.
///
/// Never stored, never synced. A recipe's ticks are dropped when its page
/// closes, unless one of its timers is still held; then they wait for that
/// timer, so coming back through the dock finds the page as it was left.
final class MethodTicksProvider
    extends $NotifierProvider<MethodTicks, Map<String, Set<String>>> {
  /// What the cook has ticked off in each recipe's method: positional keys,
  /// `s2` for a step and `s2:c0` for its first chip.
  ///
  /// Never stored, never synced. A recipe's ticks are dropped when its page
  /// closes, unless one of its timers is still held; then they wait for that
  /// timer, so coming back through the dock finds the page as it was left.
  const MethodTicksProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'methodTicksProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$methodTicksHash();

  @$internal
  @override
  MethodTicks create() => MethodTicks();

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(Map<String, Set<String>> value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<Map<String, Set<String>>>(value),
    );
  }
}

String _$methodTicksHash() => r'17b25d3f1af10a35e524c3137c1e47525d77eae0';

/// What the cook has ticked off in each recipe's method: positional keys,
/// `s2` for a step and `s2:c0` for its first chip.
///
/// Never stored, never synced. A recipe's ticks are dropped when its page
/// closes, unless one of its timers is still held; then they wait for that
/// timer, so coming back through the dock finds the page as it was left.

abstract class _$MethodTicks extends $Notifier<Map<String, Set<String>>> {
  Map<String, Set<String>> build();
  @$mustCallSuper
  @override
  void runBuild() {
    final created = build();
    final ref =
        this.ref as $Ref<Map<String, Set<String>>, Map<String, Set<String>>>;
    final element =
        ref.element
            as $ClassProviderElement<
              AnyNotifier<Map<String, Set<String>>, Map<String, Set<String>>>,
              Map<String, Set<String>>,
              Object?,
              Object?
            >;
    element.handleValue(ref, created);
  }
}

/// Keep screen on: a posture held for the session, across recipes, until it
/// is turned off or the app closes. On the web a timer's start holds it too.

@ProviderFor(KeepScreenOn)
const keepScreenOnProvider = KeepScreenOnProvider._();

/// Keep screen on: a posture held for the session, across recipes, until it
/// is turned off or the app closes. On the web a timer's start holds it too.
final class KeepScreenOnProvider extends $NotifierProvider<KeepScreenOn, bool> {
  /// Keep screen on: a posture held for the session, across recipes, until it
  /// is turned off or the app closes. On the web a timer's start holds it too.
  const KeepScreenOnProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'keepScreenOnProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$keepScreenOnHash();

  @$internal
  @override
  KeepScreenOn create() => KeepScreenOn();

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(bool value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<bool>(value),
    );
  }
}

String _$keepScreenOnHash() => r'd33e89e0e6a3e4cfbd972ce2bf76a5ff98c34dd4';

/// Keep screen on: a posture held for the session, across recipes, until it
/// is turned off or the app closes. On the web a timer's start holds it too.

abstract class _$KeepScreenOn extends $Notifier<bool> {
  bool build();
  @$mustCallSuper
  @override
  void runBuild() {
    final created = build();
    final ref = this.ref as $Ref<bool, bool>;
    final element =
        ref.element
            as $ClassProviderElement<
              AnyNotifier<bool, bool>,
              bool,
              Object?,
              Object?
            >;
    element.handleValue(ref, created);
  }
}
