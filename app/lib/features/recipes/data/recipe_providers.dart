/// Riverpod wiring for the recipes data layer.
library;

import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../../core/sync/database.dart';
import '../../../core/sync/session.dart';
import '../../../core/units/recipe_measure.dart';
import '../domain/recipe_measure_repository.dart';
import '../domain/recipe_repository.dart';
import 'recipe_measure_repository_impl.dart';
import 'recipe_repository_impl.dart';

part 'recipe_providers.g.dart';

@Riverpod(keepAlive: true)
RecipeRepository recipeRepository(Ref ref) => SqliteRecipeRepository(
  ref.watch(databaseProvider),
  householdId: ref.watch(currentHouseholdIdProvider),
);

@Riverpod(keepAlive: true)
RecipeMeasureRepository recipeMeasureRepository(Ref ref) =>
    SqliteRecipeMeasureRepository(
      ref.watch(databaseProvider),
      householdId: ref.watch(currentHouseholdIdProvider),
    );

/// The live words of one recipe, `sort_order` first — what a component's chip
/// row offers ahead of `batch` and what the recipe editor's MEASURES list
/// draws.
///
/// Watched rather than read once, for the reason an ingredient's measures are:
/// a word coined at the other door — or on the other phone — reaches this chip
/// row without anybody invalidating anything.
@riverpod
Stream<List<RecipeMeasure>> recipeMeasures(Ref ref, String recipeId) =>
    ref.watch(recipeMeasureRepositoryProvider).watchRecipeMeasures(recipeId);
