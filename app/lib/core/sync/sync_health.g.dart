// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'sync_health.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning
/// The app's single answer to "are my changes getting through?".
///
/// Keep-alive: the banner and the two quiet lines live on different screens,
/// and the "since" timestamp must survive a tab switch.

@ProviderFor(syncHealth)
const syncHealthProvider = SyncHealthProvider._();

/// The app's single answer to "are my changes getting through?".
///
/// Keep-alive: the banner and the two quiet lines live on different screens,
/// and the "since" timestamp must survive a tab switch.

final class SyncHealthProvider
    extends
        $FunctionalProvider<
          AsyncValue<SyncHealth>,
          SyncHealth,
          Stream<SyncHealth>
        >
    with $FutureModifier<SyncHealth>, $StreamProvider<SyncHealth> {
  /// The app's single answer to "are my changes getting through?".
  ///
  /// Keep-alive: the banner and the two quiet lines live on different screens,
  /// and the "since" timestamp must survive a tab switch.
  const SyncHealthProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'syncHealthProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$syncHealthHash();

  @$internal
  @override
  $StreamProviderElement<SyncHealth> $createElement($ProviderPointer pointer) =>
      $StreamProviderElement(pointer);

  @override
  Stream<SyncHealth> create(Ref ref) {
    return syncHealth(ref);
  }
}

String _$syncHealthHash() => r'ba295b7196e5a820f8a59fbc048e26a019bc41ef';
