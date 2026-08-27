/// Riverpod wiring for the ingredients data layer (read-only vocab in step 2).
library;

import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../../core/sync/database.dart';
import '../domain/ingredient_repository.dart';
import 'ingredient_repository_impl.dart';

part 'ingredient_providers.g.dart';

@Riverpod(keepAlive: true)
IngredientRepository ingredientRepository(Ref ref) =>
    SqliteIngredientRepository(ref.watch(databaseProvider));
