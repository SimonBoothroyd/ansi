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

/// Whether the sync connection is live right now.
///
/// **Not a fifth health state**, and never rendered as one — "offline" stays a
/// thing this app does not say about itself. It exists for the one control
/// that cannot act without the server: flipping the household's first day of
/// the week runs a transaction over every week the household has planned, so
/// the chips go inert with a reason rather than tappable and failing.
///
/// PowerSync publishes `connected` on its status, and the status is readable
/// synchronously, so the stream leads with where the device stands and then
/// follows every change.

@ProviderFor(serverReachable)
const serverReachableProvider = ServerReachableProvider._();

/// Whether the sync connection is live right now.
///
/// **Not a fifth health state**, and never rendered as one — "offline" stays a
/// thing this app does not say about itself. It exists for the one control
/// that cannot act without the server: flipping the household's first day of
/// the week runs a transaction over every week the household has planned, so
/// the chips go inert with a reason rather than tappable and failing.
///
/// PowerSync publishes `connected` on its status, and the status is readable
/// synchronously, so the stream leads with where the device stands and then
/// follows every change.

final class ServerReachableProvider
    extends $FunctionalProvider<AsyncValue<bool>, bool, Stream<bool>>
    with $FutureModifier<bool>, $StreamProvider<bool> {
  /// Whether the sync connection is live right now.
  ///
  /// **Not a fifth health state**, and never rendered as one — "offline" stays a
  /// thing this app does not say about itself. It exists for the one control
  /// that cannot act without the server: flipping the household's first day of
  /// the week runs a transaction over every week the household has planned, so
  /// the chips go inert with a reason rather than tappable and failing.
  ///
  /// PowerSync publishes `connected` on its status, and the status is readable
  /// synchronously, so the stream leads with where the device stands and then
  /// follows every change.
  const ServerReachableProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'serverReachableProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$serverReachableHash();

  @$internal
  @override
  $StreamProviderElement<bool> $createElement($ProviderPointer pointer) =>
      $StreamProviderElement(pointer);

  @override
  Stream<bool> create(Ref ref) {
    return serverReachable(ref);
  }
}

String _$serverReachableHash() => r'682208e56a780cb09ceca0e47117c4d71b5f0560';
