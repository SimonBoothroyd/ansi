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
