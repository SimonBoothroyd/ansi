// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'shopping_view_models.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning
/// The derived shopping list for the viewed week, reacting to plan/recipe/
/// overlay changes.

@ProviderFor(currentShoppingList)
const currentShoppingListProvider = CurrentShoppingListProvider._();

/// The derived shopping list for the viewed week, reacting to plan/recipe/
/// overlay changes.

final class CurrentShoppingListProvider
    extends
        $FunctionalProvider<
          AsyncValue<ShoppingList>,
          ShoppingList,
          Stream<ShoppingList>
        >
    with $FutureModifier<ShoppingList>, $StreamProvider<ShoppingList> {
  /// The derived shopping list for the viewed week, reacting to plan/recipe/
  /// overlay changes.
  const CurrentShoppingListProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'currentShoppingListProvider',
        isAutoDispose: true,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$currentShoppingListHash();

  @$internal
  @override
  $StreamProviderElement<ShoppingList> $createElement(
    $ProviderPointer pointer,
  ) => $StreamProviderElement(pointer);

  @override
  Stream<ShoppingList> create(Ref ref) {
    return currentShoppingList(ref);
  }
}

String _$currentShoppingListHash() =>
    r'02d26b09cf9d63812a5aedb6bf773d25fbe5cb1e';

/// The one celebration a list gets.
///
/// [arm] is asked from the tap — before the write and before any await —
/// whether THIS tick is the one that finishes the list ([completesTheList])
/// and whether this list has already had its moment. The key is the viewed
/// week plus the list's [completionKeyOf], so unticking and re-ticking the
/// last row does not replay, a row added since can, and the same items next
/// week are a new trip. A completion that arrives by sync never asks, which
/// is the whole of "on this phone". Kept alive so leaving the tab and coming
/// back is not a new list.

@ProviderFor(LastTickCelebration)
const lastTickCelebrationProvider = LastTickCelebrationProvider._();

/// The one celebration a list gets.
///
/// [arm] is asked from the tap — before the write and before any await —
/// whether THIS tick is the one that finishes the list ([completesTheList])
/// and whether this list has already had its moment. The key is the viewed
/// week plus the list's [completionKeyOf], so unticking and re-ticking the
/// last row does not replay, a row added since can, and the same items next
/// week are a new trip. A completion that arrives by sync never asks, which
/// is the whole of "on this phone". Kept alive so leaving the tab and coming
/// back is not a new list.
final class LastTickCelebrationProvider
    extends $NotifierProvider<LastTickCelebration, String?> {
  /// The one celebration a list gets.
  ///
  /// [arm] is asked from the tap — before the write and before any await —
  /// whether THIS tick is the one that finishes the list ([completesTheList])
  /// and whether this list has already had its moment. The key is the viewed
  /// week plus the list's [completionKeyOf], so unticking and re-ticking the
  /// last row does not replay, a row added since can, and the same items next
  /// week are a new trip. A completion that arrives by sync never asks, which
  /// is the whole of "on this phone". Kept alive so leaving the tab and coming
  /// back is not a new list.
  const LastTickCelebrationProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'lastTickCelebrationProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$lastTickCelebrationHash();

  @$internal
  @override
  LastTickCelebration create() => LastTickCelebration();

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(String? value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<String?>(value),
    );
  }
}

String _$lastTickCelebrationHash() =>
    r'c0bab67b3e006a2cbe71a38f9298de8743632fff';

/// The one celebration a list gets.
///
/// [arm] is asked from the tap — before the write and before any await —
/// whether THIS tick is the one that finishes the list ([completesTheList])
/// and whether this list has already had its moment. The key is the viewed
/// week plus the list's [completionKeyOf], so unticking and re-ticking the
/// last row does not replay, a row added since can, and the same items next
/// week are a new trip. A completion that arrives by sync never asks, which
/// is the whole of "on this phone". Kept alive so leaving the tab and coming
/// back is not a new list.

abstract class _$LastTickCelebration extends $Notifier<String?> {
  String? build();
  @$mustCallSuper
  @override
  void runBuild() {
    final created = build();
    final ref = this.ref as $Ref<String?, String?>;
    final element =
        ref.element
            as $ClassProviderElement<
              AnyNotifier<String?, String?>,
              String?,
              Object?,
              Object?
            >;
    element.handleValue(ref, created);
  }
}
