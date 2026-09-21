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

@ProviderFor(priceRepository)
const priceRepositoryProvider = PriceRepositoryProvider._();

final class PriceRepositoryProvider
    extends
        $FunctionalProvider<PriceRepository, PriceRepository, PriceRepository>
    with $Provider<PriceRepository> {
  const PriceRepositoryProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'priceRepositoryProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$priceRepositoryHash();

  @$internal
  @override
  $ProviderElement<PriceRepository> $createElement($ProviderPointer pointer) =>
      $ProviderElement(pointer);

  @override
  PriceRepository create(Ref ref) {
    return priceRepository(ref);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(PriceRepository value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<PriceRepository>(value),
    );
  }
}

String _$priceRepositoryHash() => r'eaaa255eaff7a96d4f1a63473bad4b33aa8989b4';

/// The USDA probe. Talks to Supabase REST, because `usda_food` never syncs to a
/// device (ADR-0005). With no backend configured it falls back to a probe that
/// always answers "nothing", which is also what an offline device gets.

@ProviderFor(usdaProbe)
const usdaProbeProvider = UsdaProbeProvider._();

/// The USDA probe. Talks to Supabase REST, because `usda_food` never syncs to a
/// device (ADR-0005). With no backend configured it falls back to a probe that
/// always answers "nothing", which is also what an offline device gets.

final class UsdaProbeProvider
    extends $FunctionalProvider<UsdaProbe, UsdaProbe, UsdaProbe>
    with $Provider<UsdaProbe> {
  /// The USDA probe. Talks to Supabase REST, because `usda_food` never syncs to a
  /// device (ADR-0005). With no backend configured it falls back to a probe that
  /// always answers "nothing", which is also what an offline device gets.
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

/// One live vocab row by id, or null. Watched, so a save or another device's
/// edit re-renders it.

@ProviderFor(ingredientById)
const ingredientByIdProvider = IngredientByIdFamily._();

/// One live vocab row by id, or null. Watched, so a save or another device's
/// edit re-renders it.

final class IngredientByIdProvider
    extends
        $FunctionalProvider<
          AsyncValue<Ingredient?>,
          Ingredient?,
          Stream<Ingredient?>
        >
    with $FutureModifier<Ingredient?>, $StreamProvider<Ingredient?> {
  /// One live vocab row by id, or null. Watched, so a save or another device's
  /// edit re-renders it.
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

/// One live vocab row by id, or null. Watched, so a save or another device's
/// edit re-renders it.

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

  /// One live vocab row by id, or null. Watched, so a save or another device's
  /// edit re-renders it.

  IngredientByIdProvider call(String id) =>
      IngredientByIdProvider._(argument: id, from: this);

  @override
  String toString() => r'ingredientByIdProvider';
}

/// The whole live vocabulary, ordered by canonical name, for the manager list.
/// Watched, so a sync or another screen's edit re-renders it.

@ProviderFor(vocabulary)
const vocabularyProvider = VocabularyProvider._();

/// The whole live vocabulary, ordered by canonical name, for the manager list.
/// Watched, so a sync or another screen's edit re-renders it.

final class VocabularyProvider
    extends
        $FunctionalProvider<
          AsyncValue<List<Ingredient>>,
          List<Ingredient>,
          Stream<List<Ingredient>>
        >
    with $FutureModifier<List<Ingredient>>, $StreamProvider<List<Ingredient>> {
  /// The whole live vocabulary, ordered by canonical name, for the manager list.
  /// Watched, so a sync or another screen's edit re-renders it.
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

/// How many rows still read `stub`, for the Ingredients shelf's count line.

@ProviderFor(stubCount)
const stubCountProvider = StubCountProvider._();

/// How many rows still read `stub`, for the Ingredients shelf's count line.

final class StubCountProvider
    extends $FunctionalProvider<AsyncValue<int>, int, Stream<int>>
    with $FutureModifier<int>, $StreamProvider<int> {
  /// How many rows still read `stub`, for the Ingredients shelf's count line.
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

/// How many rows the vocabulary holds, for the Library's Ingredients shelf.

@ProviderFor(vocabularyCount)
const vocabularyCountProvider = VocabularyCountProvider._();

/// How many rows the vocabulary holds, for the Library's Ingredients shelf.

final class VocabularyCountProvider
    extends $FunctionalProvider<AsyncValue<int>, int, Stream<int>>
    with $FutureModifier<int>, $StreamProvider<int> {
  /// How many rows the vocabulary holds, for the Library's Ingredients shelf.
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

/// The household's distinct live categories, for the form's category dropdown.
/// Watched.

@ProviderFor(ingredientCategories)
const ingredientCategoriesProvider = IngredientCategoriesProvider._();

/// The household's distinct live categories, for the form's category dropdown.
/// Watched.

final class IngredientCategoriesProvider
    extends
        $FunctionalProvider<
          AsyncValue<List<String>>,
          List<String>,
          Stream<List<String>>
        >
    with $FutureModifier<List<String>>, $StreamProvider<List<String>> {
  /// The household's distinct live categories, for the form's category dropdown.
  /// Watched.
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

/// Every price the household has paid for one ingredient, newest first.
/// Watched.

@ProviderFor(ingredientPrices)
const ingredientPricesProvider = IngredientPricesFamily._();

/// Every price the household has paid for one ingredient, newest first.
/// Watched.

final class IngredientPricesProvider
    extends
        $FunctionalProvider<
          AsyncValue<List<PriceObservation>>,
          List<PriceObservation>,
          Stream<List<PriceObservation>>
        >
    with
        $FutureModifier<List<PriceObservation>>,
        $StreamProvider<List<PriceObservation>> {
  /// Every price the household has paid for one ingredient, newest first.
  /// Watched.
  const IngredientPricesProvider._({
    required IngredientPricesFamily super.from,
    required String super.argument,
  }) : super(
         retry: null,
         name: r'ingredientPricesProvider',
         isAutoDispose: true,
         dependencies: null,
         $allTransitiveDependencies: null,
       );

  @override
  String debugGetCreateSourceHash() => _$ingredientPricesHash();

  @override
  String toString() {
    return r'ingredientPricesProvider'
        ''
        '($argument)';
  }

  @$internal
  @override
  $StreamProviderElement<List<PriceObservation>> $createElement(
    $ProviderPointer pointer,
  ) => $StreamProviderElement(pointer);

  @override
  Stream<List<PriceObservation>> create(Ref ref) {
    final argument = this.argument as String;
    return ingredientPrices(ref, argument);
  }

  @override
  bool operator ==(Object other) {
    return other is IngredientPricesProvider && other.argument == argument;
  }

  @override
  int get hashCode {
    return argument.hashCode;
  }
}

String _$ingredientPricesHash() => r'94ea033d5fbbbe670774964ae6de0efc21d092f4';

/// Every price the household has paid for one ingredient, newest first.
/// Watched.

final class IngredientPricesFamily extends $Family
    with $FunctionalFamilyOverride<Stream<List<PriceObservation>>, String> {
  const IngredientPricesFamily._()
    : super(
        retry: null,
        name: r'ingredientPricesProvider',
        dependencies: null,
        $allTransitiveDependencies: null,
        isAutoDispose: true,
      );

  /// Every price the household has paid for one ingredient, newest first.
  /// Watched.

  IngredientPricesProvider call(String ingredientId) =>
      IngredientPricesProvider._(argument: ingredientId, from: this);

  @override
  String toString() => r'ingredientPricesProvider';
}

/// The names this household's receipts have printed for one ingredient, newest
/// first, for the `On receipts` fold. Watched.

@ProviderFor(ingredientReceiptNames)
const ingredientReceiptNamesProvider = IngredientReceiptNamesFamily._();

/// The names this household's receipts have printed for one ingredient, newest
/// first, for the `On receipts` fold. Watched.

final class IngredientReceiptNamesProvider
    extends
        $FunctionalProvider<
          AsyncValue<List<ReceiptName>>,
          List<ReceiptName>,
          Stream<List<ReceiptName>>
        >
    with
        $FutureModifier<List<ReceiptName>>,
        $StreamProvider<List<ReceiptName>> {
  /// The names this household's receipts have printed for one ingredient, newest
  /// first, for the `On receipts` fold. Watched.
  const IngredientReceiptNamesProvider._({
    required IngredientReceiptNamesFamily super.from,
    required String super.argument,
  }) : super(
         retry: null,
         name: r'ingredientReceiptNamesProvider',
         isAutoDispose: true,
         dependencies: null,
         $allTransitiveDependencies: null,
       );

  @override
  String debugGetCreateSourceHash() => _$ingredientReceiptNamesHash();

  @override
  String toString() {
    return r'ingredientReceiptNamesProvider'
        ''
        '($argument)';
  }

  @$internal
  @override
  $StreamProviderElement<List<ReceiptName>> $createElement(
    $ProviderPointer pointer,
  ) => $StreamProviderElement(pointer);

  @override
  Stream<List<ReceiptName>> create(Ref ref) {
    final argument = this.argument as String;
    return ingredientReceiptNames(ref, argument);
  }

  @override
  bool operator ==(Object other) {
    return other is IngredientReceiptNamesProvider &&
        other.argument == argument;
  }

  @override
  int get hashCode {
    return argument.hashCode;
  }
}

String _$ingredientReceiptNamesHash() =>
    r'00b38a9c1ec16800e259c369c8155af18fcda5db';

/// The names this household's receipts have printed for one ingredient, newest
/// first, for the `On receipts` fold. Watched.

final class IngredientReceiptNamesFamily extends $Family
    with $FunctionalFamilyOverride<Stream<List<ReceiptName>>, String> {
  const IngredientReceiptNamesFamily._()
    : super(
        retry: null,
        name: r'ingredientReceiptNamesProvider',
        dependencies: null,
        $allTransitiveDependencies: null,
        isAutoDispose: true,
      );

  /// The names this household's receipts have printed for one ingredient, newest
  /// first, for the `On receipts` fold. Watched.

  IngredientReceiptNamesProvider call(String ingredientId) =>
      IngredientReceiptNamesProvider._(argument: ingredientId, from: this);

  @override
  String toString() => r'ingredientReceiptNamesProvider';
}

/// The store words this household has used, most recently first, for the price
/// sheet's chip row.

@ProviderFor(priceStores)
const priceStoresProvider = PriceStoresProvider._();

/// The store words this household has used, most recently first, for the price
/// sheet's chip row.

final class PriceStoresProvider
    extends
        $FunctionalProvider<
          AsyncValue<List<String>>,
          List<String>,
          Stream<List<String>>
        >
    with $FutureModifier<List<String>>, $StreamProvider<List<String>> {
  /// The store words this household has used, most recently first, for the price
  /// sheet's chip row.
  const PriceStoresProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'priceStoresProvider',
        isAutoDispose: true,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$priceStoresHash();

  @$internal
  @override
  $StreamProviderElement<List<String>> $createElement(
    $ProviderPointer pointer,
  ) => $StreamProviderElement(pointer);

  @override
  Stream<List<String>> create(Ref ref) {
    return priceStores(ref);
  }
}

String _$priceStoresHash() => r'930835d3e6cba5b660423af2587e8216c250f134';

/// The latest price for every row the household has paid for, keyed by
/// ingredient id (ADR-0017).

@ProviderFor(latestPrices)
const latestPricesProvider = LatestPricesProvider._();

/// The latest price for every row the household has paid for, keyed by
/// ingredient id (ADR-0017).

final class LatestPricesProvider
    extends
        $FunctionalProvider<
          AsyncValue<Map<String, PriceObservation>>,
          Map<String, PriceObservation>,
          Stream<Map<String, PriceObservation>>
        >
    with
        $FutureModifier<Map<String, PriceObservation>>,
        $StreamProvider<Map<String, PriceObservation>> {
  /// The latest price for every row the household has paid for, keyed by
  /// ingredient id (ADR-0017).
  const LatestPricesProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'latestPricesProvider',
        isAutoDispose: true,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$latestPricesHash();

  @$internal
  @override
  $StreamProviderElement<Map<String, PriceObservation>> $createElement(
    $ProviderPointer pointer,
  ) => $StreamProviderElement(pointer);

  @override
  Stream<Map<String, PriceObservation>> create(Ref ref) {
    return latestPrices(ref);
  }
}

String _$latestPricesHash() => r'7255ce50a4f7032725a7fee5d576ee3d5de08d57';

/// What every vocabulary row costs and how its amounts convert, for a surface
/// holding amounts rather than recipe lines (the Shop). Assembled from the
/// vocabulary and latest-price watches; a row the vocabulary has not synced is
/// absent.

@ProviderFor(ingredientPricing)
const ingredientPricingProvider = IngredientPricingProvider._();

/// What every vocabulary row costs and how its amounts convert, for a surface
/// holding amounts rather than recipe lines (the Shop). Assembled from the
/// vocabulary and latest-price watches; a row the vocabulary has not synced is
/// absent.

final class IngredientPricingProvider
    extends
        $FunctionalProvider<
          Map<String, IngredientPricing>,
          Map<String, IngredientPricing>,
          Map<String, IngredientPricing>
        >
    with $Provider<Map<String, IngredientPricing>> {
  /// What every vocabulary row costs and how its amounts convert, for a surface
  /// holding amounts rather than recipe lines (the Shop). Assembled from the
  /// vocabulary and latest-price watches; a row the vocabulary has not synced is
  /// absent.
  const IngredientPricingProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'ingredientPricingProvider',
        isAutoDispose: true,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$ingredientPricingHash();

  @$internal
  @override
  $ProviderElement<Map<String, IngredientPricing>> $createElement(
    $ProviderPointer pointer,
  ) => $ProviderElement(pointer);

  @override
  Map<String, IngredientPricing> create(Ref ref) {
    return ingredientPricing(ref);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(Map<String, IngredientPricing> value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<Map<String, IngredientPricing>>(
        value,
      ),
    );
  }
}

String _$ingredientPricingHash() => r'0be8ce3ac475cc87462efef01804a21a4c2abdaf';
