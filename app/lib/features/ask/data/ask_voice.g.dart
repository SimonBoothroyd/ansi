// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'ask_voice.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning

@ProviderFor(askVoice)
const askVoiceProvider = AskVoiceProvider._();

final class AskVoiceProvider
    extends $FunctionalProvider<AskVoice, AskVoice, AskVoice>
    with $Provider<AskVoice> {
  const AskVoiceProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'askVoiceProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$askVoiceHash();

  @$internal
  @override
  $ProviderElement<AskVoice> $createElement($ProviderPointer pointer) =>
      $ProviderElement(pointer);

  @override
  AskVoice create(Ref ref) {
    return askVoice(ref);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(AskVoice value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<AskVoice>(value),
    );
  }
}

String _$askVoiceHash() => r'c2bbd93108c2fb1f027f9f823c2ca839cd02f336';

/// The read-aloud setting for this run of the app.

@ProviderFor(AskReadAloudSetting)
const askReadAloudSettingProvider = AskReadAloudSettingProvider._();

/// The read-aloud setting for this run of the app.
final class AskReadAloudSettingProvider
    extends $NotifierProvider<AskReadAloudSetting, AskReadAloud> {
  /// The read-aloud setting for this run of the app.
  const AskReadAloudSettingProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'askReadAloudSettingProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$askReadAloudSettingHash();

  @$internal
  @override
  AskReadAloudSetting create() => AskReadAloudSetting();

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(AskReadAloud value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<AskReadAloud>(value),
    );
  }
}

String _$askReadAloudSettingHash() =>
    r'c657ef9659067ca9bff949886f2d9fd0a5ab5a93';

/// The read-aloud setting for this run of the app.

abstract class _$AskReadAloudSetting extends $Notifier<AskReadAloud> {
  AskReadAloud build();
  @$mustCallSuper
  @override
  void runBuild() {
    final created = build();
    final ref = this.ref as $Ref<AskReadAloud, AskReadAloud>;
    final element =
        ref.element
            as $ClassProviderElement<
              AnyNotifier<AskReadAloud, AskReadAloud>,
              AskReadAloud,
              Object?,
              Object?
            >;
    element.handleValue(ref, created);
  }
}
