/// The amount an amount sheet opens on, read for one ingredient: its live
/// measures and the last amount used at this door, through
/// [defaultAmountFor].
library;

import 'package:hooks_riverpod/hooks_riverpod.dart';

import '../../planning/data/planning_providers.dart';
import '../../shopping/data/shopping_providers.dart';
import '../data/ingredient_providers.dart';
import '../domain/default_amount.dart';
import '../domain/ingredient.dart';

/// The default for [ingredient]: [forMeal] reads the last planned meal of it,
/// otherwise its last top-up. Null when there is none, or when the reads
/// fail — the sheet then opens empty, as it always did.
Future<DefaultAmount?> usualAmountOf(
  ProviderContainer container,
  Ingredient ingredient, {
  required bool forMeal,
}) async {
  try {
    final measures = await container
        .read(measureRepositoryProvider)
        .watchMeasures(ingredient.id)
        .first;
    final last = forMeal
        ? await container
              .read(planningRepositoryProvider)
              .lastIngredientAmount(ingredient.id)
        : await container
              .read(shoppingRepositoryProvider)
              .lastTopUp(ingredient.id);
    return defaultAmountFor(ingredient, measures, last: last);
  } on Object {
    return null;
  }
}
