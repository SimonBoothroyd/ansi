/// A recipe's own word for a share of one batch — PURE DART, no
/// `package:flutter` (enforced in CI), the sub-recipe twin of `measure.dart`.
///
/// A [RecipeMeasure] names a real-world portion of ONE recipe and pins how
/// many of them a batch comes to: "a batch makes 20 blob", "a batch makes 6
/// ladle", "a batch makes 1 loaf". The household coins the word; nothing in
/// this app knows or cares what it says.
///
/// **One number, and it is a count per batch.** Not an amount in a yield unit,
/// not a serving, not a fraction: `perBatch` is how many of these one run of
/// the recipe produces, so a line asking for `3 blob` asks for `3 / 20` of a
/// batch. That is the whole arithmetic, and it is why a measure needs no
/// `makes`, no unit family and no density — the three facts a component line
/// otherwise has to go through to reach a batch.
///
/// It is **independent of the recipe's yield.** Re-stating `makes` does not
/// re-state the measures and re-stating a measure does not re-state `makes`:
/// they are separate statements about the same batch, exactly as the two yield
/// denominations are, and neither derives from the other.
///
/// Honesty rules (invariant 3):
///
/// - A line naming a measure the recipe no longer has is **unresolved**, not a
///   count: `3` of a word nobody can measure is not 3 pieces of the yield, and
///   a wrong batch count is worse than a missing one.
/// - A non-positive (or NaN) [perBatch] says nothing about a share, so it
///   converts nothing — the same line `measure.dart` draws around a
///   non-positive basis amount. The database pins `per_batch > 0`; this is
///   what keeps the Dart total against a foreign or in-flight row.
/// - Scaling a parent recipe multiplies the LINE's quantity, never the
///   measure. `6 blob` is 0.3 batches; the batch still makes 20 blob.
library;

import 'package:meta/meta.dart';

/// One named measure of one recipe: `n` of it are `n / perBatch` batches.
///
/// Value-equal on all fields; [id] is the persisted `recipe_measure.id`
/// (referenced by `recipe_line_item.recipe_measure_id` and
/// `week_recipe_line_override.recipe_measure_id`).
@immutable
class RecipeMeasure {
  const RecipeMeasure({
    required this.id,
    required this.recipeId,
    required this.label,
    required this.perBatch,
    this.sortOrder = 0,
  });

  final String id;

  /// The recipe this word belongs to. A measure is a word for ONE recipe the
  /// way an ingredient measure is a word for one row — `blob` on the aioli
  /// says nothing about the ragù.
  final String recipeId;

  /// The household's word, singular, exactly as they typed it: `blob`,
  /// `ladle`, `patty`, `loaf`. Never pluralised for display and never
  /// case-folded — see `recipe_measure_authoring.dart`.
  final String label;

  /// How many of [label] one batch makes (`per_batch`). Must be finite and
  /// positive to say anything; [saysAShare] is the guard every reader asks.
  final double perBatch;

  final int sortOrder;

  /// Whether this row can say what a share of a batch is.
  ///
  /// False for a non-positive or NaN [perBatch] — bad data that dividing by
  /// would fabricate a number out of (invariant 3). A reader treats such a row
  /// as a word it has not got rather than as a division it can do.
  bool get saysAShare => perBatch.isFinite && perBatch > 0;

  /// The batches [quantity] of this measure comes to — `3 blob` of a batch
  /// that makes 20 is `0.15`. Null when the row [saysAShare] is false.
  double? batchesFor(double quantity) =>
      saysAShare ? quantity / perBatch : null;

  RecipeMeasure copyWith({
    String? id,
    String? recipeId,
    String? label,
    double? perBatch,
    int? sortOrder,
  }) => RecipeMeasure(
    id: id ?? this.id,
    recipeId: recipeId ?? this.recipeId,
    label: label ?? this.label,
    perBatch: perBatch ?? this.perBatch,
    sortOrder: sortOrder ?? this.sortOrder,
  );

  @override
  bool operator ==(Object other) =>
      other is RecipeMeasure &&
      other.id == id &&
      other.recipeId == recipeId &&
      other.label == label &&
      other.perBatch == perBatch &&
      other.sortOrder == sortOrder;

  @override
  int get hashCode => Object.hash(id, recipeId, label, perBatch, sortOrder);

  @override
  String toString() => 'RecipeMeasure(a batch makes $perBatch $label)';
}

/// The live measure of [measures] whose [RecipeMeasure.id] is [id], or null —
/// the lookup every resolution goes through, so "the word this line says is
/// gone" is decided in one place.
///
/// A row that does not [RecipeMeasure.saysAShare] is not found: it names a
/// word, but it cannot turn a number into a share of a batch, which is the
/// only thing a caller is here for.
RecipeMeasure? recipeMeasureById(String id, List<RecipeMeasure> measures) {
  for (final m in measures) {
    if (m.id == id && m.saysAShare) return m;
  }
  return null;
}
