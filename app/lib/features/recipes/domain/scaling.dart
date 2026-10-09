/// Recipe scaling. Pure Dart. Scaling never mutates the stored recipe: the UI
/// renders [scaleGroups]' result. Imprecise units ("a pinch") are left
/// untouched, as `core/units`' [scale] guarantees.
library;

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
