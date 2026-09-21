/// A recipe's own word for a portion of what it makes ("a blob is 15 g"): the
/// sub-recipe twin of `measure.dart`. Pure Dart. See ADR-0018.
///
/// Each word carries its own unit, because a recipe has no single basis. This
/// file says what a count of the word comes to; `component_math.dart` turns
/// that into a share of a batch through the recipe's same-family yield. There
/// is no density for a recipe, so a word with no yield in its family is
/// unresolved, never guessed.
library;

import 'package:meta/meta.dart';

import 'measure.dart' show LabelledMeasure;
import 'units.dart';

/// The unit families a recipe's word may be said in. `batch` would be circular
/// and an imprecise unit converts nothing.
const kRecipeMeasureFamilies = <UnitFamily>{
  UnitFamily.mass,
  UnitFamily.volume,
  UnitFamily.count,
};

/// One named measure of one recipe: `n` of it are `n × amount` of [unit].
///
/// [id] is the persisted `recipe_measure.id`.
@immutable
class RecipeMeasure implements LabelledMeasure {
  const RecipeMeasure({
    required this.id,
    required this.recipeId,
    required this.label,
    required this.amount,
    required this.unit,
    this.sortOrder = 0,
  });

  @override
  final String id;

  /// The recipe this word belongs to.
  final String recipeId;

  /// The household's word, singular, exactly as typed. Never pluralised or
  /// case-folded.
  @override
  final String label;

  /// What one of [label] comes to, in [unit]. Must be finite and positive; see
  /// [saysAnAmount].
  final double amount;

  /// The unit [amount] is said in: a catalog [Unit] of one of
  /// [kRecipeMeasureFamilies].
  final Unit unit;

  @override
  final int sortOrder;

  /// Whether this row can say what one of the word comes to. False for a
  /// non-positive or NaN [amount], or a [unit] outside
  /// [kRecipeMeasureFamilies]; readers treat such a row as missing.
  bool get saysAnAmount =>
      amount.isFinite &&
      amount > 0 &&
      kRecipeMeasureFamilies.contains(unit.family);

  /// What [count] of this word comes to (`3 blob` of a 15 g blob is `45 g`), or
  /// null when [saysAnAmount] is false.
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

/// The measure of [measures] whose [RecipeMeasure.id] is [id], or null. A row
/// that does not [RecipeMeasure.saysAnAmount] is not found.
RecipeMeasure? recipeMeasureById(String id, List<RecipeMeasure> measures) {
  for (final m in measures) {
    if (m.id == id && m.saysAnAmount) return m;
  }
  return null;
}
