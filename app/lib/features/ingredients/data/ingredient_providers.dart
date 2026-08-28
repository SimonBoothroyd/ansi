/// Riverpod wiring for the ingredients data layer (read-only vocab in step 2;
/// measures added in step 7.6).
library;

import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../../core/sync/database.dart';
import '../../../core/units/measure.dart';
import '../domain/ingredient.dart';
import '../domain/ingredient_repository.dart';
import '../domain/measure_repository.dart';
import 'ingredient_repository_impl.dart';
import 'measure_repository_impl.dart';

part 'ingredient_providers.g.dart';

@Riverpod(keepAlive: true)
IngredientRepository ingredientRepository(Ref ref) =>
    SqliteIngredientRepository(ref.watch(databaseProvider));

@Riverpod(keepAlive: true)
MeasureRepository measureRepository(Ref ref) =>
    SqliteMeasureRepository(ref.watch(databaseProvider));

/// The live measures of one ingredient, `sort_order`-first — what the unit
/// pickers append as [Measure] choices (`allowedUnitChoicesFor`).
@riverpod
Stream<List<Measure>> ingredientMeasures(Ref ref, String ingredientId) =>
    ref.watch(measureRepositoryProvider).watchMeasures(ingredientId);

/// One vocab row by id, or null — resolves an ingredient known only by
/// reference (the edit-top-up sheet's unit filter).
@riverpod
Future<Ingredient?> ingredientById(Ref ref, String id) =>
    ref.watch(ingredientRepositoryProvider).byId(id);
