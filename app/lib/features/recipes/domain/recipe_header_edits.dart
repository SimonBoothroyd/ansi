/// The rules behind every header edit, as pure transforms on a [Recipe] —
/// PURE DART (invariant 2).
///
/// Two hosts drive the one header form: the recipe editor's notifier and the
/// import review's controller. Each holds its draft differently, but what a
/// setter is *allowed to leave behind* must not differ — a yield that is half a
/// fact, a freezer window on a dish that does not freeze, a section from
/// another book. Those rules live here, once, so a host is only a place to keep
/// the result.
library;

import '../../../core/units/recipe_measure.dart';
import '../../../core/units/units.dart';
import 'recipe.dart';
import 'recipe_measure_authoring.dart';

extension RecipeHeaderEdits on Recipe {
  /// A serving count is never zero (the DB check says so); anything
  /// non-positive reads as one serving.
  Recipe withServings(double servings) =>
      copyWith(servingsBase: servings <= 0 ? 1 : servings);

  /// Sets what one batch MAKES — the first denomination (step 8.6 / D2, board
  /// frame h). Both halves are set or neither is, and clearing the first also
  /// drops the second: the migration pins "a second denomination only when
  /// the first is stated", and a save that bounces off a CHECK is not a state
  /// a host should be able to reach.
  Recipe withYield(double? qty, Unit? unit) {
    final stated = qty != null && qty > 0 && unit != null;
    return copyWith(
      yieldQty: stated ? qty : null,
      yieldUnit: stated ? unit : null,
      yieldQty2: stated ? yieldQty2 : null,
      yieldUnit2: stated ? yieldUnit2 : null,
    );
  }

  /// Sets (or clears, with nulls) the optional SECOND denomination — "makes
  /// 250 g · 16 tbsp". Ignored while no first denomination is stated, and a
  /// unit in the first's own family is refused: the pair exists to bridge two
  /// families, and two numbers in one family would be a second fact about the
  /// same one.
  Recipe withSecondYield(double? qty, Unit? unit) {
    if (yieldQty == null || yieldUnit == null) return this;
    final stated = qty != null && qty > 0 && unit != null;
    if (stated && unit.family == yieldUnit!.family) return this;
    return copyWith(
      yieldQty2: stated ? qty : null,
      yieldUnit2: stated ? unit : null,
    );
  }

  /// The cook time in seconds; null (or non-positive) leaves it unset. No rule
  /// ties it to the total — two typed facts.
  Recipe withCookTime(int? seconds) =>
      copyWith(cookTimeSeconds: _positiveOrNull(seconds));

  /// The total time in seconds; null (or non-positive) leaves it unset.
  Recipe withTotalTime(int? seconds) =>
      copyWith(totalTimeSeconds: _positiveOrNull(seconds));

  /// The fridge shelf life in days; null (or non-positive) leaves it unset —
  /// the cook plan then never splits this recipe.
  Recipe withKeepsForDays(int? days) =>
      copyWith(keepsForDays: _positiveOrNull(days));

  /// Whether the dish freezes. Clearing it also drops any freezer window: a
  /// non-freezable recipe has no freezer days.
  // ignore: avoid_positional_boolean_parameters
  Recipe withFreezable(bool freezable) => copyWith(
    freezable: freezable,
    freezerDays: freezable ? freezerDays : null,
  );

  /// The freezer shelf life in days; null (or non-positive) means "no limit"
  /// — a freezable recipe merges however far the meal is.
  Recipe withFreezerDays(int? days) =>
      copyWith(freezerDays: _positiveOrNull(days));

  /// Seats the recipe's own words — the MEASURES list as the editor left it
  /// (ADR-0018). Every row is stamped with this recipe's id and with its
  /// POSITION as `sort_order`, because the list's order is the only thing that
  /// says which word fronts a component's chip row. Nothing else about a word
  /// is decided here: [authorRecipeMeasure] has already said whether it may
  /// exist.
  ///
  /// A `makes` edit does **not** touch them. A word is an absolute amount, so
  /// re-stating what a batch makes re-states the share and leaves the word
  /// alone (ADR-0018 rule 5), and a word the edit orphans is warned about on
  /// the way out rather than dropped here.
  Recipe withMeasures(List<RecipeMeasure> measures) => copyWith(
    measures: [
      for (final (index, m) in measures.indexed)
        m.copyWith(recipeId: id, sortOrder: index),
    ],
  );

  /// Files the recipe into [bookId], clearing the section (a new book has
  /// none in common with the old one).
  Recipe withBook(String bookId) => copyWith(bookId: bookId, sectionId: null);

  /// Sets (or clears, with null) the section within the current book.
  Recipe withSection(String? sectionId) => copyWith(sectionId: sectionId);
}

int? _positiveOrNull(int? value) =>
    (value == null || value <= 0) ? null : value;
