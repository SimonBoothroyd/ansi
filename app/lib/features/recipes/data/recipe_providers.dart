/// Riverpod wiring for the recipes data layer.
library;

import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../../core/sync/database.dart';
import '../domain/recipe_repository.dart';
import 'recipe_repository_impl.dart';

part 'recipe_providers.g.dart';

@Riverpod(keepAlive: true)
RecipeRepository recipeRepository(Ref ref) =>
    SqliteRecipeRepository(ref.watch(databaseProvider));
