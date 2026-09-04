/// Riverpod wiring for the ingredients data layer (read-only vocab in step 2;
/// measures added in step 7.6).
library;

import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../../core/config/env.dart';
import '../../../core/sync/database.dart';
import '../../../core/sync/session.dart';
import '../../../core/units/measure.dart';
import '../domain/ingredient.dart';
import '../domain/ingredient_repository.dart';
import '../domain/measure_repository.dart';
import '../domain/usda_probe.dart';
import 'ingredient_repository_impl.dart';
import 'measure_repository_impl.dart';
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

/// The D7b USDA probe. Talks to Supabase REST rather than the local SQLite —
/// the one ingredient read that must, because `usda_food` never syncs to a
/// device (ADR-0005). Falls back to a probe that always answers "nothing"
/// where no backend is configured, which is the same answer an offline device
/// gets, so nothing downstream needs a second code path.
@Riverpod(keepAlive: true)
UsdaProbe usdaProbe(Ref ref) => Env.isConfigured
    ? SupabaseUsdaProbe(ref.watch(supabaseClientProvider))
    : const UnconfiguredUsdaProbe();

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

/// The whole live vocabulary, canonical-name ordered — the manager list
/// (step 8.5). Watched, so a sync or another screen's edit re-renders it.
@riverpod
Stream<List<Ingredient>> vocabulary(Ref ref) =>
    ref.watch(ingredientRepositoryProvider).watchVocabulary();

/// How many rows still read `stub` — the Library menu's badge, so the
/// fleshing-out queue is discoverable without hunting for it (D8).
@riverpod
Stream<int> stubCount(Ref ref) =>
    ref.watch(ingredientRepositoryProvider).watchStubCount();

/// How many rows the vocabulary holds, for the Library's Ingredients card
/// (0028 E5) — the shelf says what is on it, as a book card does.
@riverpod
Stream<int> vocabularyCount(Ref ref) =>
    ref.watch(ingredientRepositoryProvider).watchVocabularyCount();

/// The household's distinct live categories — the flesh-out form's category
/// dropdown (F3). Watched: a category coined on one row is offered on the
/// next without a refresh.
@riverpod
Stream<List<String>> ingredientCategories(Ref ref) =>
    ref.watch(ingredientRepositoryProvider).watchCategories();

/// One ingredient's live aliases — the form's "Also known as" chips.
@riverpod
Future<List<IngredientAlias>> ingredientAliases(Ref ref, String id) =>
    ref.watch(ingredientRepositoryProvider).aliases(id);
