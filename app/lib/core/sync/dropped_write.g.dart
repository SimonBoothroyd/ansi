// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'dropped_write.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning
/// Every write this device has lost, oldest first.
///
/// Keep-alive: a drop is terminal, so it must outlive the screen that happened
/// to be open when it landed. Restored from disk on first read, so a relaunch
/// does not quietly forgive it.

@ProviderFor(DroppedWrites)
const droppedWritesProvider = DroppedWritesProvider._();

/// Every write this device has lost, oldest first.
///
/// Keep-alive: a drop is terminal, so it must outlive the screen that happened
/// to be open when it landed. Restored from disk on first read, so a relaunch
/// does not quietly forgive it.
final class DroppedWritesProvider
    extends $NotifierProvider<DroppedWrites, List<DroppedWrite>> {
  /// Every write this device has lost, oldest first.
  ///
  /// Keep-alive: a drop is terminal, so it must outlive the screen that happened
  /// to be open when it landed. Restored from disk on first read, so a relaunch
  /// does not quietly forgive it.
  const DroppedWritesProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'droppedWritesProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$droppedWritesHash();

  @$internal
  @override
  DroppedWrites create() => DroppedWrites();

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(List<DroppedWrite> value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<List<DroppedWrite>>(value),
    );
  }
}

String _$droppedWritesHash() => r'83cb910933d2ac208bc9daa0fbe7b8135b6102e8';

/// Every write this device has lost, oldest first.
///
/// Keep-alive: a drop is terminal, so it must outlive the screen that happened
/// to be open when it landed. Restored from disk on first read, so a relaunch
/// does not quietly forgive it.

abstract class _$DroppedWrites extends $Notifier<List<DroppedWrite>> {
  List<DroppedWrite> build();
  @$mustCallSuper
  @override
  void runBuild() {
    final created = build();
    final ref = this.ref as $Ref<List<DroppedWrite>, List<DroppedWrite>>;
    final element =
        ref.element
            as $ClassProviderElement<
              AnyNotifier<List<DroppedWrite>, List<DroppedWrite>>,
              List<DroppedWrite>,
              Object?,
              Object?
            >;
    element.handleValue(ref, created);
  }
}
