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

/// What the rest of the trip comes to, and how many rows it could not price
/// (ADR-0017). Unticked rows only. The figure is null when no row can be
/// priced.

@ProviderFor(shopTripCost)
const shopTripCostProvider = ShopTripCostProvider._();

/// What the rest of the trip comes to, and how many rows it could not price
/// (ADR-0017). Unticked rows only. The figure is null when no row can be
/// priced.

final class ShopTripCostProvider
    extends $FunctionalProvider<TripCost, TripCost, TripCost>
    with $Provider<TripCost> {
  /// What the rest of the trip comes to, and how many rows it could not price
  /// (ADR-0017). Unticked rows only. The figure is null when no row can be
  /// priced.
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
  $ProviderElement<TripCost> $createElement($ProviderPointer pointer) =>
      $ProviderElement(pointer);

  @override
  TripCost create(Ref ref) {
    return shopTripCost(ref);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(TripCost value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<TripCost>(value),
    );
  }
}

String _$shopTripCostHash() => r'd70bb11f5c5ff8f4a7b36fc0a6ac9052be9d8b8d';

/// Whether this phone's Shop is in its checking pass — *what's already at
/// home?*. The tick turns into a house and the total into the door to an
/// amount. The `To buy · At home?` toggle reads and writes it. This phone's
/// alone and never synced: tapping back to `To buy` ends it, and so do
/// leaving the Shop tab and the wide pane's ×.

@ProviderFor(ShopChecking)
const shopCheckingProvider = ShopCheckingProvider._();

/// Whether this phone's Shop is in its checking pass — *what's already at
/// home?*. The tick turns into a house and the total into the door to an
/// amount. The `To buy · At home?` toggle reads and writes it. This phone's
/// alone and never synced: tapping back to `To buy` ends it, and so do
/// leaving the Shop tab and the wide pane's ×.
final class ShopCheckingProvider extends $NotifierProvider<ShopChecking, bool> {
  /// Whether this phone's Shop is in its checking pass — *what's already at
  /// home?*. The tick turns into a house and the total into the door to an
  /// amount. The `To buy · At home?` toggle reads and writes it. This phone's
  /// alone and never synced: tapping back to `To buy` ends it, and so do
  /// leaving the Shop tab and the wide pane's ×.
  const ShopCheckingProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'shopCheckingProvider',
        isAutoDispose: true,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$shopCheckingHash();

  @$internal
  @override
  ShopChecking create() => ShopChecking();

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(bool value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<bool>(value),
    );
  }
}

String _$shopCheckingHash() => r'8c60efbfef48adcac90569e40b63473df9116262';

/// Whether this phone's Shop is in its checking pass — *what's already at
/// home?*. The tick turns into a house and the total into the door to an
/// amount. The `To buy · At home?` toggle reads and writes it. This phone's
/// alone and never synced: tapping back to `To buy` ends it, and so do
/// leaving the Shop tab and the wide pane's ×.

abstract class _$ShopChecking extends $Notifier<bool> {
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

/// What is open on this phone's Shop: a row's breakdown (keyed by
/// `shoppingItemIdentity`) or a [ShopFold]. Everything starts closed. This
/// phone's alone, never synced, and it lasts the visit: leaving the Shop tab
/// closes it all.

@ProviderFor(ShopOpen)
const shopOpenProvider = ShopOpenProvider._();

/// What is open on this phone's Shop: a row's breakdown (keyed by
/// `shoppingItemIdentity`) or a [ShopFold]. Everything starts closed. This
/// phone's alone, never synced, and it lasts the visit: leaving the Shop tab
/// closes it all.
final class ShopOpenProvider extends $NotifierProvider<ShopOpen, Set<Object>> {
  /// What is open on this phone's Shop: a row's breakdown (keyed by
  /// `shoppingItemIdentity`) or a [ShopFold]. Everything starts closed. This
  /// phone's alone, never synced, and it lasts the visit: leaving the Shop tab
  /// closes it all.
  const ShopOpenProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'shopOpenProvider',
        isAutoDispose: true,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$shopOpenHash();

  @$internal
  @override
  ShopOpen create() => ShopOpen();

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(Set<Object> value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<Set<Object>>(value),
    );
  }
}

String _$shopOpenHash() => r'db94f0627dc22a41923eff8ae95f9f73b238509a';

/// What is open on this phone's Shop: a row's breakdown (keyed by
/// `shoppingItemIdentity`) or a [ShopFold]. Everything starts closed. This
/// phone's alone, never synced, and it lasts the visit: leaving the Shop tab
/// closes it all.

abstract class _$ShopOpen extends $Notifier<Set<Object>> {
  Set<Object> build();
  @$mustCallSuper
  @override
  void runBuild() {
    final created = build();
    final ref = this.ref as $Ref<Set<Object>, Set<Object>>;
    final element =
        ref.element
            as $ClassProviderElement<
              AnyNotifier<Set<Object>, Set<Object>>,
              Set<Object>,
              Object?,
              Object?
            >;
    element.handleValue(ref, created);
  }
}
