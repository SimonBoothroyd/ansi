/// Recipe scaling — a pure view concern.
///
/// PURE DART (invariant 2). Scaling never mutates the stored recipe: the UI
/// calls [scaleGroups] with a target serving count and renders the result,
/// while the persisted [Recipe.servingsBase] and quantities stay as written.
/// Imprecise units ("a pinch") are left untouched — invariant 3, never invent a
/// number — which `core/units`' [scale] already guarantees.
library;

import '../../../core/units/units.dart';
import 'recipe.dart';

/// The multiplier that takes [recipe] from its base to [targetServings].
double scaleFactorFor(Recipe recipe, double targetServings) =>
    targetServings / recipe.servingsBase;

/// [item] with its quantity multiplied by [factor]. A line with no number, or
/// an imprecise unit, is returned unchanged.
LineItem scaleLineItem(LineItem item, double factor) {
  final q = item.asQuantity;
  if (q == null) return item;
  final scaled = scale(q, factor);
  return item.copyWith(quantity: scaled.amount);
}

/// [recipe]'s groups with every line-item scaled to [targetServings]. Group and
/// item order is preserved; the recipe itself is not modified.
List<IngredientGroup> scaleGroups(Recipe recipe, double targetServings) {
  final factor = scaleFactorFor(recipe, targetServings);
  return [
    for (final group in recipe.groups)
      group.copyWith(
        items: [for (final item in group.items) scaleLineItem(item, factor)],
      ),
  ];
}
