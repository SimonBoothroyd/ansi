/// Recipe scaling. Pure Dart. Scaling never mutates the stored recipe: the UI
/// renders [scaleGroups]' result. Imprecise units ("a pinch") are left
/// untouched, as `core/units`' [scale] guarantees.
library;

import '../../../core/units/number_format.dart';
import '../../../core/units/units.dart';
import 'recipe.dart';

/// The multiplier that takes [recipe] from its base to [targetServings].
double scaleFactorFor(Recipe recipe, double targetServings) =>
    targetServings / recipe.servingsBase;

/// [item] with its quantity multiplied by [factor]. A line with no number or an
/// imprecise unit is returned unchanged.
///
/// A component line said in its target's own word (`2 blob`) has no catalog
/// unit, so no [LineItem.asQuantity]; a word is a fixed amount (ADR-0018), so
/// its count scales linearly like any other.
LineItem scaleLineItem(LineItem item, double factor) {
  final q = item.asQuantity;
  if (q != null) return item.copyWith(quantity: scale(q, factor).amount);
  final count = item.quantity;
  if (count != null && item.isMeasuredComponent) {
    return item.copyWith(quantity: count * factor);
  }
  return item;
}

/// [recipe]'s groups with every line item scaled to [targetServings], order
/// preserved.
List<IngredientGroup> scaleGroups(Recipe recipe, double targetServings) {
  final factor = scaleFactorFor(recipe, targetServings);
  return [
    for (final group in recipe.groups)
      group.copyWith(
        items: [for (final item in group.items) scaleLineItem(item, factor)],
      ),
  ];
}

/// The servings a person typed into the scaler (`3`, `1 3/4`, `1¾`, `2.5`),
/// kept to quarters, or null when it is no servings at all: blank, words,
/// nothing or less than a quarter, or past a thousand.
double? servingsFromText(String text) {
  final n = parseAmount(text);
  if (n == null || !n.isFinite || n > 1000) return null;
  final quarters = (n * 4).roundToDouble() / 4;
  return quarters <= 0 ? null : quarters;
}

/// `1 serving`, `1¾ servings`: how the scaler says its number.
String servingsWord(double servings) =>
    '${formatAmount(servings)} ${servings == 1 ? 'serving' : 'servings'}';
