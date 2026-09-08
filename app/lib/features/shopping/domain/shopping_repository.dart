/// The shopping-list read/write contract — PURE DART (invariant 2). The data
/// layer implements it over PowerSync's local SQLite; ViewModels depend only on
/// this.
///
/// The list is DERIVED (spec §4): cook contributions come live from the batch
/// cook plan. Only the overlay is written — check-off state and manual /
/// free-text contributions (`setIngredientChecked` / `setEntryChecked` /
/// `addTopUp` / `addFreeTextItem` / `removeEntry`). The read reacts to any
/// change to the week, a covered recipe, or the overlay.
///
/// **The overlay is week-scoped.** Since Cook and Shop follow the week you are
/// LOOKING AT, everything written here has to say which week's list it is on:
/// `setIngredientChecked`, `addTopUp` and `addFreeTextItem` all take the week,
/// and the read only ever returns that week's entries.
library;

import '../../../core/units/units.dart';
import 'shopping.dart';

abstract interface class ShoppingRepository {
  /// The derived shopping list for the week beginning [weekStart] (a Monday),
  /// reacting to plan/recipe/overlay changes. Emits an empty [ShoppingList]
  /// when nothing is planned and nothing has been added.
  Stream<ShoppingList> watchShoppingList(DateTime weekStart);

  /// Checks/unchecks an ingredient line on the list for [weekStart], lazily
  /// creating its entry (a purely derived ingredient has no entry until it is
  /// first touched). The entry is stamped with that week.
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

  /// Adds a manual top-up to an ingredient on the list for [weekStart]
  /// (find-or-create its entry within that week).
  ///
  /// With [measureId], the top-up is counted in that named measure ("2 ×
  /// potato, large"); [unit] must then be the count unit the row stores as
  /// its honest fallback (`pieces`).
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
  /// [weekStart]. [category] is optional.
  ///
  /// Week-scoped exactly like [addTopUp]: you added it while shopping for one
  /// week, so it belongs to that week's list and does not follow you into the
  /// next one.
  Future<void> addFreeTextItem({
    required String text,
    required DateTime weekStart,
    String? category,
  });

  /// Soft-deletes an entry and its manual contributions (remove a free-text
  /// item, or undo a top-up on an otherwise-underived ingredient).
  Future<void> removeEntry({required String entryId});
}
