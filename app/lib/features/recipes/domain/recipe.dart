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

    /// Honest **per-serving** macros for the recipe as written, or an
    /// incomplete marker (step 9's recipe-page panel; the same summary the
    /// picker rows render). Derived on read from the line items and the
    /// vocab — never persisted, and ignored by `saveRecipe`.
    ///
    /// Per-serving means the servings scaler does NOT move these numbers:
    /// scaling multiplies the whole recipe *and* the servings it yields, so
    /// each serving is unchanged. Null only where a caller builds a [Recipe]
    /// without line nutrition (tests, the editor's in-flight draft).
    RecipeMacroSummary? macros,

    /// What one batch MAKES — "makes 1 cup", "makes 8 piece" (step 8.6 / D2).
    /// Independent of [servingsBase]: portions and yield are two different
    /// facts, and neither derives from the other. Both halves are set or
    /// neither is (a DB check pins it).
    ///
    /// This is the number that turns a component line's `¼ cup` into `¼ of a
    /// batch`. Null ⇒ every derived number about this recipe-as-a-component
    /// honestly says it cannot be computed; nothing assumes `1×`.
    double? yieldQty,
    Unit? yieldUnit,

    /// The optional SECOND denomination of the same batch — "makes 250 g ·
    /// 16 tbsp". Pinned by the database to a DIFFERENT unit family than the
    /// first, so the pair bridges mass↔volume *for this recipe only*, the way
    /// an `ingredient_measure` bridges count↔mass — two stated facts, no
    /// density.
    double? yieldQty2,
    Unit? yieldUnit2,
  }) = _Recipe;

  /// This recipe's stated yields, largest-priority first, with half-stated or
  /// non-positive pairs dropped — the input [resolveComponentAmount] matches a
  /// component line's unit against.
  List<YieldDenomination> get yields =>
      yieldDenominations(yieldQty, yieldUnit, yieldQty2, yieldUnit2);
}

/// A lightweight row for the recipe list. Since 7.7 it also carries what the
/// recipe picker's information-honest rows need: the [favorite] flag and the
/// per-serving [macros] summary (computed on read from the line items — null
/// only where a caller constructs a summary without them).
@freezed
abstract class RecipeSummary with _$RecipeSummary {
  const RecipeSummary._();

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

    /// What one batch makes (step 8.6 / D2) — carried on the summary so a
    /// picker row can say "makes 1 cup" (or "no yield yet") without loading
    /// the whole recipe. See [Recipe.yieldQty].
    double? yieldQty,
    Unit? yieldUnit,
    double? yieldQty2,
    Unit? yieldUnit2,
  }) = _RecipeSummary;

  /// This recipe's stated yields — see [Recipe.yields].
  List<YieldDenomination> get yields =>
      yieldDenominations(yieldQty, yieldUnit, yieldQty2, yieldUnit2);
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

/// One recipe line: an ingredient (referenced by id, name denormalized for
/// display) **or** a sub-recipe component (step 8.6 / D1), at a [quantity] in a
/// [unit], with an optional [note] ("finely chopped"). [quantity] is null for
/// imprecise units carrying no number.
///
/// **Exactly one identity is set** — [ingredientId] or [subRecipeId], never
/// both and never neither (the database's `line_item_identity_xor` check). A
/// component line never carries a [measureId] either: a measure is an
/// *ingredient* concept ("potato, medium = 213 g" says nothing about a
/// recipe), and a second DB check pins that.
///
/// A line quantified in a named measure ("2 × potato, large", step 7.6)
/// carries [measureId] (persisted verbatim — kept even while the measure row
/// hasn't synced, so an unrelated edit never strips it) and, when the row
/// resolved, the [measure] itself. Such a line stores `unit = 'piece'`: if
/// the measure is missing it degrades to an honest count, never invented
/// grams (invariant 3).
///
/// A component line follows the same degrade-don't-destroy rule: [subRecipeId]
/// is the stored id verbatim and [subRecipe] the resolved target, null while
/// the row hasn't synced (or was deleted). Nothing derives from a component
/// whose target is missing — the line simply reads as the text it stored (D5).
@freezed
abstract class LineItem with _$LineItem {
  const LineItem._();

  const factory LineItem({
    required String id,
    required String ingredientName,
    required Unit unit,
    String? ingredientId,
    String? subRecipeId,
    SubRecipeTarget? subRecipe,
    double? quantity,
    String? measureId,
    Measure? measure,
    String? note,
  }) = _LineItem;

  /// Whether this line is a sub-recipe component rather than an ingredient.
  bool get isComponent => subRecipeId != null;

  /// This line as a [Quantity], or null when it carries no number. A measure
  /// line reads as its stored count ('piece') — the measure's gram weight is
  /// applied where totals are summed, not here.
  Quantity? get asQuantity =>
      quantity == null ? null : Quantity(quantity!, unit);

  /// How many batches of [subRecipe] this line asks for, or why that cannot
  /// be said (step 8.6 / D2). Non-null only on a component line whose target
  /// has resolved; a dangling link derives nothing at all (D5).
  ComponentAmount? get componentAmount {
    final target = subRecipe;
    if (target == null) return null;
    return resolveComponentAmount(
      quantity: quantity,
      unit: unit,
      yields: target.yields,
    );
  }
}

/// The recipe a component line points at, joined for display and batch math
/// (step 8.6). Carries only what a *referencing* surface needs: the title to
/// render, and the yields that turn "¼ cup" into "¼ of a batch".
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
  }) = _SubRecipeTarget;

  /// The target's stated yields — see [Recipe.yields].
  List<YieldDenomination> get yields =>
      yieldDenominations(yieldQty, yieldUnit, yieldQty2, yieldUnit2);
}
