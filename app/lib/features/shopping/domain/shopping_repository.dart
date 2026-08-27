/// The shopping-list read/write contract — PURE DART (invariant 2). The data
/// layer implements it over PowerSync's local SQLite; ViewModels depend only on
/// this.
///
/// The list is DERIVED (spec §4): cook contributions come live from the batch
/// cook plan. Only the overlay is written — check-off state and manual /
/// free-text contributions (`setIngredientChecked` / `setEntryChecked` /
/// `addTopUp` / `addFreeTextItem` / `removeEntry`). The read reacts to any
/// change to the week, a covered recipe, or the overlay.
library;

import '../../../core/units/units.dart';
import 'shopping.dart';

abstract interface class ShoppingRepository {
  /// The derived shopping list for the week beginning [weekStart] (a Monday),
  /// reacting to plan/recipe/overlay changes. Emits an empty [ShoppingList]
  /// when nothing is planned and nothing has been added.
  Stream<ShoppingList> watchShoppingList(DateTime weekStart);

  /// Checks/unchecks an ingredient line, lazily creating its entry (a purely
  /// derived ingredient has no entry until it is first touched).
  Future<void> setIngredientChecked({
    required String ingredientId,
    required bool checked,
  });

  /// Checks/unchecks an existing entry (a free-text item always has one).
  Future<void> setEntryChecked({
    required String entryId,
    required bool checked,
  });

  /// Adds a manual top-up to an ingredient (find-or-create its entry).
  Future<void> addTopUp({
    required String ingredientId,
    required double quantity,
    required Unit unit,
  });

  /// Edits an existing manual contribution (a top-up) in place.
  Future<void> editContribution({
    required String contributionId,
    required double quantity,
    required Unit unit,
  });

  /// Soft-deletes a single manual contribution (removes one top-up, leaving the
  /// entry's other contributions and its check-off state intact).
  Future<void> removeContribution({required String contributionId});

  /// Adds a free-text non-food item ("paper towels"). [category] is optional.
  Future<void> addFreeTextItem({required String text, String? category});

  /// Soft-deletes an entry and its manual contributions (remove a free-text
  /// item, or undo a top-up on an otherwise-underived ingredient).
  Future<void> removeEntry({required String entryId});
}
