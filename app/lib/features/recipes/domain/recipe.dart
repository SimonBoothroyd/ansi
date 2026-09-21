/// Recipe domain entities. Pure Dart.
///
/// A [Recipe] holds ordered [IngredientGroup]s, each holding ordered
/// [LineItem]s; the repository assembles them from separate rows. Scaling lives
/// in `scaling.dart`.
library;

// Freezed needs each class's private `._` constructor first (to expose custom
// getters like LineItem.asQuantity), which trips the unnamed-first sort lint.
// ignore_for_file: sort_unnamed_constructors_first
import 'package:freezed_annotation/freezed_annotation.dart';

import '../../../core/units/measure.dart';
import '../../../core/units/recipe_measure.dart';
import '../../../core/units/units.dart';
import 'component_math.dart';
import 'method_step.dart';
import 'recipe_macros.dart';

part 'recipe.freezed.dart';

@freezed
abstract class Recipe with _$Recipe {
  const Recipe._();

  const factory Recipe({
    required String id,
    required String title,

    /// The serving count the written quantities are for. Scaling multiplies
    /// against this (see `scaling.dart`); it is never zero (DB check enforces).
    required double servingsBase,
    @Default(<IngredientGroup>[]) List<IngredientGroup> groups,

    /// Ordered method steps, one line each — the plain-text form the editor
    /// writes and reads.
    @Default(<String>[]) List<String> steps,

    /// Tokenized method, rendered by [foldMethod]. The `steps` jsonb holds
    /// either this or plain-text [steps], never both.
    List<MethodStep>? methodSteps,

    /// Fridge shelf life; drives the cook-plan clustering, set from
    /// the recipe editor's shelf-life inputs.
    int? keepsForDays,
    @Default(false) bool freezable,
    int? freezerDays,

    /// The book and section this recipe is filed under; [sectionId] is null
    /// when unsectioned. [bookName] / [sectionName] are denormalised on read
    /// for display.
    String? bookId,
    String? sectionId,
    String? bookName,
    String? sectionName,

    /// Per-serving macros for the recipe as written, or an incomplete marker.
    /// Derived on read, never persisted, ignored by `saveRecipe`.
    ///
    /// The servings scaler does not move these. Null only where a caller builds
    /// a [Recipe] without line nutrition.
    RecipeMacroSummary? macros,

    /// What one batch makes ("makes 1 cup"). Independent of [servingsBase];
    /// both halves are set or neither (a DB check). Null means a component
    /// line's share of this recipe cannot be computed.
    double? yieldQty,
    Unit? yieldUnit,

    /// The optional second denomination of the same batch ("makes 250 g · 16
    /// tbsp"), pinned by the database to a different unit family, so the pair
    /// bridges mass↔volume for this recipe without a density.
    double? yieldQty2,
    Unit? yieldUnit2,

    /// The household's own words for a portion of this batch, in `sort_order`,
    /// duplicates merged. A measure whose family the yields no longer state
    /// stops resolving.
    @Default(<RecipeMeasure>[]) List<RecipeMeasure> measures,

    /// The printed cook and total times, in seconds. No rule relates them; null
    /// is unset.
    int? cookTimeSeconds,
    int? totalTimeSeconds,
  }) = _Recipe;

  /// This recipe's stated yields in priority order, with half-stated or
  /// non-positive pairs dropped.
  List<YieldDenomination> get yields =>
      yieldDenominations(yieldQty, yieldUnit, yieldQty2, yieldUnit2);

  /// This recipe as another recipe's component target.
  SubRecipeTarget get asSubRecipeTarget => SubRecipeTarget(
    id: id,
    title: title,
    yieldQty: yieldQty,
    yieldUnit: yieldUnit,
    yieldQty2: yieldQty2,
    yieldUnit2: yieldUnit2,
    measures: measures,
  );
}

/// A lightweight row for the recipe list, including the [favorite] flag and the
/// per-serving [macros] summary computed on read.
@freezed
abstract class RecipeSummary with _$RecipeSummary {
  const RecipeSummary._();

  const factory RecipeSummary({
    required String id,
    required String title,
    required double servingsBase,

    /// Shelf-life carried on the summary so the planner can show batch-aware
    /// chips and the "same batch" hint without the full recipe.
    int? keepsForDays,
    @Default(false) bool freezable,
    int? freezerDays,

    /// The household's curated shortlist flag (the picker's Favorites tab).
    @Default(false) bool favorite,

    /// Honest per-serving macros, or an incomplete marker.
    RecipeMacroSummary? macros,

    /// What one batch makes, so a picker row can say "makes 1 cup" without
    /// loading the recipe. See [Recipe.yieldQty].
    double? yieldQty,
    Unit? yieldUnit,
    double? yieldQty2,
    Unit? yieldUnit2,

    /// This recipe's own measures, `sort_order` first, merge-hidden twins
    /// included, so the summary can become a [SubRecipeTarget] without a second
    /// read.
    @Default(<RecipeMeasure>[]) List<RecipeMeasure> measures,
  }) = _RecipeSummary;

  /// This recipe's stated yields — see [Recipe.yields].
  List<YieldDenomination> get yields =>
      yieldDenominations(yieldQty, yieldUnit, yieldQty2, yieldUnit2);

  /// This summary as another recipe's component target. See
  /// [Recipe.asSubRecipeTarget].
  SubRecipeTarget get asSubRecipeTarget => SubRecipeTarget(
    id: id,
    title: title,
    yieldQty: yieldQty,
    yieldUnit: yieldUnit,
    yieldQty2: yieldQty2,
    yieldUnit2: yieldUnit2,
    measures: measures,
  );
}

/// A named group of line-items within a recipe. [name] is null for a recipe
/// with no explicit grouping (a single unnamed group).
@freezed
abstract class IngredientGroup with _$IngredientGroup {
  const factory IngredientGroup({
    required String id,
    String? name,
    @Default(<LineItem>[]) List<LineItem> items,
  }) = _IngredientGroup;
}

/// One recipe line: an ingredient or a sub-recipe component, at a [quantity] in
/// a [unit], with an optional [note]. [quantity] is null for a numberless line.
///
/// Exactly one of [ingredientId] and [subRecipeId] is set (a DB check). Only an
/// ingredient line may carry [measureId]; only a component line
/// [recipeMeasureId]. References degrade rather than disappear: a missing
/// measure reads as the stored `piece` count, a retired ingredient keeps its id
/// and name with [ingredientDeleted] set, and a missing component target reads
/// as stored text. [optional] lines are left out of macros and shopping through
/// `effectiveLines`.
@freezed
abstract class LineItem with _$LineItem {
  const LineItem._();

  @Assert(
    'unit != null || recipeMeasureId != null',
    'a line is denominated in a catalog unit or in a recipe measure',
  )
  @Assert(
    'unit == null || recipeMeasureId == null',
    'a line is denominated in ONE of the two, never both',
  )
  const factory LineItem({
    required String id,
    required String ingredientName,

    /// The catalog unit the [quantity] is said in, or null on a component line
    /// said in one of the target's words ([recipeMeasureId]). Exactly one of
    /// the two is set, as the database checks.
    Unit? unit,
    String? ingredientId,
    String? subRecipeId,
    SubRecipeTarget? subRecipe,
    double? quantity,
    String? measureId,
    Measure? measure,

    /// The target recipe's own word this line is said in (`3 blob`). Set only
    /// on a component line with a [quantity].
    ///
    /// Persisted verbatim like [measureId]. The row it names is read off
    /// [SubRecipeTarget.measures], not joined onto the line.
    String? recipeMeasureId,
    String? note,
    @Default(false) bool optional,

    /// Whether [measureId] points at a measure the household deleted, as
    /// opposed to one that has not synced yet. Both leave [measure] null.
    @Default(false) bool measureDeleted,

    /// Whether [ingredientId] points at a retired vocab row (`deleted_at` set).
    /// The last known name still reads; nothing else derives from the row.
    @Default(false) bool ingredientDeleted,
  }) = _LineItem;

  /// Whether this line is a sub-recipe component rather than an ingredient.
  bool get isComponent => subRecipeId != null;

  /// Whether this line's amount is said in one of the target recipe's words,
  /// the one state in which [unit] is null.
  bool get isMeasuredComponent => recipeMeasureId != null;

  /// This line as a [Quantity], or null when it carries no number or no catalog
  /// unit. An ingredient measure line reads as its stored count; the measure's
  /// weight is applied where totals are summed. A recipe-measure line has no
  /// [Quantity]; see [componentAmount].
  Quantity? get asQuantity {
    final q = quantity;
    final u = unit;
    return q == null || u == null ? null : Quantity(q, u);
  }

  /// How many batches of [subRecipe] this line asks for, or why that cannot be
  /// said. Non-null only on a component line whose target has resolved.
  ComponentAmount? get componentAmount {
    final target = subRecipe;
    if (target == null) return null;
    return resolveComponentAmount(
      quantity: quantity,
      unit: unit,
      yields: target.yields,
      recipeMeasureId: recipeMeasureId,
      measures: target.measures,
    );
  }
}

/// The recipe a component line points at, joined for display and batch math:
/// its title, yields and own measures.
@freezed
abstract class SubRecipeTarget with _$SubRecipeTarget {
  const SubRecipeTarget._();

  const factory SubRecipeTarget({
    required String id,
    required String title,
    double? yieldQty,
    Unit? yieldUnit,
    double? yieldQty2,
    Unit? yieldUnit2,

    /// The target's live measures, `sort_order` first, including merge-hidden
    /// duplicates, because a line pointing at a hidden twin still resolves.
    /// `componentUnitChoices` dedupes what a chip row offers. When empty, a
    /// measured line reads as [ComponentMeasureMissing].
    @Default(<RecipeMeasure>[]) List<RecipeMeasure> measures,
  }) = _SubRecipeTarget;

  /// The target's stated yields — see [Recipe.yields].
  List<YieldDenomination> get yields =>
      yieldDenominations(yieldQty, yieldUnit, yieldQty2, yieldUnit2);
}
