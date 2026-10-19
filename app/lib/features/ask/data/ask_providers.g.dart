// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'ask_providers.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning
/// The `ask` edge function when Supabase is configured. Unconfigured, it says
/// so rather than pretending to answer. Tests override this with a fake.

@ProviderFor(askRepository)
const askRepositoryProvider = AskRepositoryProvider._();

/// The `ask` edge function when Supabase is configured. Unconfigured, it says
/// so rather than pretending to answer. Tests override this with a fake.

final class AskRepositoryProvider
    extends $FunctionalProvider<AskRepository, AskRepository, AskRepository>
    with $Provider<AskRepository> {
  /// The `ask` edge function when Supabase is configured. Unconfigured, it says
  /// so rather than pretending to answer. Tests override this with a fake.
  const AskRepositoryProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'askRepositoryProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$askRepositoryHash();

  @$internal
  @override
  $ProviderElement<AskRepository> $createElement($ProviderPointer pointer) =>
      $ProviderElement(pointer);

  @override
  AskRepository create(Ref ref) {
    return askRepository(ref);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(AskRepository value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<AskRepository>(value),
    );
  }
}

String _$askRepositoryHash() => r'16cac83cf44376dceed9abe246f560e2776e6d98';
