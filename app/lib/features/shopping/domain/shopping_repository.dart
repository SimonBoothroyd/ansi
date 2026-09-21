/// The shopping-list read/write contract. Pure Dart.
///
/// The list is derived: cook contributions come live from the batch cook plan.
/// Only the overlay is written (check-off state, manual top-ups and free-text
/// items), and it is week-scoped: every write names the week, and the read
/// returns only that week's entries.
library;

import '../../../core/units/units.dart';
import 'shopping.dart';

abstract interface class ShoppingRepository {
  /// The derived shopping list for the week beginning [weekStart], reacting to
  /// plan, recipe and overlay changes. Emits an empty [ShoppingList] when
  /// nothing is planned or added.
  Stream<ShoppingList> watchShoppingList(DateTime weekStart);

  /// Checks or unchecks an ingredient on the list for [weekStart], creating its
  /// entry on first touch, stamped with that week.
  Future<void> setIngredientChecked({
    required String ingredientId,
    required bool checked,
    required DateTime weekStart,
  });

  /// Checks/unchecks an existing entry (a free-text item always has one).
  Future<void> setEntryChecked({
    required String entryId,
    required bool checked,
  });

  /// Adds a manual top-up to an ingredient on the list for [weekStart], finding
  /// or creating its entry within that week. With [measureId] the top-up is
  /// counted in that measure, and [unit] must be the count unit (`pieces`).
  Future<void> addTopUp({
    required String ingredientId,
    required double quantity,
    required Unit unit,
    required DateTime weekStart,
    String? measureId,
  });

  /// Edits an existing manual contribution (a top-up) in place. [measureId]
  /// follows the same contract as [addTopUp] (null clears a stored measure).
  Future<void> editContribution({
    required String contributionId,
    required double quantity,
    required Unit unit,
    String? measureId,
  });

  /// Soft-deletes a single manual contribution (removes one top-up, leaving the
  /// entry's other contributions and its check-off state intact).
  Future<void> removeContribution({required String contributionId});

  /// Adds a free-text non-food item ("paper towels") to the list for
  /// [weekStart]. [category] is optional. Week-scoped like [addTopUp].
  Future<void> addFreeTextItem({
    required String text,
    required DateTime weekStart,
    String? category,
  });

  /// Soft-deletes an entry and its manual contributions (remove a free-text
  /// item, or undo a top-up on an otherwise-underived ingredient).
  Future<void> removeEntry({required String entryId});
}
