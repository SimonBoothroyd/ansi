/// How an ingredient line reads: the recipe page's display grouping and the
/// import review's source-line join. Pure Dart.
///
/// Line items in one [IngredientGroup] that share an identity
/// ([LineItem.ingredientId], or [LineItem.subRecipeId] for a component) fold
/// into one [LineUses] row, in first-occurrence order. Amounts and notes are
/// joined in parallel ("2 cloves + 1 clove"), never summed.
library;

import '../../../core/units/number_format.dart';
import '../../../core/units/recipe_measure.dart';
import '../../../core/units/units.dart';
import 'recipe.dart';

/// One recipe-page row: an identity and its ordered [uses]. Amounts join with "
/// + "; empty notes are dropped.
class LineUses {
  const LineUses({required this.uses, this.ingredientId, this.subRecipeId})
    : assert(uses.length > 0, 'a display row needs at least one use');

  /// The ingredient this row names, or null for a sub-recipe component.
  final String? ingredientId;

  /// The sub-recipe this row names, or null for an ingredient row.
  final String? subRecipeId;

  /// The sibling line items in source order. The first carries the display
  /// name.
  final List<LineItem> uses;

  /// Whether this row names a sub-recipe rather than an ingredient.
  bool get isComponent => subRecipeId != null;

  /// The ingredient's display name — taken from the first use.
  String get ingredientName => uses.first.ingredientName;

  /// Whether this identity was mentioned more than once in the group.
  bool get isMultiUse => uses.length > 1;

  /// The non-empty notes of each use, in order.
  List<String> get notes => [
    for (final u in uses)
      if (u.note != null && u.note!.trim().isNotEmpty) u.note!.trim(),
  ];
}

/// Joins an imported line's printed amount and ingredient text into one "from
/// source" string, eliding a measure word both sides print: `2–3 cloves` +
/// `garlic cloves, sliced` reads "2–3 garlic cloves, sliced".
///
/// The word is dropped from the amount side, so the ingredient text survives
/// verbatim. The comparison is case- and plural-insensitive, looks only at the
/// ingredient text's leading phrase (up to the first comma or bracket), and
/// elides whole trailing words of the amount once.
String joinSourceLine(String rawAmount, String ingredientText) {
  final amount = rawAmount.trim();
  final text = ingredientText.trim();
  if (amount.isEmpty || text.isEmpty) {
    return [amount, text].where((s) => s.isNotEmpty).join(' ');
  }

  final amountWords = amount.split(RegExp(r'\s+'));
  final lead = [
    for (final w in text.split(RegExp(r'[,;(\[]')).first.split(RegExp(r'\s+')))
      _displayWordKey(w),
  ];
  for (var k = amountWords.length; k > 0; k--) {
    final tail = [
      for (final w in amountWords.sublist(amountWords.length - k))
        _displayWordKey(w),
    ];
    if (tail.any((w) => w.isEmpty)) continue;
    if (!_containsRun(lead, tail)) continue;
    final kept = amountWords.sublist(0, amountWords.length - k).join(' ');
    return kept.isEmpty ? text : '$kept $text';
  }
  return '$amount $text';
}

/// A word's comparison key: lowercase, letters and digits only, a simple `s`
/// plural dropped from words long enough to have one.
String _displayWordKey(String word) {
  final bare = word.toLowerCase().replaceAll(RegExp('[^a-z0-9]'), '');
  if (bare.length >= 4 && bare.endsWith('s')) {
    return bare.substring(0, bare.length - 1);
  }
  return bare;
}

/// Whether [run] appears as a contiguous subsequence of [words].
bool _containsRun(List<String> words, List<String> run) {
  if (run.isEmpty || run.length > words.length) return false;
  for (var i = 0; i + run.length <= words.length; i++) {
    var hit = true;
    for (var j = 0; j < run.length; j++) {
      if (words[i + j] != run[j]) {
        hit = false;
        break;
      }
    }
    if (hit) return true;
  }
  return false;
}

/// Folds [items] into display rows, one per identity, in first-occurrence
/// order. A line with neither identity (foreign data; the DB forbids it) gets
/// its own row keyed by line id.
List<LineUses> groupLineUses(List<LineItem> items) {
  final order = <String>[];
  final byKey = <String, List<LineItem>>{};
  for (final item in items) {
    final key = item.ingredientId ?? 'sub:${item.subRecipeId ?? item.id}';
    byKey
        .putIfAbsent(key, () {
          order.add(key);
          return <LineItem>[];
        })
        .add(item);
  }
  return [
    for (final key in order)
      LineUses(
        ingredientId: byKey[key]!.first.ingredientId,
        subRecipeId: byKey[key]!.first.subRecipeId,
        uses: byKey[key]!,
      ),
  ];
}

/// One line's amount string: a count shows its number ("6"), a measure or
/// mass/volume unit "2 tin" / "400 g", an imprecise unit its label, a
/// numberless line the unit alone. The week's variant and the shopping list
/// quote it too.
String amountOfLine(LineItem item) {
  final measure = item.measure;
  if (measure != null) {
    return measuredAmountText(item.quantity, measure.label);
  }
  final word = recipeMeasureOfLine(item);
  if (word != null) return measuredAmountText(item.quantity, word.label);
  final unit = item.unit;
  // A component line whose word has gone keeps its number and prints no
  // denomination.
  if (unit == null) {
    final q = item.quantity;
    return q == null ? '' : formatAmount(q);
  }
  final qty = item.quantity == null ? '' : formatAmountIn(item.quantity!, unit);
  if (unit.family == UnitFamily.count) {
    return qty.isEmpty ? unit.label : qty;
  }
  if (qty.isEmpty) return unit.label;
  return '$qty ${unit.label}';
}

/// An amount in a named word: `2 clove`, `3 blob`, or the bare word without a
/// number. Always singular: the app does not know the word's grammar.
String measuredAmountText(double? quantity, String label) {
  final counted = quantity == null ? '' : formatAmount(quantity);
  return counted.isEmpty ? label : '$counted $label';
}

/// The target recipe's measure [item] is said in, or null when it names none or
/// the target no longer has it. The measure lives on the target
/// ([SubRecipeTarget.measures]), so a re-stated word reaches every line saying
/// it.
RecipeMeasure? recipeMeasureOfLine(LineItem item) {
  final id = item.recipeMeasureId;
  if (id == null) return null;
  return recipeMeasureById(id, item.subRecipe?.measures ?? const []);
}
