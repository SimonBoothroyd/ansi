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

    /// Tokenized method (step 8 import): text/ref/timer chips rendered by the
    /// fold ([foldMethod]). Non-null only for an imported recipe; the editor's
    /// plain-text [steps] and this are the two shapes the `steps` jsonb holds,
    /// and one row carries one of them — never both.
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

    /// The household's own words for one of what this batch makes — `blob`,
    /// `ladle`, `loaf` — in `sort_order`, duplicates already merged.
    ///
    /// Each is an amount in a unit, read against the yield of its family:
    /// re-stating `makes` does not re-state a measure, but a measure whose
    /// family the yields no longer state stops resolving.
    @Default(<RecipeMeasure>[]) List<RecipeMeasure> measures,

    /// The printed cook and total times, in seconds. Two typed facts with no
    /// rule between them — a total below the cook time is what somebody wrote,
    /// not an error to refuse. Null is unset: the page never said, and nothing
    /// invents one.
    int? cookTimeSeconds,
    int? totalTimeSeconds,
  }) = _Recipe;

  /// This recipe's stated yields, largest-priority first, with half-stated or
  /// non-positive pairs dropped — the input [resolveComponentAmount] matches a
  /// component line's unit against.
  List<YieldDenomination> get yields =>
      yieldDenominations(yieldQty, yieldUnit, yieldQty2, yieldUnit2);

  /// This recipe as another recipe's component target — what an editor that
  /// has just saved a sub-recipe hands back to the line waiting on it, so the
  /// quantity sheet opens on the yields without a second read.
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

    /// This recipe's own words for one of what its batch makes, `sort_order`
    /// first, with any merge-hidden twins behind them — this summary becomes a
    /// [SubRecipeTarget], which is a list lines are resolved against.
    ///
    /// Carried on the summary for the reason the yields are: a picker row that
    /// hands this recipe on as a component TARGET must hand the words over
    /// with it, or the line it lands on could not be said in one of them
    /// without a second read.
    @Default(<RecipeMeasure>[]) List<RecipeMeasure> measures,
  }) = _RecipeSummary;

  /// This recipe's stated yields — see [Recipe.yields].
  List<YieldDenomination> get yields =>
      yieldDenominations(yieldQty, yieldUnit, yieldQty2, yieldUnit2);

  /// This summary as another recipe's component target — what a picker row
  /// hands the line it was opened for, so the quantity dock opens on the
  /// yields AND the words without a second read. See
  /// [Recipe.asSubRecipeTarget], which answers the same question one aggregate
  /// up.
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

/// One recipe line: an ingredient (referenced by id, name denormalized for
/// display) **or** a sub-recipe component (step 8.6 / D1), at a [quantity] in a
/// [unit], with an optional [note] ("finely chopped"). [quantity] is null for
/// imprecise units carrying no number.
///
/// **Exactly one identity is set** — [ingredientId] or [subRecipeId], never
/// both and never neither (the database's `line_item_identity_xor` check). A
/// component line never carries a [measureId] either: a measure is an
/// *ingredient* concept ("potato, medium = 213 g" says nothing about a
/// recipe), and a second DB check pins that. Its own word is
/// [recipeMeasureId], which only a component line may carry, for the mirror
/// reason — `blob` is a word for one recipe.
///
/// A line quantified in a named measure ("2 × potato, large", step 7.6)
/// carries [measureId] (persisted verbatim — kept even while the measure row
/// hasn't synced, so an unrelated edit never strips it) and, when the row
/// resolved, the [measure] itself. Such a line stores `unit = 'piece'`: if
/// the measure is missing it degrades to an honest count, never invented
/// grams (invariant 3).
///
/// A line whose INGREDIENT has been retired follows the same rule one referent
/// up: [ingredientId] is the stored id verbatim, [ingredientName] the row's
/// last known name, and [ingredientDeleted] says so — the line is shown and
/// re-pointable, never silently blank and never dropped. Nothing derives from
/// the retired row (no macros, no density, no measures), because a retired row
/// is not a fact about food any more.
///
/// A component line follows the same degrade-don't-destroy rule: [subRecipeId]
/// is the stored id verbatim and [subRecipe] the resolved target, null while
/// the row hasn't synced (or was deleted). Nothing derives from a component
/// whose target is missing — the line simply reads as the text it stored (D5).
///
/// An **optional** line is one the recipe says may be left out — "lime, to
/// serve (optional)". It is a stored fact about the line, not about its amount:
/// "1 lime" is still what the recipe says. What the flag changes is what a
/// TOTAL covers, through one seam (`effectiveLines`): the macro summary and the
/// shopping list leave the line out and name it where it left; the cook plan is
/// unaffected. A component line carries it too — "aioli (optional)" is a thing
/// a recipe says — and the seam names the sub-recipe's title where it left.
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

    /// The catalog unit the [quantity] is said in, or **null** on a component
    /// line said in one of the target's own words instead
    /// ([recipeMeasureId]).
    ///
    /// Exactly one of the two is set — the database's
    /// `num_nonnulls(unit, recipe_measure_id) = 1`, asserted here too. There
    /// is no companion unit a measured line could honestly carry: `batch` is
    /// the right dimension with the wrong number, and `piece` is the count
    /// degradation the whole feature refuses.
    Unit? unit,
    String? ingredientId,
    String? subRecipeId,
    SubRecipeTarget? subRecipe,
    double? quantity,
    String? measureId,
    Measure? measure,

    /// The target recipe's own word this line is said in — `3 blob`
    /// (`recipe_line_item.recipe_measure_id`). Set only on a component line,
    /// and only with a [quantity]: a word with no number says nothing.
    ///
    /// Persisted verbatim, like [measureId], so a word that has not synced
    /// yet is never stripped by an unrelated edit. The row it names is read
    /// off the target ([SubRecipeTarget.measures]) rather than joined onto
    /// the line, because the word belongs to the recipe being used, not to
    /// the line using it — which is also what makes a re-stated `blob` follow
    /// through to every line already saying it.
    String? recipeMeasureId,
    String? note,
    @Default(false) bool optional,

    /// Whether [measureId] points at a measure the household has DELETED, as
    /// opposed to one that simply has not arrived yet. Both leave [measure]
    /// null and the line reading its stored count, and only this tells the
    /// two apart — so a line can say which it is instead of promising a sync
    /// that is never coming.
    @Default(false) bool measureDeleted,

    /// Whether [ingredientId] points at a vocab row the household has
    /// RETIRED (`deleted_at` set). The name still reads — it is the row's
    /// last known one, joined without the liveness guard — and nothing is
    /// derived from the row: the line is shown, named, and repairable rather
    /// than blanked. Same degrade-don't-destroy shape as [measureDeleted],
    /// one referent up.
    @Default(false) bool ingredientDeleted,
  }) = _LineItem;

  /// Whether this line is a sub-recipe component rather than an ingredient.
  bool get isComponent => subRecipeId != null;

  /// Whether this line's amount is said in one of the TARGET recipe's own
  /// words rather than in a catalog unit — the one state in which [unit] is
  /// null.
  bool get isMeasuredComponent => recipeMeasureId != null;

  /// This line as a [Quantity], or null when it carries no number **or no
  /// catalog unit**. An ingredient measure line reads as its stored count
  /// ('piece') — the measure's gram weight is applied where totals are
  /// summed, not here. A component line said in a recipe measure has no
  /// quantity in the unit system at all: what it is, is a share of a batch,
  /// and [componentAmount] is the only thing that can say so.
  Quantity? get asQuantity {
    final q = quantity;
    final u = unit;
    return q == null || u == null ? null : Quantity(q, u);
  }

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
      recipeMeasureId: recipeMeasureId,
      measures: target.measures,
    );
  }
}

/// The recipe a component line points at, joined for display and batch math
/// (step 8.6). Carries only what a *referencing* surface needs: the title to
/// render, the yields that turn "¼ cup" into "¼ of a batch", and the target's
/// own words that turn "3 blob" into the same thing without a yield at all.
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

    /// The target's live measures, `sort_order` first — the list a line's
    /// [LineItem.recipeMeasureId] is looked up in, so it carries EVERY live
    /// row, the merge-hidden duplicates behind the rest: a line pointing at a
    /// hidden twin still means what it said. What a chip row may OFFER is the
    /// deduped half (`componentUnitChoices` does it, so no caller has to know
    /// which list it holds). Empty for a recipe that coins none, and for a
    /// caller that
    /// assembled a target without reading them, where a measured line then
    /// reads as [ComponentMeasureMissing] rather than as anything invented.
    @Default(<RecipeMeasure>[]) List<RecipeMeasure> measures,
  }) = _SubRecipeTarget;

  /// The target's stated yields — see [Recipe.yields].
  List<YieldDenomination> get yields =>
      yieldDenominations(yieldQty, yieldUnit, yieldQty2, yieldUnit2);
}
