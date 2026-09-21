/// The rules behind every header edit, as pure transforms on a [Recipe]. Pure
/// Dart. Shared by the recipe editor's notifier and the import review's
/// controller, so neither can leave an invalid header behind.
library;

import '../../../core/units/recipe_measure.dart';
import '../../../core/units/units.dart';
import 'recipe.dart';
import 'recipe_measure_authoring.dart';

extension RecipeHeaderEdits on Recipe {
  /// A non-positive serving count reads as one serving (the DB forbids zero).
  Recipe withServings(double servings) =>
      copyWith(servingsBase: servings <= 0 ? 1 : servings);

  /// Sets what one batch makes (the first denomination). Both halves are set or
  /// neither; clearing it also drops the second, as the server's check
  /// requires.
  Recipe withYield(double? qty, Unit? unit) {
    final stated = qty != null && qty > 0 && unit != null;
    return copyWith(
      yieldQty: stated ? qty : null,
      yieldUnit: stated ? unit : null,
      yieldQty2: stated ? yieldQty2 : null,
      yieldUnit2: stated ? yieldUnit2 : null,
    );
  }

  /// Sets or clears the optional second denomination ("makes 250 g · 16 tbsp").
  /// Ignored without a first denomination; a unit in the first's family is
  /// refused, since the pair exists to bridge two families.
  Recipe withSecondYield(double? qty, Unit? unit) {
    if (yieldQty == null || yieldUnit == null) return this;
    final stated = qty != null && qty > 0 && unit != null;
    if (stated && unit.family == yieldUnit!.family) return this;
    return copyWith(
      yieldQty2: stated ? qty : null,
      yieldUnit2: stated ? unit : null,
    );
  }

  /// The cook time in seconds; null or non-positive leaves it unset.
  /// Independent of the total time.
  Recipe withCookTime(int? seconds) =>
      copyWith(cookTimeSeconds: _positiveOrNull(seconds));

  /// The total time in seconds; null (or non-positive) leaves it unset.
  Recipe withTotalTime(int? seconds) =>
      copyWith(totalTimeSeconds: _positiveOrNull(seconds));

  /// The fridge shelf life in days; null or non-positive leaves it unset, and
  /// the cook plan then never splits this recipe.
  Recipe withKeepsForDays(int? days) =>
      copyWith(keepsForDays: _positiveOrNull(days));

  /// Whether the dish freezes. Clearing it also drops the freezer window.
  // ignore: avoid_positional_boolean_parameters
  Recipe withFreezable(bool freezable) => copyWith(
    freezable: freezable,
    freezerDays: freezable ? freezerDays : null,
  );

  /// The freezer shelf life in days; null or non-positive means no limit.
  Recipe withFreezerDays(int? days) =>
      copyWith(freezerDays: _positiveOrNull(days));

  /// Seats the recipe's measures as the editor left them (ADR-0018), stamping
  /// each with this recipe's id and its position as `sort_order`. Validity is
  /// [authorRecipeMeasure]'s job. A `makes` edit does not touch them (ADR-0018
  /// rule 5); an orphaned word is warned about, not dropped.
  Recipe withMeasures(List<RecipeMeasure> measures) => copyWith(
    measures: [
      for (final (index, m) in measures.indexed)
        m.copyWith(recipeId: id, sortOrder: index),
    ],
  );

  /// Files the recipe into [bookId], clearing the section.
  Recipe withBook(String bookId) => copyWith(bookId: bookId, sectionId: null);

  /// Sets (or clears, with null) the section within the current book.
  Recipe withSection(String? sectionId) => copyWith(sectionId: sectionId);
}

int? _positiveOrNull(int? value) =>
    (value == null || value <= 0) ? null : value;
