/// Read/write access to a recipe's own words for one of what its batch makes —
/// PURE DART (invariant 2), the sub-recipe twin of `MeasureRepository`.
///
/// A [RecipeMeasure] is the household's word for one of what ONE recipe makes
/// — a named AMOUNT in a unit ("a blob is 15 g", ADR-0018) — so another
/// recipe's component line can say `3 blob` of it. A number and a unit define
/// it and nothing here knows what the word says.
///
/// **Duplicate labels merge on read.** No unique index guards
/// `(recipe_id, label)` — one would make an offline duplicate fail upload, and
/// a failed upload drops the whole crud transaction (migration 0011's
/// doctrine, restated by 0048). Every device converges on the *oldest* live row
/// per label instead ([mergeRecipeMeasures]); the newer one is hidden, never
/// deleted, so a line already pointing at it still resolves by id.
library;

import 'package:meta/meta.dart';

import '../../../core/result/result.dart';
import '../../../core/units/recipe_measure.dart';
import '../../../core/units/units.dart';
import 'recipe.dart';
import 'recipe_measure_authoring.dart';
import 'recipe_repository.dart';

/// **Two doors write a measure, and they write it differently** — the same pair
/// the ingredient side has worn since 7.6, and what separates them is whether
/// the host has a Save (ADR-0011).
///
/// - The **recipe editor's MEASURES list**, under MAKES, has one, so it
///   **defers**: the list rides [Recipe.measures] through
///   [RecipeRepository.saveRecipe], which diffs it like any other child. None
///   of this interface's methods are involved.
/// - The **manage-measures page behind the ＋ on a component's quantity dock**
///   has none, so it writes **on tap** — [addRecipeMeasure],
///   [restateRecipeMeasure] and [softDeleteRecipeMeasure] — and a word written
///   there is live on the next chip row.
///
/// Both doors land the same rows under the same rules, because the rules are
/// [authorRecipeMeasure]'s rather than either door's.
///
/// **Nothing follows a measure out, because nothing may.** A line whose word
/// has been retired is unresolved and stays unresolved — never re-read as a
/// count of the yield (ADR-0018 rule 3). So a delete asks [countLinesUsing]
/// first and is REFUSED while anything still says the word, at the repository
/// rather than only at the bin: the refusal *is* the design, and a second door
/// must not be able to walk round it.
abstract interface class RecipeMeasureRepository {
  /// The live words of [recipeId], `sort_order` first, duplicates merged — so
  /// the first is the one that fronts a component's chip row.
  Stream<List<RecipeMeasure>> watchRecipeMeasures(String recipeId);

  /// Coins one word for [recipeId] and returns it for immediate selection —
  /// the ＋ door, which writes on tap.
  ///
  /// Stamped after the recipe's existing words (`sort_order`). Throws
  /// [RecipeMeasureRefused] carrying [authorRecipeMeasure]'s own failure for a
  /// blank label, a label that merely names a catalog unit, a label this
  /// recipe already says, an [amount] that is not a positive finite number, a
  /// [unit] that cannot measure (`batch`, or an imprecise word), or a unit
  /// whose family the recipe's `makes` does not state — the rules hold at the
  /// repository, not only at the form.
  ///
  /// **The `makes` is not a parameter.** ADR-0018 rule 2 gates a word on what
  /// the recipe says a batch makes, which is a fact about the stored recipe;
  /// the implementation reads it off the row inside its own transaction rather
  /// than letting a form assert it.
  Future<RecipeMeasure> addRecipeMeasure({
    required String recipeId,
    required String label,
    required double amount,
    required Unit unit,
  });

  /// Re-states one live word in place, **keeping its id** — `blob` moving from
  /// 15 g to 18 g follows through to every line already saying it, which is the
  /// whole reason this is not a delete and a re-add.
  ///
  /// The label, the number and the unit are re-stated together because they are
  /// one sentence ("a blob is 18 g"), and the row's editor says all three.
  /// Throws [RecipeMeasureRefused] on [addRecipeMeasure]'s rules, and for an
  /// id naming no live word.
  Future<void> restateRecipeMeasure({
    required String measureId,
    required String label,
    required double amount,
    required Unit unit,
  });

  /// What still says this word: how many live rows point at it, and which
  /// recipes they are in — the count the bin's refusal speaks
  /// (`recipeMeasureDeleteRefusalText`) and the door that lists them.
  ///
  /// Both tables that can carry a pointer are counted (0048 names exactly
  /// two), and only while the row is reachable: a line under a live group of a
  /// live recipe, and an override on a live week.
  Future<RecipeMeasureUsage> countLinesUsing(String measureId);

  /// Soft-deletes one word (tombstone, spec §3) — **or refuses**.
  ///
  /// Throws [RecipeMeasureInUse], carrying [countLinesUsing]'s counts, while
  /// anything still points at it. A retired word does not degrade: the lines
  /// saying it would go unresolved and join no total, so the app refuses the
  /// retirement instead of quietly breaking them.
  Future<void> softDeleteRecipeMeasure(String measureId);
}

/// What a recipe measure is still used by — the answer
/// [RecipeMeasureRepository.countLinesUsing] gives.
///
/// [lines] counts the live recipe lines — under a live group of a live recipe,
/// the same set [recipes] names, so the sentence and the door can never
/// disagree. [weeks] counts one week's own amounts separately, because there is
/// no page to send anybody to for one.
@immutable
class RecipeMeasureUsage {
  const RecipeMeasureUsage({
    required this.lines,
    required this.recipes,
    this.weeks = 0,
  });

  static const none = RecipeMeasureUsage(lines: 0, recipes: []);

  final int lines;

  /// Live overrides of live week plans that say this word.
  final int weeks;

  /// Every live recipe with a line saying this word, by title.
  final List<({String id, String title})> recipes;

  bool get any => lines > 0 || weeks > 0;

  @override
  bool operator ==(Object other) =>
      other is RecipeMeasureUsage &&
      other.lines == lines &&
      other.weeks == weeks &&
      other.recipes.length == recipes.length &&
      other.recipes.indexed.every((e) => e.$2 == recipes[e.$1]);

  @override
  int get hashCode => Object.hash(lines, weeks, Object.hashAll(recipes));

  @override
  String toString() =>
      'RecipeMeasureUsage($lines lines, $weeks weeks, '
      '${recipes.length} recipes)';
}

/// A word the household cannot have: the authoring rule that refused it, as
/// [authorRecipeMeasure] stated it.
///
/// A repository throws rather than returning a [Result] (see
/// `core/result/result.dart`): the write door turns a throw into a message
/// with a reason, and [message] is already the sentence a form prints.
class RecipeMeasureRefused implements Exception {
  const RecipeMeasureRefused(this.code, this.message);

  /// `recipe_measure/<reason>` — the code [authorRecipeMeasure] gave, so a
  /// caller can branch without matching on prose.
  final String code;
  final String message;

  @override
  String toString() => message;
}

/// Why a word could not be retired: lines still say it.
///
/// Carries the counts rather than a sentence, because the sentence is the
/// presentation layer's (`recipeMeasureDeleteRefusalText`) and this file is
/// pure Dart. [label] is the word as stored, so the refusal can quote it.
class RecipeMeasureInUse implements Exception {
  const RecipeMeasureInUse({
    required this.measureId,
    required this.label,
    required this.usage,
  });

  final String measureId;
  final String label;
  final RecipeMeasureUsage usage;

  @override
  String toString() =>
      'RecipeMeasureInUse($label: ${usage.lines} lines, '
      '${usage.recipes.length} recipes)';
}
