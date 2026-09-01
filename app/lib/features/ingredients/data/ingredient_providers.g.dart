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

/// One vocab row by id, or null — resolves an ingredient known only by
/// reference (the edit-top-up sheet's unit filter).

@ProviderFor(ingredientById)
const ingredientByIdProvider = IngredientByIdFamily._();

/// One vocab row by id, or null — resolves an ingredient known only by
/// reference (the edit-top-up sheet's unit filter).

final class IngredientByIdProvider
    extends
        $FunctionalProvider<
          AsyncValue<Ingredient?>,
          Ingredient?,
          FutureOr<Ingredient?>
        >
    with $FutureModifier<Ingredient?>, $FutureProvider<Ingredient?> {
  /// One vocab row by id, or null — resolves an ingredient known only by
  /// reference (the edit-top-up sheet's unit filter).
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
  $FutureProviderElement<Ingredient?> $createElement(
    $ProviderPointer pointer,
  ) => $FutureProviderElement(pointer);

  @override
  FutureOr<Ingredient?> create(Ref ref) {
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

String _$ingredientByIdHash() => r'65ff1b2441c16cf7abf6cc93ca241452155f7b67';

/// One vocab row by id, or null — resolves an ingredient known only by
/// reference (the edit-top-up sheet's unit filter).

final class IngredientByIdFamily extends $Family
    with $FunctionalFamilyOverride<FutureOr<Ingredient?>, String> {
  const IngredientByIdFamily._()
    : super(
        retry: null,
        name: r'ingredientByIdProvider',
        dependencies: null,
        $allTransitiveDependencies: null,
        isAutoDispose: true,
      );

  /// One vocab row by id, or null — resolves an ingredient known only by
  /// reference (the edit-top-up sheet's unit filter).

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

/// One ingredient's live aliases — the form's "Also known as" chips.

@ProviderFor(ingredientAliases)
const ingredientAliasesProvider = IngredientAliasesFamily._();

/// One ingredient's live aliases — the form's "Also known as" chips.

final class IngredientAliasesProvider
    extends
        $FunctionalProvider<
          AsyncValue<List<IngredientAlias>>,
          List<IngredientAlias>,
          FutureOr<List<IngredientAlias>>
        >
    with
        $FutureModifier<List<IngredientAlias>>,
        $FutureProvider<List<IngredientAlias>> {
  /// One ingredient's live aliases — the form's "Also known as" chips.
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
  $FutureProviderElement<List<IngredientAlias>> $createElement(
    $ProviderPointer pointer,
  ) => $FutureProviderElement(pointer);

  @override
  FutureOr<List<IngredientAlias>> create(Ref ref) {
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

String _$ingredientAliasesHash() => r'f5cf163b526690fca645745143d2e1fbe395767d';

/// One ingredient's live aliases — the form's "Also known as" chips.

final class IngredientAliasesFamily extends $Family
    with $FunctionalFamilyOverride<FutureOr<List<IngredientAlias>>, String> {
  const IngredientAliasesFamily._()
    : super(
        retry: null,
        name: r'ingredientAliasesProvider',
        dependencies: null,
        $allTransitiveDependencies: null,
        isAutoDispose: true,
      );

  /// One ingredient's live aliases — the form's "Also known as" chips.

  IngredientAliasesProvider call(String id) =>
      IngredientAliasesProvider._(argument: id, from: this);

  @override
  String toString() => r'ingredientAliasesProvider';
}
