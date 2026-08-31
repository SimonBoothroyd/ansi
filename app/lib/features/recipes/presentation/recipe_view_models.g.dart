// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'recipe_view_models.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning
/// The recipe list, newest first.

@ProviderFor(recipeList)
const recipeListProvider = RecipeListProvider._();

/// The recipe list, newest first.

final class RecipeListProvider
    extends
        $FunctionalProvider<
          AsyncValue<List<RecipeSummary>>,
          List<RecipeSummary>,
          Stream<List<RecipeSummary>>
        >
    with
        $FutureModifier<List<RecipeSummary>>,
        $StreamProvider<List<RecipeSummary>> {
  /// The recipe list, newest first.
  const RecipeListProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'recipeListProvider',
        isAutoDispose: true,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$recipeListHash();

  @$internal
  @override
  $StreamProviderElement<List<RecipeSummary>> $createElement(
    $ProviderPointer pointer,
  ) => $StreamProviderElement(pointer);

  @override
  Stream<List<RecipeSummary>> create(Ref ref) {
    return recipeList(ref);
  }
}

String _$recipeListHash() => r'8752d48a8fb470a42470380f8a15441c87e89bfb';

/// A single recipe aggregate, or null if it doesn't exist.

@ProviderFor(recipeById)
const recipeByIdProvider = RecipeByIdFamily._();

/// A single recipe aggregate, or null if it doesn't exist.

final class RecipeByIdProvider
    extends $FunctionalProvider<AsyncValue<Recipe?>, Recipe?, Stream<Recipe?>>
    with $FutureModifier<Recipe?>, $StreamProvider<Recipe?> {
  /// A single recipe aggregate, or null if it doesn't exist.
  const RecipeByIdProvider._({
    required RecipeByIdFamily super.from,
    required String super.argument,
  }) : super(
         retry: null,
         name: r'recipeByIdProvider',
         isAutoDispose: true,
         dependencies: null,
         $allTransitiveDependencies: null,
       );

  @override
  String debugGetCreateSourceHash() => _$recipeByIdHash();

  @override
  String toString() {
    return r'recipeByIdProvider'
        ''
        '($argument)';
  }

  @$internal
  @override
  $StreamProviderElement<Recipe?> $createElement($ProviderPointer pointer) =>
      $StreamProviderElement(pointer);

  @override
  Stream<Recipe?> create(Ref ref) {
    final argument = this.argument as String;
    return recipeById(ref, argument);
  }

  @override
  bool operator ==(Object other) {
    return other is RecipeByIdProvider && other.argument == argument;
  }

  @override
  int get hashCode {
    return argument.hashCode;
  }
}

String _$recipeByIdHash() => r'd738c71ee527ae36d4456a05c772a3da5d619380';

/// A single recipe aggregate, or null if it doesn't exist.

final class RecipeByIdFamily extends $Family
    with $FunctionalFamilyOverride<Stream<Recipe?>, String> {
  const RecipeByIdFamily._()
    : super(
        retry: null,
        name: r'recipeByIdProvider',
        dependencies: null,
        $allTransitiveDependencies: null,
        isAutoDispose: true,
      );

  /// A single recipe aggregate, or null if it doesn't exist.

  RecipeByIdProvider call(String id) =>
      RecipeByIdProvider._(argument: id, from: this);

  @override
  String toString() => r'recipeByIdProvider';
}

/// Resolves the vocab [Ingredient] behind an editor line item, so its unit
/// dropdown can be filtered by `allowedUnitsFor`. The repository only exposes
/// search (ADR-0004), so this searches by the denormalised name and matches on
/// id; null when the vocab row can't be resolved (the dropdown then falls back
/// to the full catalog).

@ProviderFor(lineItemIngredient)
const lineItemIngredientProvider = LineItemIngredientFamily._();

/// Resolves the vocab [Ingredient] behind an editor line item, so its unit
/// dropdown can be filtered by `allowedUnitsFor`. The repository only exposes
/// search (ADR-0004), so this searches by the denormalised name and matches on
/// id; null when the vocab row can't be resolved (the dropdown then falls back
/// to the full catalog).

final class LineItemIngredientProvider
    extends
        $FunctionalProvider<
          AsyncValue<Ingredient?>,
          Ingredient?,
          FutureOr<Ingredient?>
        >
    with $FutureModifier<Ingredient?>, $FutureProvider<Ingredient?> {
  /// Resolves the vocab [Ingredient] behind an editor line item, so its unit
  /// dropdown can be filtered by `allowedUnitsFor`. The repository only exposes
  /// search (ADR-0004), so this searches by the denormalised name and matches on
  /// id; null when the vocab row can't be resolved (the dropdown then falls back
  /// to the full catalog).
  const LineItemIngredientProvider._({
    required LineItemIngredientFamily super.from,
    required ({String ingredientId, String name}) super.argument,
  }) : super(
         retry: null,
         name: r'lineItemIngredientProvider',
         isAutoDispose: true,
         dependencies: null,
         $allTransitiveDependencies: null,
       );

  @override
  String debugGetCreateSourceHash() => _$lineItemIngredientHash();

  @override
  String toString() {
    return r'lineItemIngredientProvider'
        ''
        '$argument';
  }

  @$internal
  @override
  $FutureProviderElement<Ingredient?> $createElement(
    $ProviderPointer pointer,
  ) => $FutureProviderElement(pointer);

  @override
  FutureOr<Ingredient?> create(Ref ref) {
    final argument = this.argument as ({String ingredientId, String name});
    return lineItemIngredient(
      ref,
      ingredientId: argument.ingredientId,
      name: argument.name,
    );
  }

  @override
  bool operator ==(Object other) {
    return other is LineItemIngredientProvider && other.argument == argument;
  }

  @override
  int get hashCode {
    return argument.hashCode;
  }
}

String _$lineItemIngredientHash() =>
    r'0ae0badeabfeb2035ea5f7781c8d9d1c6e8976fa';

/// Resolves the vocab [Ingredient] behind an editor line item, so its unit
/// dropdown can be filtered by `allowedUnitsFor`. The repository only exposes
/// search (ADR-0004), so this searches by the denormalised name and matches on
/// id; null when the vocab row can't be resolved (the dropdown then falls back
/// to the full catalog).

final class LineItemIngredientFamily extends $Family
    with
        $FunctionalFamilyOverride<
          FutureOr<Ingredient?>,
          ({String ingredientId, String name})
        > {
  const LineItemIngredientFamily._()
    : super(
        retry: null,
        name: r'lineItemIngredientProvider',
        dependencies: null,
        $allTransitiveDependencies: null,
        isAutoDispose: true,
      );

  /// Resolves the vocab [Ingredient] behind an editor line item, so its unit
  /// dropdown can be filtered by `allowedUnitsFor`. The repository only exposes
  /// search (ADR-0004), so this searches by the denormalised name and matches on
  /// id; null when the vocab row can't be resolved (the dropdown then falls back
  /// to the full catalog).

  LineItemIngredientProvider call({
    required String ingredientId,
    required String name,
  }) => LineItemIngredientProvider._(
    argument: (ingredientId: ingredientId, name: name),
    from: this,
  );

  @override
  String toString() => r'lineItemIngredientProvider';
}

/// Editable recipe state. `build` loads an existing recipe (edit) or starts a
/// blank one with a fresh id and a single empty group (create).

@ProviderFor(RecipeEditor)
const recipeEditorProvider = RecipeEditorFamily._();

/// Editable recipe state. `build` loads an existing recipe (edit) or starts a
/// blank one with a fresh id and a single empty group (create).
final class RecipeEditorProvider
    extends $AsyncNotifierProvider<RecipeEditor, Recipe> {
  /// Editable recipe state. `build` loads an existing recipe (edit) or starts a
  /// blank one with a fresh id and a single empty group (create).
  const RecipeEditorProvider._({
    required RecipeEditorFamily super.from,
    required String? super.argument,
  }) : super(
         retry: null,
         name: r'recipeEditorProvider',
         isAutoDispose: true,
         dependencies: null,
         $allTransitiveDependencies: null,
       );

  @override
  String debugGetCreateSourceHash() => _$recipeEditorHash();

  @override
  String toString() {
    return r'recipeEditorProvider'
        ''
        '($argument)';
  }

  @$internal
  @override
  RecipeEditor create() => RecipeEditor();

  @override
  bool operator ==(Object other) {
    return other is RecipeEditorProvider && other.argument == argument;
  }

  @override
  int get hashCode {
    return argument.hashCode;
  }
}

String _$recipeEditorHash() => r'f574b31fff7d6e92623870141d9e4941a9108900';

/// Editable recipe state. `build` loads an existing recipe (edit) or starts a
/// blank one with a fresh id and a single empty group (create).

final class RecipeEditorFamily extends $Family
    with
        $ClassFamilyOverride<
          RecipeEditor,
          AsyncValue<Recipe>,
          Recipe,
          FutureOr<Recipe>,
          String?
        > {
  const RecipeEditorFamily._()
    : super(
        retry: null,
        name: r'recipeEditorProvider',
        dependencies: null,
        $allTransitiveDependencies: null,
        isAutoDispose: true,
      );

  /// Editable recipe state. `build` loads an existing recipe (edit) or starts a
  /// blank one with a fresh id and a single empty group (create).

  RecipeEditorProvider call(String? recipeId) =>
      RecipeEditorProvider._(argument: recipeId, from: this);

  @override
  String toString() => r'recipeEditorProvider';
}

/// Editable recipe state. `build` loads an existing recipe (edit) or starts a
/// blank one with a fresh id and a single empty group (create).

abstract class _$RecipeEditor extends $AsyncNotifier<Recipe> {
  late final _$args = ref.$arg as String?;
  String? get recipeId => _$args;

  FutureOr<Recipe> build(String? recipeId);
  @$mustCallSuper
  @override
  void runBuild() {
    final created = build(_$args);
    final ref = this.ref as $Ref<AsyncValue<Recipe>, Recipe>;
    final element =
        ref.element
            as $ClassProviderElement<
              AnyNotifier<AsyncValue<Recipe>, Recipe>,
              AsyncValue<Recipe>,
              Object?,
              Object?
            >;
    element.handleValue(ref, created);
  }
}
