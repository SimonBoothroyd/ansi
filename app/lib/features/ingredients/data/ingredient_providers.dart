/// Riverpod wiring for the ingredients data layer.
library;

import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../../core/config/env.dart';
import '../../../core/sync/database.dart';
import '../../../core/sync/session.dart';
import '../../../core/units/measure.dart';
import '../../recipes/domain/recipe_cost.dart';
import '../domain/ingredient.dart';
import '../domain/ingredient_repository.dart';
import '../domain/measure_repository.dart';
import '../domain/price.dart';
import '../domain/price_repository.dart';
import '../domain/usda_probe.dart';
import 'ingredient_repository_impl.dart';
import 'measure_repository_impl.dart';
import 'price_repository_impl.dart';
import 'usda_probe_impl.dart';

part 'ingredient_providers.g.dart';

@Riverpod(keepAlive: true)
IngredientRepository ingredientRepository(Ref ref) =>
    SqliteIngredientRepository(
      ref.watch(databaseProvider),
      householdId: ref.watch(currentHouseholdIdProvider),
    );

@Riverpod(keepAlive: true)
MeasureRepository measureRepository(Ref ref) => SqliteMeasureRepository(
  ref.watch(databaseProvider),
  householdId: ref.watch(currentHouseholdIdProvider),
);

@Riverpod(keepAlive: true)
PriceRepository priceRepository(Ref ref) =>
    SqlitePriceRepository(ref.watch(databaseProvider));

/// The USDA probe. Talks to Supabase REST, because `usda_food` never syncs to a
/// device (ADR-0005). With no backend configured it falls back to a probe that
/// always answers "nothing", which is also what an offline device gets.
@Riverpod(keepAlive: true)
UsdaProbe usdaProbe(Ref ref) => Env.isConfigured
    ? SupabaseUsdaProbe(ref.watch(supabaseClientProvider))
    : const UnconfiguredUsdaProbe();

/// The live measures of one ingredient, `sort_order`-first — what the unit
/// pickers append as [Measure] choices (`allowedUnitChoicesFor`).
@riverpod
Stream<List<Measure>> ingredientMeasures(Ref ref, String ingredientId) =>
    ref.watch(measureRepositoryProvider).watchMeasures(ingredientId);

/// One live vocab row by id, or null. Watched, so a save or another device's
/// edit re-renders it.
@riverpod
Stream<Ingredient?> ingredientById(Ref ref, String id) =>
    ref.watch(ingredientRepositoryProvider).watchIngredient(id);

/// The whole live vocabulary, ordered by canonical name, for the manager list.
/// Watched, so a sync or another screen's edit re-renders it.
@riverpod
Stream<List<Ingredient>> vocabulary(Ref ref) =>
    ref.watch(ingredientRepositoryProvider).watchVocabulary();

/// How many rows still read `stub`, for the Ingredients shelf's count line.
@riverpod
Stream<int> stubCount(Ref ref) =>
    ref.watch(ingredientRepositoryProvider).watchStubCount();

/// How many rows the vocabulary holds, for the Library's Ingredients shelf.
@riverpod
Stream<int> vocabularyCount(Ref ref) =>
    ref.watch(ingredientRepositoryProvider).watchVocabularyCount();

/// The household's distinct live categories, for the form's category dropdown.
/// Watched.
@riverpod
Stream<List<String>> ingredientCategories(Ref ref) =>
    ref.watch(ingredientRepositoryProvider).watchCategories();

/// One ingredient's live aliases — the form's "Also known as" chips. Watched,
/// so a saved alias appears without a refresh.
@riverpod
Stream<List<IngredientAlias>> ingredientAliases(Ref ref, String id) =>
    ref.watch(ingredientRepositoryProvider).watchAliases(id);

/// Every price the household has paid for one ingredient, newest first.
/// Watched.
@riverpod
Stream<List<PriceObservation>> ingredientPrices(Ref ref, String ingredientId) =>
    ref.watch(priceRepositoryProvider).watchPrices(ingredientId);

/// The names this household's receipts have printed for one ingredient, newest
/// first, for the `On receipts` fold. Watched.
@riverpod
Stream<List<ReceiptName>> ingredientReceiptNames(
  Ref ref,
  String ingredientId,
) => ref.watch(priceRepositoryProvider).watchReceiptNames(ingredientId);

/// The store words this household has used, most recently first, for the price
/// sheet's chip row.
@riverpod
Stream<List<String>> priceStores(Ref ref) =>
    ref.watch(priceRepositoryProvider).watchStores();

/// One row's base price, or null. Watched.
@riverpod
Stream<BasePrice?> ingredientBasePrice(Ref ref, String ingredientId) =>
    ref.watch(priceRepositoryProvider).watchBasePrice(ingredientId);

/// The price every cost reads, keyed by ingredient id: the newest receipt
/// price, else the row's base price (`costPriceOf`, ADR-0017).
@riverpod
Stream<Map<String, UnitPrice>> costPriceMap(Ref ref) =>
    ref.watch(priceRepositoryProvider).watchCostPrices();

/// What every vocabulary row costs and how its amounts convert, for a surface
/// holding amounts rather than recipe lines (the Shop). Assembled from the
/// vocabulary and cost-price watches; a row the vocabulary has not synced is
/// absent.
@riverpod
Map<String, IngredientPricing> ingredientPricing(Ref ref) {
  final prices = ref.watch(costPriceMapProvider).asData?.value ?? const {};
  final rows =
      ref.watch(vocabularyProvider).asData?.value ?? const <Ingredient>[];
  return {
    for (final row in rows)
      row.id: (
        row: (
          basis: row.macrosBasis,
          densityGPerMl: row.densityGPerMl,
          pieceBasisAmount: row.pieceBasisAmount,
        ),
        price: prices[row.id],
      ),
  };
}
