// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'recipe_providers.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning

@ProviderFor(recipeRepository)
const recipeRepositoryProvider = RecipeRepositoryProvider._();

final class RecipeRepositoryProvider
    extends
        $FunctionalProvider<
          RecipeRepository,
          RecipeRepository,
          RecipeRepository
        >
    with $Provider<RecipeRepository> {
  const RecipeRepositoryProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'recipeRepositoryProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$recipeRepositoryHash();

  @$internal
  @override
  $ProviderElement<RecipeRepository> $createElement($ProviderPointer pointer) =>
      $ProviderElement(pointer);

  @override
  RecipeRepository create(Ref ref) {
    return recipeRepository(ref);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(RecipeRepository value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<RecipeRepository>(value),
    );
  }
}

String _$recipeRepositoryHash() => r'92bab517c377cbf5bb8e4cbc05529e80d5110bec';

@ProviderFor(recipeMeasureRepository)
const recipeMeasureRepositoryProvider = RecipeMeasureRepositoryProvider._();

final class RecipeMeasureRepositoryProvider
    extends
        $FunctionalProvider<
          RecipeMeasureRepository,
          RecipeMeasureRepository,
          RecipeMeasureRepository
        >
    with $Provider<RecipeMeasureRepository> {
  const RecipeMeasureRepositoryProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'recipeMeasureRepositoryProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$recipeMeasureRepositoryHash();

  @$internal
  @override
  $ProviderElement<RecipeMeasureRepository> $createElement(
    $ProviderPointer pointer,
  ) => $ProviderElement(pointer);

  @override
  RecipeMeasureRepository create(Ref ref) {
    return recipeMeasureRepository(ref);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(RecipeMeasureRepository value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<RecipeMeasureRepository>(value),
    );
  }
}

String _$recipeMeasureRepositoryHash() =>
    r'50e6ab1fa9246f9063c085196de241bc80f4c05a';

/// The live words of one recipe, `sort_order` first — what a component's chip
/// row offers ahead of `batch` and what the recipe editor's MEASURES list
/// draws.
///
/// Watched rather than read once, for the reason an ingredient's measures are:
/// a word coined at the other door — or on the other phone — reaches this chip
/// row without anybody invalidating anything.

@ProviderFor(recipeMeasures)
const recipeMeasuresProvider = RecipeMeasuresFamily._();

/// The live words of one recipe, `sort_order` first — what a component's chip
/// row offers ahead of `batch` and what the recipe editor's MEASURES list
/// draws.
///
/// Watched rather than read once, for the reason an ingredient's measures are:
/// a word coined at the other door — or on the other phone — reaches this chip
/// row without anybody invalidating anything.

final class RecipeMeasuresProvider
    extends
        $FunctionalProvider<
          AsyncValue<List<RecipeMeasure>>,
          List<RecipeMeasure>,
          Stream<List<RecipeMeasure>>
        >
    with
        $FutureModifier<List<RecipeMeasure>>,
        $StreamProvider<List<RecipeMeasure>> {
  /// The live words of one recipe, `sort_order` first — what a component's chip
  /// row offers ahead of `batch` and what the recipe editor's MEASURES list
  /// draws.
  ///
  /// Watched rather than read once, for the reason an ingredient's measures are:
  /// a word coined at the other door — or on the other phone — reaches this chip
  /// row without anybody invalidating anything.
  const RecipeMeasuresProvider._({
    required RecipeMeasuresFamily super.from,
    required String super.argument,
  }) : super(
         retry: null,
         name: r'recipeMeasuresProvider',
         isAutoDispose: true,
         dependencies: null,
         $allTransitiveDependencies: null,
       );

  @override
  String debugGetCreateSourceHash() => _$recipeMeasuresHash();

  @override
  String toString() {
    return r'recipeMeasuresProvider'
        ''
        '($argument)';
  }

  @$internal
  @override
  $StreamProviderElement<List<RecipeMeasure>> $createElement(
    $ProviderPointer pointer,
  ) => $StreamProviderElement(pointer);

  @override
  Stream<List<RecipeMeasure>> create(Ref ref) {
    final argument = this.argument as String;
    return recipeMeasures(ref, argument);
  }

  @override
  bool operator ==(Object other) {
    return other is RecipeMeasuresProvider && other.argument == argument;
  }

  @override
  int get hashCode {
    return argument.hashCode;
  }
}

String _$recipeMeasuresHash() => r'a991eebcd371421e23928768b9994a11c21e2ef6';

/// The live words of one recipe, `sort_order` first — what a component's chip
/// row offers ahead of `batch` and what the recipe editor's MEASURES list
/// draws.
///
/// Watched rather than read once, for the reason an ingredient's measures are:
/// a word coined at the other door — or on the other phone — reaches this chip
/// row without anybody invalidating anything.

final class RecipeMeasuresFamily extends $Family
    with $FunctionalFamilyOverride<Stream<List<RecipeMeasure>>, String> {
  const RecipeMeasuresFamily._()
    : super(
        retry: null,
        name: r'recipeMeasuresProvider',
        dependencies: null,
        $allTransitiveDependencies: null,
        isAutoDispose: true,
      );

  /// The live words of one recipe, `sort_order` first — what a component's chip
  /// row offers ahead of `batch` and what the recipe editor's MEASURES list
  /// draws.
  ///
  /// Watched rather than read once, for the reason an ingredient's measures are:
  /// a word coined at the other door — or on the other phone — reaches this chip
  /// row without anybody invalidating anything.

  RecipeMeasuresProvider call(String recipeId) =>
      RecipeMeasuresProvider._(argument: recipeId, from: this);

  @override
  String toString() => r'recipeMeasuresProvider';
}

/// What still says one word — the count the bin's refusal speaks
/// (`recipeMeasureDeleteRefusalText`) and the door that lists the recipes.
///
/// A one-shot read taken when the bin is offered, like the ingredient
/// measures' own delete guard: the answer has to be true *now*, not as of the
/// last time a list was assembled.

@ProviderFor(recipeMeasureUsage)
const recipeMeasureUsageProvider = RecipeMeasureUsageFamily._();

/// What still says one word — the count the bin's refusal speaks
/// (`recipeMeasureDeleteRefusalText`) and the door that lists the recipes.
///
/// A one-shot read taken when the bin is offered, like the ingredient
/// measures' own delete guard: the answer has to be true *now*, not as of the
/// last time a list was assembled.

final class RecipeMeasureUsageProvider
    extends
        $FunctionalProvider<
          AsyncValue<RecipeMeasureUsage>,
          RecipeMeasureUsage,
          FutureOr<RecipeMeasureUsage>
        >
    with
        $FutureModifier<RecipeMeasureUsage>,
        $FutureProvider<RecipeMeasureUsage> {
  /// What still says one word — the count the bin's refusal speaks
  /// (`recipeMeasureDeleteRefusalText`) and the door that lists the recipes.
  ///
  /// A one-shot read taken when the bin is offered, like the ingredient
  /// measures' own delete guard: the answer has to be true *now*, not as of the
  /// last time a list was assembled.
  const RecipeMeasureUsageProvider._({
    required RecipeMeasureUsageFamily super.from,
    required String super.argument,
  }) : super(
         retry: null,
         name: r'recipeMeasureUsageProvider',
         isAutoDispose: true,
         dependencies: null,
         $allTransitiveDependencies: null,
       );

  @override
  String debugGetCreateSourceHash() => _$recipeMeasureUsageHash();

  @override
  String toString() {
    return r'recipeMeasureUsageProvider'
        ''
        '($argument)';
  }

  @$internal
  @override
  $FutureProviderElement<RecipeMeasureUsage> $createElement(
    $ProviderPointer pointer,
  ) => $FutureProviderElement(pointer);

  @override
  FutureOr<RecipeMeasureUsage> create(Ref ref) {
    final argument = this.argument as String;
    return recipeMeasureUsage(ref, argument);
  }

  @override
  bool operator ==(Object other) {
    return other is RecipeMeasureUsageProvider && other.argument == argument;
  }

  @override
  int get hashCode {
    return argument.hashCode;
  }
}

String _$recipeMeasureUsageHash() =>
    r'4a3f821857d3b126b0f914b46eed73b3cd33f29b';

/// What still says one word — the count the bin's refusal speaks
/// (`recipeMeasureDeleteRefusalText`) and the door that lists the recipes.
///
/// A one-shot read taken when the bin is offered, like the ingredient
/// measures' own delete guard: the answer has to be true *now*, not as of the
/// last time a list was assembled.

final class RecipeMeasureUsageFamily extends $Family
    with $FunctionalFamilyOverride<FutureOr<RecipeMeasureUsage>, String> {
  const RecipeMeasureUsageFamily._()
    : super(
        retry: null,
        name: r'recipeMeasureUsageProvider',
        dependencies: null,
        $allTransitiveDependencies: null,
        isAutoDispose: true,
      );

  /// What still says one word — the count the bin's refusal speaks
  /// (`recipeMeasureDeleteRefusalText`) and the door that lists the recipes.
  ///
  /// A one-shot read taken when the bin is offered, like the ingredient
  /// measures' own delete guard: the answer has to be true *now*, not as of the
  /// last time a list was assembled.

  RecipeMeasureUsageProvider call(String measureId) =>
      RecipeMeasureUsageProvider._(argument: measureId, from: this);

  @override
  String toString() => r'recipeMeasureUsageProvider';
}
