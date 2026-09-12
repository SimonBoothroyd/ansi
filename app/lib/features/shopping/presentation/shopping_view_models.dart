/// Riverpod ViewModels for the Shop screen.
///
/// [currentShoppingList] streams the derived shopping list for the **viewed**
/// week — the same week start the Week and Cook screens show (D3). Mutations
/// (check-off,
/// top-up, add item) are fire-and-forget calls the view makes on the keep-alive
/// [shoppingRepositoryProvider] directly — never a throwaway notifier held
/// across an async gap, which Riverpod disposes underneath the call.
/// [LastTickCelebration] remembers which list has had its confetti.
library;

import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../planning/presentation/week_view_models.dart';
import '../data/shopping_providers.dart';
import '../domain/shopping.dart';

part 'shopping_view_models.g.dart';

/// The derived shopping list for the viewed week, reacting to plan/recipe/
/// overlay changes.
@riverpod
Stream<ShoppingList> currentShoppingList(Ref ref) => ref
    .watch(shoppingRepositoryProvider)
    .watchShoppingList(ref.watch(viewedWeekStartProvider));

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
@Riverpod(keepAlive: true)
class LastTickCelebration extends _$LastTickCelebration {
  @override
  String? build() => null;

  /// Whether to play, recording the list as played when so.
  bool arm(DateTime weekStart, ShoppingList list, ShoppingItem item) {
    if (!completesTheList(list, item)) return false;
    final key = '${weekStart.toIso8601String()} ${completionKeyOf(list)}';
    if (state == key) return false;
    state = key;
    return true;
  }
}
