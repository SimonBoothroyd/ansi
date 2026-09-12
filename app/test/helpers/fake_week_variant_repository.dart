/// A canned [WeekVariantRepository] for widget tests: the variant a test wants
/// to draw, and nothing else.
///
/// The default is **no variant at all**, which is the state every screen test
/// that is not about this feature should be in — the week then reads exactly
/// the Library's per-recipe figures, as it did before the variant existed.
library;

import 'package:ansi/features/planning/domain/week_variant_repository.dart';
import 'package:ansi/features/recipes/domain/line_override.dart';
import 'package:ansi/features/recipes/domain/recipe_macros.dart';

class FakeWeekVariantRepository implements WeekVariantRepository {
  FakeWeekVariantRepository({
    this.overrides = const {},
    this.variantMacros = const {},
  });

  /// Keyed by recipe id, as the repository returns it.
  final Map<String, List<LineOverride>> overrides;
  final Map<String, RecipeMacroSummary> variantMacros;

  /// Every `(weekStart, recipeId, set)` a test drove a save with.
  final saved =
      <({DateTime weekStart, String recipeId, List<LineOverride> set})>[];

  @override
  Stream<Map<String, List<LineOverride>>> watchWeekOverrides(
    DateTime weekStart,
  ) => Stream.value(overrides);

  @override
  Future<List<LineOverride>> loadOverrides(
    DateTime weekStart,
    String recipeId,
  ) async => overrides[recipeId] ?? const [];

  @override
  Future<void> saveOverrides(
    DateTime weekStart,
    String recipeId, {
    required List<LineOverride> overrides,
  }) async =>
      saved.add((weekStart: weekStart, recipeId: recipeId, set: overrides));

  /// Every `(weekStart, recipeId, lineId, included)` a test drove the one-tap
  /// door with.
  final ticked =
      <({DateTime weekStart, String recipeId, String lineId, bool included})>[];

  @override
  Future<void> setLineIncluded(
    DateTime weekStart,
    String recipeId,
    String lineId, {
    required bool included,
  }) async => ticked.add((
    weekStart: weekStart,
    recipeId: recipeId,
    lineId: lineId,
    included: included,
  ));

  @override
  Stream<Map<String, RecipeMacroSummary>> watchVariantRecipeMacros(
    DateTime weekStart,
  ) => Stream.value(variantMacros);
}
