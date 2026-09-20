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

/// The recipes that list [id] as a component — the "Used in · N" tab's rows
/// (step 8.6 / D9), and the same count D5's delete refusal speaks.
///
/// It re-reads whenever the recipe itself changes, which is what a link
/// written on this device (or synced in from the other one) moves.

@ProviderFor(recipeUsedIn)
const recipeUsedInProvider = RecipeUsedInFamily._();

/// The recipes that list [id] as a component — the "Used in · N" tab's rows
/// (step 8.6 / D9), and the same count D5's delete refusal speaks.
///
/// It re-reads whenever the recipe itself changes, which is what a link
/// written on this device (or synced in from the other one) moves.

final class RecipeUsedInProvider
    extends
        $FunctionalProvider<
          AsyncValue<List<RecipeUse>>,
          List<RecipeUse>,
          FutureOr<List<RecipeUse>>
        >
    with $FutureModifier<List<RecipeUse>>, $FutureProvider<List<RecipeUse>> {
  /// The recipes that list [id] as a component — the "Used in · N" tab's rows
  /// (step 8.6 / D9), and the same count D5's delete refusal speaks.
  ///
  /// It re-reads whenever the recipe itself changes, which is what a link
  /// written on this device (or synced in from the other one) moves.
  const RecipeUsedInProvider._({
    required RecipeUsedInFamily super.from,
    required String super.argument,
  }) : super(
         retry: null,
         name: r'recipeUsedInProvider',
         isAutoDispose: true,
         dependencies: null,
         $allTransitiveDependencies: null,
       );

  @override
  String debugGetCreateSourceHash() => _$recipeUsedInHash();

  @override
  String toString() {
    return r'recipeUsedInProvider'
        ''
        '($argument)';
  }

  @$internal
  @override
  $FutureProviderElement<List<RecipeUse>> $createElement(
    $ProviderPointer pointer,
  ) => $FutureProviderElement(pointer);

  @override
  FutureOr<List<RecipeUse>> create(Ref ref) {
    final argument = this.argument as String;
    return recipeUsedIn(ref, argument);
  }

  @override
  bool operator ==(Object other) {
    return other is RecipeUsedInProvider && other.argument == argument;
  }

  @override
  int get hashCode {
    return argument.hashCode;
  }
}

String _$recipeUsedInHash() => r'3e015b6121d06751810194bbdf33fffb54d48d5c';

/// The recipes that list [id] as a component — the "Used in · N" tab's rows
/// (step 8.6 / D9), and the same count D5's delete refusal speaks.
///
/// It re-reads whenever the recipe itself changes, which is what a link
/// written on this device (or synced in from the other one) moves.

final class RecipeUsedInFamily extends $Family
    with $FunctionalFamilyOverride<FutureOr<List<RecipeUse>>, String> {
  const RecipeUsedInFamily._()
    : super(
        retry: null,
        name: r'recipeUsedInProvider',
        dependencies: null,
        $allTransitiveDependencies: null,
        isAutoDispose: true,
      );

  /// The recipes that list [id] as a component — the "Used in · N" tab's rows
  /// (step 8.6 / D9), and the same count D5's delete refusal speaks.
  ///
  /// It re-reads whenever the recipe itself changes, which is what a link
  /// written on this device (or synced in from the other one) moves.

  RecipeUsedInProvider call(String id) =>
      RecipeUsedInProvider._(argument: id, from: this);

  @override
  String toString() => r'recipeUsedInProvider';
}

/// Every recipe's cost, keyed by recipe id (ADR-0017) — the Cost reading of
/// the recipe panel, and what the week's band sums.
///
/// A second stream beside [recipeList] rather than a field on it: a cost moves
/// when a receipt lands, and money never rides on a macro summary.

@ProviderFor(recipeCosts)
const recipeCostsProvider = RecipeCostsProvider._();

/// Every recipe's cost, keyed by recipe id (ADR-0017) — the Cost reading of
/// the recipe panel, and what the week's band sums.
///
/// A second stream beside [recipeList] rather than a field on it: a cost moves
/// when a receipt lands, and money never rides on a macro summary.

final class RecipeCostsProvider
    extends
        $FunctionalProvider<
          AsyncValue<Map<String, RecipeCostSummary>>,
          Map<String, RecipeCostSummary>,
          Stream<Map<String, RecipeCostSummary>>
        >
    with
        $FutureModifier<Map<String, RecipeCostSummary>>,
        $StreamProvider<Map<String, RecipeCostSummary>> {
  /// Every recipe's cost, keyed by recipe id (ADR-0017) — the Cost reading of
  /// the recipe panel, and what the week's band sums.
  ///
  /// A second stream beside [recipeList] rather than a field on it: a cost moves
  /// when a receipt lands, and money never rides on a macro summary.
  const RecipeCostsProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'recipeCostsProvider',
        isAutoDispose: true,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$recipeCostsHash();

  @$internal
  @override
  $StreamProviderElement<Map<String, RecipeCostSummary>> $createElement(
    $ProviderPointer pointer,
  ) => $StreamProviderElement(pointer);

  @override
  Stream<Map<String, RecipeCostSummary>> create(Ref ref) {
    return recipeCosts(ref);
  }
}

String _$recipeCostsHash() => r'baa798871d2fb3bbb25f9d42fb7eeede913f75be';

/// Whether the recipe page prints each ingredient line's own figures under its
/// name, beneath the panel's total.
///
/// A **reading posture**, not a household fact: it changes what one person is
/// looking at right now, so it is neither written to the recipe nor synced.
/// Keep-alive rather than per-page so the choice survives moving between
/// recipes — a reader comparing two recipes' lines should not have to switch it
/// back on — and it resets with the app, which is as long as a posture lasts.
///
/// WHICH figures it prints is [CostReading]'s answer, not this one: there is
/// one toggle and one menu item, and the lines print whatever the panel above
/// them is reading.

@ProviderFor(ShowLineFigures)
const showLineFiguresProvider = ShowLineFiguresProvider._();

/// Whether the recipe page prints each ingredient line's own figures under its
/// name, beneath the panel's total.
///
/// A **reading posture**, not a household fact: it changes what one person is
/// looking at right now, so it is neither written to the recipe nor synced.
/// Keep-alive rather than per-page so the choice survives moving between
/// recipes — a reader comparing two recipes' lines should not have to switch it
/// back on — and it resets with the app, which is as long as a posture lasts.
///
/// WHICH figures it prints is [CostReading]'s answer, not this one: there is
/// one toggle and one menu item, and the lines print whatever the panel above
/// them is reading.
final class ShowLineFiguresProvider
    extends $NotifierProvider<ShowLineFigures, bool> {
  /// Whether the recipe page prints each ingredient line's own figures under its
  /// name, beneath the panel's total.
  ///
  /// A **reading posture**, not a household fact: it changes what one person is
  /// looking at right now, so it is neither written to the recipe nor synced.
  /// Keep-alive rather than per-page so the choice survives moving between
  /// recipes — a reader comparing two recipes' lines should not have to switch it
  /// back on — and it resets with the app, which is as long as a posture lasts.
  ///
  /// WHICH figures it prints is [CostReading]'s answer, not this one: there is
  /// one toggle and one menu item, and the lines print whatever the panel above
  /// them is reading.
  const ShowLineFiguresProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'showLineFiguresProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$showLineFiguresHash();

  @$internal
  @override
  ShowLineFigures create() => ShowLineFigures();

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(bool value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<bool>(value),
    );
  }
}

String _$showLineFiguresHash() => r'f7f887cb0f269c979a96df0440b4c04f126da289';

/// Whether the recipe page prints each ingredient line's own figures under its
/// name, beneath the panel's total.
///
/// A **reading posture**, not a household fact: it changes what one person is
/// looking at right now, so it is neither written to the recipe nor synced.
/// Keep-alive rather than per-page so the choice survives moving between
/// recipes — a reader comparing two recipes' lines should not have to switch it
/// back on — and it resets with the app, which is as long as a posture lasts.
///
/// WHICH figures it prints is [CostReading]'s answer, not this one: there is
/// one toggle and one menu item, and the lines print whatever the panel above
/// them is reading.

abstract class _$ShowLineFigures extends $Notifier<bool> {
  bool build();
  @$mustCallSuper
  @override
  void runBuild() {
    final created = build();
    final ref = this.ref as $Ref<bool, bool>;
    final element =
        ref.element
            as $ClassProviderElement<
              AnyNotifier<bool, bool>,
              bool,
              Object?,
              Object?
            >;
    element.handleValue(ref, created);
  }
}

/// Whether the recipe panel reads COST rather than macros — the `Macros |
/// Cost` chip pair that closes the Ingredients tab.
///
/// The same kind of posture as [ShowLineFigures] and held the same way: for the
/// session, across recipes, written nowhere and synced to nobody. Somebody
/// pricing a week's cooking stays in Cost while they move between recipes; the
/// app forgets it when it restarts, which is as long as a posture lasts.

@ProviderFor(CostReading)
const costReadingProvider = CostReadingProvider._();

/// Whether the recipe panel reads COST rather than macros — the `Macros |
/// Cost` chip pair that closes the Ingredients tab.
///
/// The same kind of posture as [ShowLineFigures] and held the same way: for the
/// session, across recipes, written nowhere and synced to nobody. Somebody
/// pricing a week's cooking stays in Cost while they move between recipes; the
/// app forgets it when it restarts, which is as long as a posture lasts.
final class CostReadingProvider extends $NotifierProvider<CostReading, bool> {
  /// Whether the recipe panel reads COST rather than macros — the `Macros |
  /// Cost` chip pair that closes the Ingredients tab.
  ///
  /// The same kind of posture as [ShowLineFigures] and held the same way: for the
  /// session, across recipes, written nowhere and synced to nobody. Somebody
  /// pricing a week's cooking stays in Cost while they move between recipes; the
  /// app forgets it when it restarts, which is as long as a posture lasts.
  const CostReadingProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'costReadingProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$costReadingHash();

  @$internal
  @override
  CostReading create() => CostReading();

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(bool value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<bool>(value),
    );
  }
}

String _$costReadingHash() => r'b4536d0397187cc64cd4adcf839c42c40ad72e9d';

/// Whether the recipe panel reads COST rather than macros — the `Macros |
/// Cost` chip pair that closes the Ingredients tab.
///
/// The same kind of posture as [ShowLineFigures] and held the same way: for the
/// session, across recipes, written nowhere and synced to nobody. Somebody
/// pricing a week's cooking stays in Cost while they move between recipes; the
/// app forgets it when it restarts, which is as long as a posture lasts.

abstract class _$CostReading extends $Notifier<bool> {
  bool build();
  @$mustCallSuper
  @override
  void runBuild() {
    final created = build();
    final ref = this.ref as $Ref<bool, bool>;
    final element =
        ref.element
            as $ClassProviderElement<
              AnyNotifier<bool, bool>,
              bool,
              Object?,
              Object?
            >;
    element.handleValue(ref, created);
  }
}

/// Resolves the vocab [Ingredient] behind an editor line item, so its unit
/// dropdown can be filtered by [allowedUnitsFor]. The repository only exposes
/// search (ADR-0004), so this searches by the denormalised name and matches on
/// id; null when the vocab row can't be resolved (the dropdown then falls back
/// to the full catalog).

@ProviderFor(lineItemIngredient)
const lineItemIngredientProvider = LineItemIngredientFamily._();

/// Resolves the vocab [Ingredient] behind an editor line item, so its unit
/// dropdown can be filtered by [allowedUnitsFor]. The repository only exposes
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
  /// dropdown can be filtered by [allowedUnitsFor]. The repository only exposes
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
    r'4c3b527f76234a712182d22f5efadac9b0845b4d';

/// Resolves the vocab [Ingredient] behind an editor line item, so its unit
/// dropdown can be filtered by [allowedUnitsFor]. The repository only exposes
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
  /// dropdown can be filtered by [allowedUnitsFor]. The repository only exposes
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
///
/// [RecipeEditor.build]'s [initialTitle] seeds a NEW draft's title — what
/// `/recipes/new?title=…` carries from the Library's "nothing matches" state,
/// so a search for a recipe you were about to write becomes that recipe rather
/// than an empty form. It is part of the family key, so arriving with a
/// different title is a different draft.
///
/// [initialBookId] and [initialSectionId] are the same idea for the FILING
/// (0028 E3): `/recipes/new?book=…&section=…` is what a section's `＋` hands
/// over, so the recipe lands on the shelf you tapped instead of in whichever
/// book `ensureDefaultBook` returns. They key the family too — the same
/// blank form filed into two different sections is two drafts.
///
/// It `implements MethodEditing` (seam D4) — a declaration, not a refactor:
/// every member of that interface was already here, written for the step cards.
/// The import review's adapter implements the same surface, so the cards can
/// host on either screen without two of them existing. The same holds for
/// [RecipeHeaderHost]: the header form renders over this notifier here and over
/// the import controller at review.

@ProviderFor(RecipeEditor)
const recipeEditorProvider = RecipeEditorFamily._();

/// Editable recipe state. `build` loads an existing recipe (edit) or starts a
/// blank one with a fresh id and a single empty group (create).
///
/// [RecipeEditor.build]'s [initialTitle] seeds a NEW draft's title — what
/// `/recipes/new?title=…` carries from the Library's "nothing matches" state,
/// so a search for a recipe you were about to write becomes that recipe rather
/// than an empty form. It is part of the family key, so arriving with a
/// different title is a different draft.
///
/// [initialBookId] and [initialSectionId] are the same idea for the FILING
/// (0028 E3): `/recipes/new?book=…&section=…` is what a section's `＋` hands
/// over, so the recipe lands on the shelf you tapped instead of in whichever
/// book `ensureDefaultBook` returns. They key the family too — the same
/// blank form filed into two different sections is two drafts.
///
/// It `implements MethodEditing` (seam D4) — a declaration, not a refactor:
/// every member of that interface was already here, written for the step cards.
/// The import review's adapter implements the same surface, so the cards can
/// host on either screen without two of them existing. The same holds for
/// [RecipeHeaderHost]: the header form renders over this notifier here and over
/// the import controller at review.
final class RecipeEditorProvider
    extends $AsyncNotifierProvider<RecipeEditor, Recipe> {
  /// Editable recipe state. `build` loads an existing recipe (edit) or starts a
  /// blank one with a fresh id and a single empty group (create).
  ///
  /// [RecipeEditor.build]'s [initialTitle] seeds a NEW draft's title — what
  /// `/recipes/new?title=…` carries from the Library's "nothing matches" state,
  /// so a search for a recipe you were about to write becomes that recipe rather
  /// than an empty form. It is part of the family key, so arriving with a
  /// different title is a different draft.
  ///
  /// [initialBookId] and [initialSectionId] are the same idea for the FILING
  /// (0028 E3): `/recipes/new?book=…&section=…` is what a section's `＋` hands
  /// over, so the recipe lands on the shelf you tapped instead of in whichever
  /// book `ensureDefaultBook` returns. They key the family too — the same
  /// blank form filed into two different sections is two drafts.
  ///
  /// It `implements MethodEditing` (seam D4) — a declaration, not a refactor:
  /// every member of that interface was already here, written for the step cards.
  /// The import review's adapter implements the same surface, so the cards can
  /// host on either screen without two of them existing. The same holds for
  /// [RecipeHeaderHost]: the header form renders over this notifier here and over
  /// the import controller at review.
  const RecipeEditorProvider._({
    required RecipeEditorFamily super.from,
    required (
      String?, {
      String? initialTitle,
      String? initialBookId,
      String? initialSectionId,
    })
    super.argument,
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
        '$argument';
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

String _$recipeEditorHash() => r'c2120add7276ae99483db8192cbc679305413e9d';

/// Editable recipe state. `build` loads an existing recipe (edit) or starts a
/// blank one with a fresh id and a single empty group (create).
///
/// [RecipeEditor.build]'s [initialTitle] seeds a NEW draft's title — what
/// `/recipes/new?title=…` carries from the Library's "nothing matches" state,
/// so a search for a recipe you were about to write becomes that recipe rather
/// than an empty form. It is part of the family key, so arriving with a
/// different title is a different draft.
///
/// [initialBookId] and [initialSectionId] are the same idea for the FILING
/// (0028 E3): `/recipes/new?book=…&section=…` is what a section's `＋` hands
/// over, so the recipe lands on the shelf you tapped instead of in whichever
/// book `ensureDefaultBook` returns. They key the family too — the same
/// blank form filed into two different sections is two drafts.
///
/// It `implements MethodEditing` (seam D4) — a declaration, not a refactor:
/// every member of that interface was already here, written for the step cards.
/// The import review's adapter implements the same surface, so the cards can
/// host on either screen without two of them existing. The same holds for
/// [RecipeHeaderHost]: the header form renders over this notifier here and over
/// the import controller at review.

final class RecipeEditorFamily extends $Family
    with
        $ClassFamilyOverride<
          RecipeEditor,
          AsyncValue<Recipe>,
          Recipe,
          FutureOr<Recipe>,
          (
            String?, {
            String? initialTitle,
            String? initialBookId,
            String? initialSectionId,
          })
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
  ///
  /// [RecipeEditor.build]'s [initialTitle] seeds a NEW draft's title — what
  /// `/recipes/new?title=…` carries from the Library's "nothing matches" state,
  /// so a search for a recipe you were about to write becomes that recipe rather
  /// than an empty form. It is part of the family key, so arriving with a
  /// different title is a different draft.
  ///
  /// [initialBookId] and [initialSectionId] are the same idea for the FILING
  /// (0028 E3): `/recipes/new?book=…&section=…` is what a section's `＋` hands
  /// over, so the recipe lands on the shelf you tapped instead of in whichever
  /// book `ensureDefaultBook` returns. They key the family too — the same
  /// blank form filed into two different sections is two drafts.
  ///
  /// It `implements MethodEditing` (seam D4) — a declaration, not a refactor:
  /// every member of that interface was already here, written for the step cards.
  /// The import review's adapter implements the same surface, so the cards can
  /// host on either screen without two of them existing. The same holds for
  /// [RecipeHeaderHost]: the header form renders over this notifier here and over
  /// the import controller at review.

  RecipeEditorProvider call(
    String? recipeId, {
    String? initialTitle,
    String? initialBookId,
    String? initialSectionId,
  }) => RecipeEditorProvider._(
    argument: (
      recipeId,
      initialTitle: initialTitle,
      initialBookId: initialBookId,
      initialSectionId: initialSectionId,
    ),
    from: this,
  );

  @override
  String toString() => r'recipeEditorProvider';
}

/// Editable recipe state. `build` loads an existing recipe (edit) or starts a
/// blank one with a fresh id and a single empty group (create).
///
/// [RecipeEditor.build]'s [initialTitle] seeds a NEW draft's title — what
/// `/recipes/new?title=…` carries from the Library's "nothing matches" state,
/// so a search for a recipe you were about to write becomes that recipe rather
/// than an empty form. It is part of the family key, so arriving with a
/// different title is a different draft.
///
/// [initialBookId] and [initialSectionId] are the same idea for the FILING
/// (0028 E3): `/recipes/new?book=…&section=…` is what a section's `＋` hands
/// over, so the recipe lands on the shelf you tapped instead of in whichever
/// book `ensureDefaultBook` returns. They key the family too — the same
/// blank form filed into two different sections is two drafts.
///
/// It `implements MethodEditing` (seam D4) — a declaration, not a refactor:
/// every member of that interface was already here, written for the step cards.
/// The import review's adapter implements the same surface, so the cards can
/// host on either screen without two of them existing. The same holds for
/// [RecipeHeaderHost]: the header form renders over this notifier here and over
/// the import controller at review.

abstract class _$RecipeEditor extends $AsyncNotifier<Recipe> {
  late final _$args =
      ref.$arg
          as (
            String?, {
            String? initialTitle,
            String? initialBookId,
            String? initialSectionId,
          });
  String? get recipeId => _$args.$1;
  String? get initialTitle => _$args.initialTitle;
  String? get initialBookId => _$args.initialBookId;
  String? get initialSectionId => _$args.initialSectionId;

  FutureOr<Recipe> build(
    String? recipeId, {
    String? initialTitle,
    String? initialBookId,
    String? initialSectionId,
  });
  @$mustCallSuper
  @override
  void runBuild() {
    final created = build(
      _$args.$1,
      initialTitle: _$args.initialTitle,
      initialBookId: _$args.initialBookId,
      initialSectionId: _$args.initialSectionId,
    );
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
