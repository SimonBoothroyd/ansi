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
