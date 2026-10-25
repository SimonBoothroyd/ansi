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

/// The price the Shop reads for every row that has one: the cheapest paid in
/// the window ending today, else the price every other cost reads
/// (`shopPriceOf`, ADR-0017). Keep-alive and re-keyed by [todayProvider], so
/// the window moves at midnight and leaving the tab keeps the watch. The
/// Shop's own: no other cost reads it.

@ProviderFor(shopPriceMap)
const shopPriceMapProvider = ShopPriceMapProvider._();

/// The price the Shop reads for every row that has one: the cheapest paid in
/// the window ending today, else the price every other cost reads
/// (`shopPriceOf`, ADR-0017). Keep-alive and re-keyed by [todayProvider], so
/// the window moves at midnight and leaving the tab keeps the watch. The
/// Shop's own: no other cost reads it.

final class ShopPriceMapProvider
    extends
        $FunctionalProvider<
          AsyncValue<Map<String, ShopPrice>>,
          Map<String, ShopPrice>,
          Stream<Map<String, ShopPrice>>
        >
    with
        $FutureModifier<Map<String, ShopPrice>>,
        $StreamProvider<Map<String, ShopPrice>> {
  /// The price the Shop reads for every row that has one: the cheapest paid in
  /// the window ending today, else the price every other cost reads
  /// (`shopPriceOf`, ADR-0017). Keep-alive and re-keyed by [todayProvider], so
  /// the window moves at midnight and leaving the tab keeps the watch. The
  /// Shop's own: no other cost reads it.
  const ShopPriceMapProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'shopPriceMapProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$shopPriceMapHash();

  @$internal
  @override
  $StreamProviderElement<Map<String, ShopPrice>> $createElement(
    $ProviderPointer pointer,
  ) => $StreamProviderElement(pointer);

  @override
  Stream<Map<String, ShopPrice>> create(Ref ref) {
    return shopPriceMap(ref);
  }
}

String _$shopPriceMapHash() => r'64869ec991792631c901fba0af516b879c65a8e3';

/// What each vocabulary row costs at the Shop's price and how its amounts
/// convert. A row the vocabulary has not synced is absent.

@ProviderFor(shopPricing)
const shopPricingProvider = ShopPricingProvider._();

/// What each vocabulary row costs at the Shop's price and how its amounts
/// convert. A row the vocabulary has not synced is absent.

final class ShopPricingProvider
    extends
        $FunctionalProvider<
          Map<String, ShopPricing>,
          Map<String, ShopPricing>,
          Map<String, ShopPricing>
        >
    with $Provider<Map<String, ShopPricing>> {
  /// What each vocabulary row costs at the Shop's price and how its amounts
  /// convert. A row the vocabulary has not synced is absent.
  const ShopPricingProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'shopPricingProvider',
        isAutoDispose: true,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$shopPricingHash();

  @$internal
  @override
  $ProviderElement<Map<String, ShopPricing>> $createElement(
    $ProviderPointer pointer,
  ) => $ProviderElement(pointer);

  @override
  Map<String, ShopPricing> create(Ref ref) {
    return shopPricing(ref);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(Map<String, ShopPricing> value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<Map<String, ShopPricing>>(value),
    );
  }
}

String _$shopPricingHash() => r'92432187a440b4d62e06b904b616c53ef8053bdb';

/// What the rest of the trip comes to at the Shop's prices, and how many rows
/// it could not price (ADR-0017): the sum of the figures the rows print.
/// Unticked rows only. The figure is null when no row can be priced.

@ProviderFor(shopTripCost)
const shopTripCostProvider = ShopTripCostProvider._();

/// What the rest of the trip comes to at the Shop's prices, and how many rows
/// it could not price (ADR-0017): the sum of the figures the rows print.
/// Unticked rows only. The figure is null when no row can be priced.

final class ShopTripCostProvider
    extends $FunctionalProvider<TripCost, TripCost, TripCost>
    with $Provider<TripCost> {
  /// What the rest of the trip comes to at the Shop's prices, and how many rows
  /// it could not price (ADR-0017): the sum of the figures the rows print.
  /// Unticked rows only. The figure is null when no row can be priced.
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

String _$shopTripCostHash() => r'a8c2f9f14a0901af820539dd302b795b5c5822aa';

/// Whether this phone's Shop is in its checking pass — *what's already at
/// home?*. The tick turns into a house and the total into the door
/// to an amount. This phone's alone and never synced: **Done** ends it, and so
/// does leaving the Shop tab.

@ProviderFor(ShopChecking)
const shopCheckingProvider = ShopCheckingProvider._();

/// Whether this phone's Shop is in its checking pass — *what's already at
/// home?*. The tick turns into a house and the total into the door
/// to an amount. This phone's alone and never synced: **Done** ends it, and so
/// does leaving the Shop tab.
final class ShopCheckingProvider extends $NotifierProvider<ShopChecking, bool> {
  /// Whether this phone's Shop is in its checking pass — *what's already at
  /// home?*. The tick turns into a house and the total into the door
  /// to an amount. This phone's alone and never synced: **Done** ends it, and so
  /// does leaving the Shop tab.
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
/// home?*. The tick turns into a house and the total into the door
/// to an amount. This phone's alone and never synced: **Done** ends it, and so
/// does leaving the Shop tab.

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
