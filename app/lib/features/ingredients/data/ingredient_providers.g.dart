// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'ingredient_providers.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning

@ProviderFor(ingredientRepository)
const ingredientRepositoryProvider = IngredientRepositoryProvider._();

final class IngredientRepositoryProvider
    extends
        $FunctionalProvider<
          IngredientRepository,
          IngredientRepository,
          IngredientRepository
        >
    with $Provider<IngredientRepository> {
  const IngredientRepositoryProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'ingredientRepositoryProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$ingredientRepositoryHash();

  @$internal
  @override
  $ProviderElement<IngredientRepository> $createElement(
    $ProviderPointer pointer,
  ) => $ProviderElement(pointer);

  @override
  IngredientRepository create(Ref ref) {
    return ingredientRepository(ref);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(IngredientRepository value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<IngredientRepository>(value),
    );
  }
}

String _$ingredientRepositoryHash() =>
    r'6ec104f1657ed7cd7d01a390e09c88326da7825c';

@ProviderFor(measureRepository)
const measureRepositoryProvider = MeasureRepositoryProvider._();

final class MeasureRepositoryProvider
    extends
        $FunctionalProvider<
          MeasureRepository,
          MeasureRepository,
          MeasureRepository
        >
    with $Provider<MeasureRepository> {
  const MeasureRepositoryProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'measureRepositoryProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$measureRepositoryHash();

  @$internal
  @override
  $ProviderElement<MeasureRepository> $createElement(
    $ProviderPointer pointer,
  ) => $ProviderElement(pointer);

  @override
  MeasureRepository create(Ref ref) {
    return measureRepository(ref);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(MeasureRepository value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<MeasureRepository>(value),
    );
  }
}

String _$measureRepositoryHash() => r'808d26e7592bdca5737829dc22181cadd9e2b349';

/// The D7b USDA probe. Talks to Supabase REST rather than the local SQLite —
/// the one ingredient read that must, because `usda_food` never syncs to a
/// device (ADR-0005). Falls back to a probe that always answers "nothing"
/// where no backend is configured, which is the same answer an offline device
/// gets, so nothing downstream needs a second code path.

@ProviderFor(usdaProbe)
const usdaProbeProvider = UsdaProbeProvider._();

/// The D7b USDA probe. Talks to Supabase REST rather than the local SQLite —
/// the one ingredient read that must, because `usda_food` never syncs to a
/// device (ADR-0005). Falls back to a probe that always answers "nothing"
/// where no backend is configured, which is the same answer an offline device
/// gets, so nothing downstream needs a second code path.

final class UsdaProbeProvider
    extends $FunctionalProvider<UsdaProbe, UsdaProbe, UsdaProbe>
    with $Provider<UsdaProbe> {
  /// The D7b USDA probe. Talks to Supabase REST rather than the local SQLite —
  /// the one ingredient read that must, because `usda_food` never syncs to a
  /// device (ADR-0005). Falls back to a probe that always answers "nothing"
  /// where no backend is configured, which is the same answer an offline device
  /// gets, so nothing downstream needs a second code path.
  const UsdaProbeProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'usdaProbeProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$usdaProbeHash();

  @$internal
  @override
  $ProviderElement<UsdaProbe> $createElement($ProviderPointer pointer) =>
      $ProviderElement(pointer);

  @override
  UsdaProbe create(Ref ref) {
    return usdaProbe(ref);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(UsdaProbe value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<UsdaProbe>(value),
    );
  }
}

String _$usdaProbeHash() => r'cc0ecc2959b7f0bbb92c22fab0e13f1a9f4ba96a';

/// The live measures of one ingredient, `sort_order`-first — what the unit
/// pickers append as [Measure] choices (`allowedUnitChoicesFor`).

@ProviderFor(ingredientMeasures)
const ingredientMeasuresProvider = IngredientMeasuresFamily._();

/// The live measures of one ingredient, `sort_order`-first — what the unit
/// pickers append as [Measure] choices (`allowedUnitChoicesFor`).

final class IngredientMeasuresProvider
    extends
        $FunctionalProvider<
          AsyncValue<List<Measure>>,
          List<Measure>,
          Stream<List<Measure>>
        >
    with $FutureModifier<List<Measure>>, $StreamProvider<List<Measure>> {
  /// The live measures of one ingredient, `sort_order`-first — what the unit
  /// pickers append as [Measure] choices (`allowedUnitChoicesFor`).
  const IngredientMeasuresProvider._({
    required IngredientMeasuresFamily super.from,
    required String super.argument,
  }) : super(
         retry: null,
         name: r'ingredientMeasuresProvider',
         isAutoDispose: true,
         dependencies: null,
         $allTransitiveDependencies: null,
       );

  @override
  String debugGetCreateSourceHash() => _$ingredientMeasuresHash();

  @override
  String toString() {
    return r'ingredientMeasuresProvider'
        ''
        '($argument)';
  }

  @$internal
  @override
  $StreamProviderElement<List<Measure>> $createElement(
    $ProviderPointer pointer,
  ) => $StreamProviderElement(pointer);

  @override
  Stream<List<Measure>> create(Ref ref) {
    final argument = this.argument as String;
    return ingredientMeasures(ref, argument);
  }

  @override
  bool operator ==(Object other) {
    return other is IngredientMeasuresProvider && other.argument == argument;
  }

  @override
  int get hashCode {
    return argument.hashCode;
  }
}

String _$ingredientMeasuresHash() =>
    r'e2f91b1c3b694956adb03b43cda7be9e4a8d65df';

/// The live measures of one ingredient, `sort_order`-first — what the unit
/// pickers append as [Measure] choices (`allowedUnitChoicesFor`).

final class IngredientMeasuresFamily extends $Family
    with $FunctionalFamilyOverride<Stream<List<Measure>>, String> {
  const IngredientMeasuresFamily._()
    : super(
        retry: null,
        name: r'ingredientMeasuresProvider',
        dependencies: null,
        $allTransitiveDependencies: null,
        isAutoDispose: true,
      );

  /// The live measures of one ingredient, `sort_order`-first — what the unit
  /// pickers append as [Measure] choices (`allowedUnitChoicesFor`).

  IngredientMeasuresProvider call(String ingredientId) =>
      IngredientMeasuresProvider._(argument: ingredientId, from: this);

  @override
  String toString() => r'ingredientMeasuresProvider';
}

/// One live vocab row by id, or null — resolves an ingredient known only by
/// reference (the edit-top-up sheet's unit filter) and keeps the form on the
/// row it is editing. Watched: a save re-renders it, and so does another
/// device's edit, without anyone invalidating it by hand.

@ProviderFor(ingredientById)
const ingredientByIdProvider = IngredientByIdFamily._();

/// One live vocab row by id, or null — resolves an ingredient known only by
/// reference (the edit-top-up sheet's unit filter) and keeps the form on the
/// row it is editing. Watched: a save re-renders it, and so does another
/// device's edit, without anyone invalidating it by hand.

final class IngredientByIdProvider
    extends
        $FunctionalProvider<
          AsyncValue<Ingredient?>,
          Ingredient?,
          Stream<Ingredient?>
        >
    with $FutureModifier<Ingredient?>, $StreamProvider<Ingredient?> {
  /// One live vocab row by id, or null — resolves an ingredient known only by
  /// reference (the edit-top-up sheet's unit filter) and keeps the form on the
  /// row it is editing. Watched: a save re-renders it, and so does another
  /// device's edit, without anyone invalidating it by hand.
  const IngredientByIdProvider._({
    required IngredientByIdFamily super.from,
    required String super.argument,
  }) : super(
         retry: null,
         name: r'ingredientByIdProvider',
         isAutoDispose: true,
         dependencies: null,
         $allTransitiveDependencies: null,
       );

  @override
  String debugGetCreateSourceHash() => _$ingredientByIdHash();

  @override
  String toString() {
    return r'ingredientByIdProvider'
        ''
        '($argument)';
  }

  @$internal
  @override
  $StreamProviderElement<Ingredient?> $createElement(
    $ProviderPointer pointer,
  ) => $StreamProviderElement(pointer);

  @override
  Stream<Ingredient?> create(Ref ref) {
    final argument = this.argument as String;
    return ingredientById(ref, argument);
  }

  @override
  bool operator ==(Object other) {
    return other is IngredientByIdProvider && other.argument == argument;
  }

  @override
  int get hashCode {
    return argument.hashCode;
  }
}

String _$ingredientByIdHash() => r'0223ffcdca1d5872f58038ca2ea9f7bfcc83fdaa';

/// One live vocab row by id, or null — resolves an ingredient known only by
/// reference (the edit-top-up sheet's unit filter) and keeps the form on the
/// row it is editing. Watched: a save re-renders it, and so does another
/// device's edit, without anyone invalidating it by hand.

final class IngredientByIdFamily extends $Family
    with $FunctionalFamilyOverride<Stream<Ingredient?>, String> {
  const IngredientByIdFamily._()
    : super(
        retry: null,
        name: r'ingredientByIdProvider',
        dependencies: null,
        $allTransitiveDependencies: null,
        isAutoDispose: true,
      );

  /// One live vocab row by id, or null — resolves an ingredient known only by
  /// reference (the edit-top-up sheet's unit filter) and keeps the form on the
  /// row it is editing. Watched: a save re-renders it, and so does another
  /// device's edit, without anyone invalidating it by hand.

  IngredientByIdProvider call(String id) =>
      IngredientByIdProvider._(argument: id, from: this);

  @override
  String toString() => r'ingredientByIdProvider';
}

/// The whole live vocabulary, canonical-name ordered — the manager list
/// (step 8.5). Watched, so a sync or another screen's edit re-renders it.

@ProviderFor(vocabulary)
const vocabularyProvider = VocabularyProvider._();

/// The whole live vocabulary, canonical-name ordered — the manager list
/// (step 8.5). Watched, so a sync or another screen's edit re-renders it.

final class VocabularyProvider
    extends
        $FunctionalProvider<
          AsyncValue<List<Ingredient>>,
          List<Ingredient>,
          Stream<List<Ingredient>>
        >
    with $FutureModifier<List<Ingredient>>, $StreamProvider<List<Ingredient>> {
  /// The whole live vocabulary, canonical-name ordered — the manager list
  /// (step 8.5). Watched, so a sync or another screen's edit re-renders it.
  const VocabularyProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'vocabularyProvider',
        isAutoDispose: true,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$vocabularyHash();

  @$internal
  @override
  $StreamProviderElement<List<Ingredient>> $createElement(
    $ProviderPointer pointer,
  ) => $StreamProviderElement(pointer);

  @override
  Stream<List<Ingredient>> create(Ref ref) {
    return vocabulary(ref);
  }
}

String _$vocabularyHash() => r'046e543cc9d9714ff1e38d324815ec14206b688f';

/// How many rows still read `stub` — the Library menu's badge, so the
/// fleshing-out queue is discoverable without hunting for it (D8).

@ProviderFor(stubCount)
const stubCountProvider = StubCountProvider._();

/// How many rows still read `stub` — the Library menu's badge, so the
/// fleshing-out queue is discoverable without hunting for it (D8).

final class StubCountProvider
    extends $FunctionalProvider<AsyncValue<int>, int, Stream<int>>
    with $FutureModifier<int>, $StreamProvider<int> {
  /// How many rows still read `stub` — the Library menu's badge, so the
  /// fleshing-out queue is discoverable without hunting for it (D8).
  const StubCountProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'stubCountProvider',
        isAutoDispose: true,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$stubCountHash();

  @$internal
  @override
  $StreamProviderElement<int> $createElement($ProviderPointer pointer) =>
      $StreamProviderElement(pointer);

  @override
  Stream<int> create(Ref ref) {
    return stubCount(ref);
  }
}

String _$stubCountHash() => r'3bd615a3ce89b74c3fee12845369124dd30463ca';

/// How many rows the vocabulary holds, for the Library's Ingredients card
/// (0028 E5) — the shelf says what is on it, as a book card does.

@ProviderFor(vocabularyCount)
const vocabularyCountProvider = VocabularyCountProvider._();

/// How many rows the vocabulary holds, for the Library's Ingredients card
/// (0028 E5) — the shelf says what is on it, as a book card does.

final class VocabularyCountProvider
    extends $FunctionalProvider<AsyncValue<int>, int, Stream<int>>
    with $FutureModifier<int>, $StreamProvider<int> {
  /// How many rows the vocabulary holds, for the Library's Ingredients card
  /// (0028 E5) — the shelf says what is on it, as a book card does.
  const VocabularyCountProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'vocabularyCountProvider',
        isAutoDispose: true,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$vocabularyCountHash();

  @$internal
  @override
  $StreamProviderElement<int> $createElement($ProviderPointer pointer) =>
      $StreamProviderElement(pointer);

  @override
  Stream<int> create(Ref ref) {
    return vocabularyCount(ref);
  }
}

String _$vocabularyCountHash() => r'e23a92e9cfd96bf3bb6db3cfb7208b89b79955fd';

/// The household's distinct live categories — the flesh-out form's category
/// dropdown (F3). Watched: a category coined on one row is offered on the
/// next without a refresh.

@ProviderFor(ingredientCategories)
const ingredientCategoriesProvider = IngredientCategoriesProvider._();

/// The household's distinct live categories — the flesh-out form's category
/// dropdown (F3). Watched: a category coined on one row is offered on the
/// next without a refresh.

final class IngredientCategoriesProvider
    extends
        $FunctionalProvider<
          AsyncValue<List<String>>,
          List<String>,
          Stream<List<String>>
        >
    with $FutureModifier<List<String>>, $StreamProvider<List<String>> {
  /// The household's distinct live categories — the flesh-out form's category
  /// dropdown (F3). Watched: a category coined on one row is offered on the
  /// next without a refresh.
  const IngredientCategoriesProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'ingredientCategoriesProvider',
        isAutoDispose: true,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$ingredientCategoriesHash();

  @$internal
  @override
  $StreamProviderElement<List<String>> $createElement(
    $ProviderPointer pointer,
  ) => $StreamProviderElement(pointer);

  @override
  Stream<List<String>> create(Ref ref) {
    return ingredientCategories(ref);
  }
}

String _$ingredientCategoriesHash() =>
    r'd5fe37edf976c197070b3dbeaf98d15d85cf3edb';

/// One ingredient's live aliases — the form's "Also known as" chips. Watched,
/// so a saved alias appears without a refresh.

@ProviderFor(ingredientAliases)
const ingredientAliasesProvider = IngredientAliasesFamily._();

/// One ingredient's live aliases — the form's "Also known as" chips. Watched,
/// so a saved alias appears without a refresh.

final class IngredientAliasesProvider
    extends
        $FunctionalProvider<
          AsyncValue<List<IngredientAlias>>,
          List<IngredientAlias>,
          Stream<List<IngredientAlias>>
        >
    with
        $FutureModifier<List<IngredientAlias>>,
        $StreamProvider<List<IngredientAlias>> {
  /// One ingredient's live aliases — the form's "Also known as" chips. Watched,
  /// so a saved alias appears without a refresh.
  const IngredientAliasesProvider._({
    required IngredientAliasesFamily super.from,
    required String super.argument,
  }) : super(
         retry: null,
         name: r'ingredientAliasesProvider',
         isAutoDispose: true,
         dependencies: null,
         $allTransitiveDependencies: null,
       );

  @override
  String debugGetCreateSourceHash() => _$ingredientAliasesHash();

  @override
  String toString() {
    return r'ingredientAliasesProvider'
        ''
        '($argument)';
  }

  @$internal
  @override
  $StreamProviderElement<List<IngredientAlias>> $createElement(
    $ProviderPointer pointer,
  ) => $StreamProviderElement(pointer);

  @override
  Stream<List<IngredientAlias>> create(Ref ref) {
    final argument = this.argument as String;
    return ingredientAliases(ref, argument);
  }

  @override
  bool operator ==(Object other) {
    return other is IngredientAliasesProvider && other.argument == argument;
  }

  @override
  int get hashCode {
    return argument.hashCode;
  }
}

String _$ingredientAliasesHash() => r'5edaba8686f515054ab9eaea747e9c135fc35c09';

/// One ingredient's live aliases — the form's "Also known as" chips. Watched,
/// so a saved alias appears without a refresh.

final class IngredientAliasesFamily extends $Family
    with $FunctionalFamilyOverride<Stream<List<IngredientAlias>>, String> {
  const IngredientAliasesFamily._()
    : super(
        retry: null,
        name: r'ingredientAliasesProvider',
        dependencies: null,
        $allTransitiveDependencies: null,
        isAutoDispose: true,
      );

  /// One ingredient's live aliases — the form's "Also known as" chips. Watched,
  /// so a saved alias appears without a refresh.

  IngredientAliasesProvider call(String id) =>
      IngredientAliasesProvider._(argument: id, from: this);

  @override
  String toString() => r'ingredientAliasesProvider';
}
