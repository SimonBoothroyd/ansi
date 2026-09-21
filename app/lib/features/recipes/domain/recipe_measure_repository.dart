/// Read/write access to a recipe's own measures ("a blob is 15 g", ADR-0018).
/// Pure Dart.
///
/// Duplicate labels merge on read. A unique index on `(recipe_id, label)` would
/// make an offline duplicate fail upload and drop the whole crud transaction,
/// so devices converge on the oldest live row per label (`mergeByLabel`) and
/// hide the newer one, which still resolves by id.
library;

import 'package:meta/meta.dart';

import '../../../core/result/result.dart';
import '../../../core/units/recipe_measure.dart';
import '../../../core/units/units.dart';
import 'recipe.dart';
import 'recipe_measure_authoring.dart';
import 'recipe_repository.dart';

/// The on-tap door for measures (ADR-0011). The recipe editor's MEASURES list
/// defers instead, riding [Recipe.measures] through
/// [RecipeRepository.saveRecipe]. Both are held to [authorRecipeMeasure]. A
/// delete is refused while anything says the word ([countLinesUsing]; ADR-0018
/// rule 3).
abstract interface class RecipeMeasureRepository {
  /// The live words of [recipeId], `sort_order` first, duplicates merged.
  Stream<List<RecipeMeasure>> watchRecipeMeasures(String recipeId);

  /// Coins one word for [recipeId], stamped after its existing words, and
  /// returns it. Throws [RecipeMeasureRefused] with [authorRecipeMeasure]'s
  /// failure. The recipe's `makes` is read off the stored row inside the
  /// transaction, not passed in (ADR-0018 rule 2).
  Future<RecipeMeasure> addRecipeMeasure({
    required String recipeId,
    required String label,
    required double amount,
    required Unit unit,
  });

  /// Re-states one live word's label, number and unit in place, keeping its id
  /// so every line saying it follows. Throws [RecipeMeasureRefused] on
  /// [addRecipeMeasure]'s rules, and for an id naming no live word.
  Future<void> restateRecipeMeasure({
    required String measureId,
    required String label,
    required double amount,
    required Unit unit,
  });

  /// What still says this word: live recipe lines (under a live group of a live
  /// recipe), the recipes they are in, and overrides on live weeks.
  Future<RecipeMeasureUsage> countLinesUsing(String measureId);

  /// Soft-deletes one word, or throws [RecipeMeasureInUse] with
  /// [countLinesUsing]'s counts while anything still points at it.
  Future<void> softDeleteRecipeMeasure(String measureId);
}

/// What a recipe measure is still used by. [lines] counts the live recipe
/// lines, in the recipes [recipes] names. [weeks] counts week overrides
/// separately, since they have no page to open.
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

/// An authoring refusal, as [authorRecipeMeasure] stated it. Repositories throw
/// rather than return a [Result] (see `core/result/result.dart`); [message] is
/// the sentence a form prints.
class RecipeMeasureRefused implements Exception {
  const RecipeMeasureRefused(this.code, this.message);

  /// `recipe_measure/<reason>`, so a caller can branch without matching prose.
  final String code;
  final String message;

  @override
  String toString() => message;
}

/// Why a word could not be retired: lines still say it. Carries counts, not a
/// sentence (`recipeMeasureDeleteRefusalText` phrases it). [label] is the word
/// as stored.
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
