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

/// What the rest of the trip comes to — the figure on the sync line
/// (ADR-0017).
///
/// The UNTICKED rows only: what is in the basket has been picked up, and the
/// question the line answers is what is left. Null when not one row can be
/// priced, because `≈ $0` would read as a free trip rather than an unpriced
/// one.

@ProviderFor(shopTripCost)
const shopTripCostProvider = ShopTripCostProvider._();

/// What the rest of the trip comes to — the figure on the sync line
/// (ADR-0017).
///
/// The UNTICKED rows only: what is in the basket has been picked up, and the
/// question the line answers is what is left. Null when not one row can be
/// priced, because `≈ $0` would read as a free trip rather than an unpriced
/// one.

final class ShopTripCostProvider
    extends $FunctionalProvider<double?, double?, double?>
    with $Provider<double?> {
  /// What the rest of the trip comes to — the figure on the sync line
  /// (ADR-0017).
  ///
  /// The UNTICKED rows only: what is in the basket has been picked up, and the
  /// question the line answers is what is left. Null when not one row can be
  /// priced, because `≈ $0` would read as a free trip rather than an unpriced
  /// one.
  const ShopTripCostProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'shopTripCostProvider',
        isAutoDispose: true,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$shopTripCostHash();

  @$internal
  @override
  $ProviderElement<double?> $createElement($ProviderPointer pointer) =>
      $ProviderElement(pointer);

  @override
  double? create(Ref ref) {
    return shopTripCost(ref);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(double? value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<double?>(value),
    );
  }
}

String _$shopTripCostHash() => r'7b8c8d60c45164a1de8df973ddff214efa378bb2';
