/// Recipe domain entities — the read aggregate the UI renders.
///
/// PURE DART (invariant 2): no `package:flutter`. A [Recipe] holds ordered
/// [IngredientGroup]s ("for the sauce"), each holding ordered [LineItem]s. The
/// database stores these as separate rows; the repository assembles them into
/// this aggregate (order = list order). Scaling lives in `scaling.dart`.
library;

// Freezed needs each class's private `._` constructor first (to expose custom
// getters like LineItem.asQuantity), which trips the unnamed-first sort lint.
// ignore_for_file: sort_unnamed_constructors_first
import 'package:freezed_annotation/freezed_annotation.dart';

import '../../../core/units/measure.dart';
import '../../../core/units/units.dart';
import 'method_step.dart';
import 'recipe_macros.dart';

part 'recipe.freezed.dart';

@freezed
abstract class Recipe with _$Recipe {
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

    /// Tokenized method (step 8 import): text/ref/timer chips rendered by the
    /// fold ([foldMethod]). Non-null only for an imported recipe; the editor's
    /// plain-text [steps] and this are the two shapes the `steps` jsonb holds
    /// ([mise-data-ephemeral] — no back-compat, they don't coexist on one row).
    List<MethodStep>? methodSteps,

    /// Fridge shelf life; drives the cook-plan clustering (step 5), set from
    /// the recipe editor's shelf-life inputs.
    int? keepsForDays,
    @Default(false) bool freezable,
    int? freezerDays,

    /// The book/section this recipe is filed under (step 3). [bookId] is set for
    /// any recipe surfaced through the Library; [sectionId] is null when
    /// Unsectioned. [bookName]/[sectionName] are denormalised for the recipe
    /// page's "Book · Section" hero line (display-only; assembled on read).
    String? bookId,
    String? sectionId,
    String? bookName,
    String? sectionName,
  }) = _Recipe;
}

/// A lightweight row for the recipe list. Since 7.7 it also carries what the
/// recipe picker's information-honest rows need: the [favorite] flag and the
/// per-serving [macros] summary (computed on read from the line items — null
/// only where a caller constructs a summary without them).
@freezed
abstract class RecipeSummary with _$RecipeSummary {
  const factory RecipeSummary({
    required String id,
    required String title,
    required double servingsBase,

    /// Shelf-life carried on the summary so the planner can show batch-aware
    /// chips and the "same batch" hint without the full recipe (step 5).
    int? keepsForDays,
    @Default(false) bool freezable,
    int? freezerDays,

    /// The household's curated shortlist flag (the picker's Favorites tab).
    @Default(false) bool favorite,

    /// Honest per-serving macros, or an incomplete marker (step 7.7).
    RecipeMacroSummary? macros,
  }) = _RecipeSummary;
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

/// One ingredient line: an ingredient (referenced by id, name denormalized for
/// display) at a [quantity] in a [unit], with an optional [note] ("finely
/// chopped"). [quantity] is null for imprecise units carrying no number.
///
/// A line quantified in a named measure ("2 × potato, large", step 7.6)
/// carries [measureId] (persisted verbatim — kept even while the measure row
/// hasn't synced, so an unrelated edit never strips it) and, when the row
/// resolved, the [measure] itself. Such a line stores `unit = 'piece'`: if
/// the measure is missing it degrades to an honest count, never invented
/// grams (invariant 3).
@freezed
abstract class LineItem with _$LineItem {
  const LineItem._();

  const factory LineItem({
    required String id,
    required String ingredientId,
    required String ingredientName,
    required Unit unit,
    double? quantity,
    String? measureId,
    Measure? measure,
    String? note,
  }) = _LineItem;

  /// This line as a [Quantity], or null when it carries no number. A measure
  /// line reads as its stored count ('piece') — the measure's gram weight is
  /// applied where totals are summed, not here.
  Quantity? get asQuantity =>
      quantity == null ? null : Quantity(quantity!, unit);
}
