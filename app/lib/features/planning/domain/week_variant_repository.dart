/// The persistence contract for a week's recipe variants. Pure Dart.
///
/// A variant is one set of [LineOverride]s per `(week, recipe)`, written whole:
/// the repository makes the stored rows equal the set it is handed.
library;

import '../../recipes/domain/line_override.dart';
import '../../recipes/domain/recipe_cost.dart';
import '../../recipes/domain/recipe_macros.dart';

/// A delta naming one of the target's words but no number, refused by
/// `saveOverrides` before it is written. The server would reject it on upload,
/// and a rejected upload makes the PowerSync connector drop the whole crud
/// transaction.
class WordlessOverrideError implements Exception {
  const WordlessOverrideError({
    required this.overrideId,
    required this.recipeMeasureId,
  });

  final String overrideId;
  final String recipeMeasureId;

  @override
  String toString() =>
      'this week’s amount names one of the recipe’s own words but no number — '
      'a word only says something beside a count';
}

abstract interface class WeekVariantRepository {
  /// Every override on the week beginning [weekStart], keyed by recipe id,
  /// live. A recipe with no variant is absent.
  Stream<Map<String, List<LineOverride>>> watchWeekOverrides(
    DateTime weekStart,
  );

  /// One recipe's set for that week, as week mode opens on it.
  Future<List<LineOverride>> loadOverrides(DateTime weekStart, String recipeId);

  /// Makes the stored set for `(weekStart, recipeId)` equal [overrides] in one
  /// transaction: wanted rows are updated in place, the rest tombstoned. An
  /// empty list drops the variant.
  Future<void> saveOverrides(
    DateTime weekStart,
    String recipeId, {
    required List<LineOverride> overrides,
  });

  /// Ticks one optional line in for this week, or back out, by adding or
  /// removing one [LineOverrideAction.include] row and saving the set whole.
  /// Idempotent, and a line with its own stated amount keeps it.
  Future<void> setLineIncluded(
    DateTime weekStart,
    String recipeId,
    String lineId, {
    required bool included,
  });

  /// Macro summaries for the recipes this week varies, summed over each one's
  /// effective lines. A recipe with no variant is absent; the Library's figure
  /// stands for it.
  Stream<Map<String, RecipeMacroSummary>> watchVariantRecipeMacros(
    DateTime weekStart,
  );

  /// The same for cost (ADR-0017).
  Stream<Map<String, RecipeCostSummary>> watchVariantRecipeCosts(
    DateTime weekStart,
  );
}
