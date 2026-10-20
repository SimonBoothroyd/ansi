// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'ask_controller.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning
/// The clock the thread's idle rule reads. Tests pin it.

@ProviderFor(askClock)
const askClockProvider = AskClockProvider._();

/// The clock the thread's idle rule reads. Tests pin it.

final class AskClockProvider
    extends
        $FunctionalProvider<
          DateTime Function(),
          DateTime Function(),
          DateTime Function()
        >
    with $Provider<DateTime Function()> {
  /// The clock the thread's idle rule reads. Tests pin it.
  const AskClockProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'askClockProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$askClockHash();

  @$internal
  @override
  $ProviderElement<DateTime Function()> $createElement(
    $ProviderPointer pointer,
  ) => $ProviderElement(pointer);

  @override
  DateTime Function() create(Ref ref) {
    return askClock(ref);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(DateTime Function() value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<DateTime Function()>(value),
    );
  }
}

String _$askClockHash() => r'bdfab3d2fb9b623b5f9755a4199d343846b10cf8';

@ProviderFor(AskController)
const askControllerProvider = AskControllerProvider._();

final class AskControllerProvider
    extends $NotifierProvider<AskController, AskState> {
  const AskControllerProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'askControllerProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$askControllerHash();

  @$internal
  @override
  AskController create() => AskController();

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(AskState value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<AskState>(value),
    );
  }
}

String _$askControllerHash() => r'fd81eb96c263f37518be4000a7cf18e2e7a656c5';

abstract class _$AskController extends $Notifier<AskState> {
  AskState build();
  @$mustCallSuper
  @override
  void runBuild() {
    final created = build();
    final ref = this.ref as $Ref<AskState, AskState>;
    final element =
        ref.element
            as $ClassProviderElement<
              AnyNotifier<AskState, AskState>,
              AskState,
              Object?,
              Object?
            >;
    element.handleValue(ref, created);
  }
}
