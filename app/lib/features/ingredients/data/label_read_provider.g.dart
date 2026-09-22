// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'label_read_provider.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning
/// The `read-label` edge function when Supabase is configured. Unconfigured,
/// it refuses out loud rather than pretending to read. Widget tests override
/// this with a reader that answers from a fixture.

@ProviderFor(labelReadRepository)
const labelReadRepositoryProvider = LabelReadRepositoryProvider._();

/// The `read-label` edge function when Supabase is configured. Unconfigured,
/// it refuses out loud rather than pretending to read. Widget tests override
/// this with a reader that answers from a fixture.

final class LabelReadRepositoryProvider
    extends
        $FunctionalProvider<
          LabelReadRepository,
          LabelReadRepository,
          LabelReadRepository
        >
    with $Provider<LabelReadRepository> {
  /// The `read-label` edge function when Supabase is configured. Unconfigured,
  /// it refuses out loud rather than pretending to read. Widget tests override
  /// this with a reader that answers from a fixture.
  const LabelReadRepositoryProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'labelReadRepositoryProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$labelReadRepositoryHash();

  @$internal
  @override
  $ProviderElement<LabelReadRepository> $createElement(
    $ProviderPointer pointer,
  ) => $ProviderElement(pointer);

  @override
  LabelReadRepository create(Ref ref) {
    return labelReadRepository(ref);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(LabelReadRepository value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<LabelReadRepository>(value),
    );
  }
}

String _$labelReadRepositoryHash() =>
    r'4d2cb3708cfcdfdf607b11c0cd292a0e3f3123bd';
