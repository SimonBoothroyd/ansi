/// Riverpod ViewModels for the Shop screen.
///
/// [currentShoppingList] streams the derived shopping list for the active week
/// (the same Monday the Week and Cook screens use). Mutations (check-off,
/// top-up, add item) are fire-and-forget calls the view makes on the keep-alive
/// `shoppingRepositoryProvider` directly — no throwaway notifier held across an
/// async gap ([[mise-riverpod-notifier-ref-after-async]]).
library;

import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../planning/presentation/week_view_models.dart';
import '../data/shopping_providers.dart';
import '../domain/shopping.dart';

part 'shopping_view_models.g.dart';

/// The derived shopping list for the active week, reacting to plan/recipe/
/// overlay changes.
@riverpod
Stream<ShoppingList> currentShoppingList(Ref ref) => ref
    .watch(shoppingRepositoryProvider)
    .watchShoppingList(ref.watch(currentWeekStartProvider));
