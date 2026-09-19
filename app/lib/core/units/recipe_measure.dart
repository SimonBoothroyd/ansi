/// A recipe's own word for one of what it makes — PURE DART, no
/// `package:flutter` (enforced in CI), the sub-recipe twin of `measure.dart`.
///
/// A [RecipeMeasure] names a real-world portion of ONE recipe and pins what one
/// of them comes to: "a blob is 15 g", "a ladle is 180 ml", "a patty is 1
/// piece". The household coins the word; nothing in this app knows or cares
/// what it says.
///
/// **A named amount, exactly like an ingredient's word.** A `Measure` is
/// `label` + an amount in the ingredient's basis unit (ADR-0008); this is the
/// same fact one level up, and the only difference is where the unit comes
/// from. An ingredient HAS a basis, so its measures inherit it. A recipe has no
/// single basis — it can state what it makes in mass, volume or count, and in
/// two of those at once — so each word carries its own [RecipeMeasure.unit].
///
/// `3 blob` is therefore `45 g`, and a share of a batch is the ordinary
/// component conversion from there: through the recipe's same-family yield
/// (`makes 300 g`) it is 0.15 batches. This file answers the first half — what
/// the count comes to — and `recipes/domain/component_math.dart` runs the
/// second, in the same code that has always resolved `¼ cup`.
///
/// **It needs the recipe to say what it makes, and that is the honest cost.**
/// A word with no yield in its own family says nothing about a batch:
/// `recipe_measure_authoring.dart` refuses to mint one and sends the person to
/// MAKES, and a `makes` edited away LATER leaves every line saying the word
/// unresolved — `ComponentYieldMissing` or `ComponentFamilyMismatch`, the same
/// two refusals a unit-said line has always fallen into, never a guess.
///
/// Honesty rules (invariant 3):
///
/// - A line naming a measure the recipe no longer has is **unresolved**, not a
///   count: the word was the only place its amount lived, so `3` of a word
///   nobody can measure is not 3 pieces of the yield, and a wrong batch share
///   is worse than a missing one.
/// - A non-positive (or NaN) [RecipeMeasure.amount] says nothing about a size,
///   so it converts nothing — the same line `measure.dart` draws around a
///   non-positive basis amount. The database pins `amount > 0`; this is what
///   keeps the Dart total against a foreign or in-flight row.
/// - So does a unit that cannot measure ([kRecipeMeasureFamilies]): `batch`
///   would make the word circular and an imprecise word converts nothing.
/// - **There is no density.** A mass-said word against a volume-only yield is
///   a family mismatch, exactly as a mass-said component amount is today.
///   ADR-0008 keeps mass⇄volume to an INGREDIENT's density; a recipe is not a
///   substance and has none, so the recipe's optional second yield
///   denomination is the only bridge there is.
/// - Re-stating `makes` re-states the share, and that is the point: `blob` = 15
///   g is absolute, so a batch restated from 300 g to 600 g leaves the blob
///   alone and makes it 0.075 of the bigger batch.
/// - Scaling a parent recipe multiplies the LINE's quantity, never the
///   measure. `6 blob` is 90 g; a blob is still 15 g.
library;

import 'package:meta/meta.dart';

import 'units.dart';

/// The unit families a recipe's word may be said in: the three that measure
/// something.
///
/// `batch` is refused because "a blob is 0.05 batch" is the fraction nobody
/// thinks in, and because a word defined in batches would be circular — the
/// whole job of the word is to reach a batch. An imprecise word is refused
/// because [convert] will not carry one, so a measure said in a pinch could
/// never answer the one question it exists for.
const kRecipeMeasureFamilies = <UnitFamily>{
  UnitFamily.mass,
  UnitFamily.volume,
  UnitFamily.count,
};

/// One named measure of one recipe: `n` of it are `n × amount` of [unit].
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
    required this.amount,
    required this.unit,
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

  /// What ONE of [label] comes to, in [unit]: a blob is 15 g. Must be finite
  /// and positive to say anything; [saysAnAmount] is the guard every reader
  /// asks.
  final double amount;

  /// The unit [amount] is said in — a catalog [Unit], of one of
  /// [kRecipeMeasureFamilies]. The measure's own, because a recipe has no basis
  /// to lend it one.
  final Unit unit;

  final int sortOrder;

  /// Whether this row can say what one of the word comes to.
  ///
  /// False for a non-positive or NaN [amount], and for a [unit] outside
  /// [kRecipeMeasureFamilies] — bad data that multiplying by would fabricate a
  /// number out of (invariant 3). A reader treats such a row as a word it has
  /// not got rather than as a conversion it can do.
  bool get saysAnAmount =>
      amount.isFinite &&
      amount > 0 &&
      kRecipeMeasureFamilies.contains(unit.family);

  /// What [count] of this word comes to — `3 blob` of a 15 g blob is `45 g`.
  /// Null when the row [saysAnAmount] is false.
  ///
  /// This is the whole of the measure's arithmetic. Turning that into a share
  /// of a batch is the recipe's yield's job, and it is done by the same code
  /// that has always converted `¼ cup` — see `resolveComponentAmount`.
  Quantity? totalFor(double count) =>
      saysAnAmount ? Quantity(count * amount, unit) : null;

  RecipeMeasure copyWith({
    String? id,
    String? recipeId,
    String? label,
    double? amount,
    Unit? unit,
    int? sortOrder,
  }) => RecipeMeasure(
    id: id ?? this.id,
    recipeId: recipeId ?? this.recipeId,
    label: label ?? this.label,
    amount: amount ?? this.amount,
    unit: unit ?? this.unit,
    sortOrder: sortOrder ?? this.sortOrder,
  );

  @override
  bool operator ==(Object other) =>
      other is RecipeMeasure &&
      other.id == id &&
      other.recipeId == recipeId &&
      other.label == label &&
      other.amount == amount &&
      other.unit == unit &&
      other.sortOrder == sortOrder;

  @override
  int get hashCode => Object.hash(id, recipeId, label, amount, unit, sortOrder);

  @override
  String toString() => 'RecipeMeasure($label = $amount ${unit.id})';
}

/// The live measure of [measures] whose [RecipeMeasure.id] is [id], or null —
/// the lookup every resolution goes through, so "the word this line says is
/// gone" is decided in one place.
///
/// A row that does not [RecipeMeasure.saysAnAmount] is not found: it names a
/// word, but it cannot say what one of it comes to, which is the only thing a
/// caller is here for.
RecipeMeasure? recipeMeasureById(String id, List<RecipeMeasure> measures) {
  for (final m in measures) {
    if (m.id == id && m.saysAnAmount) return m;
  }
  return null;
}
