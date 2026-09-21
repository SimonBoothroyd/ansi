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

/// The live measures of one recipe, `sort_order` first. Watched, so a word
/// coined at the other door or on another phone reaches the chip row.

@ProviderFor(recipeMeasures)
const recipeMeasuresProvider = RecipeMeasuresFamily._();

/// The live measures of one recipe, `sort_order` first. Watched, so a word
/// coined at the other door or on another phone reaches the chip row.

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
  /// The live measures of one recipe, `sort_order` first. Watched, so a word
  /// coined at the other door or on another phone reaches the chip row.
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

/// The live measures of one recipe, `sort_order` first. Watched, so a word
/// coined at the other door or on another phone reaches the chip row.

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

  /// The live measures of one recipe, `sort_order` first. Watched, so a word
  /// coined at the other door or on another phone reaches the chip row.

  RecipeMeasuresProvider call(String recipeId) =>
      RecipeMeasuresProvider._(argument: recipeId, from: this);

  @override
  String toString() => r'recipeMeasuresProvider';
}
