// The pumped ProviderScope IS the root scope of each test's tree.
// ignore_for_file: scoped_providers_should_specify_dependencies

import 'package:ansi/core/theme/ansi_theme.dart';
import 'package:ansi/core/units/macros.dart';
import 'package:ansi/core/units/measure.dart';
import 'package:ansi/core/units/units.dart';
import 'package:ansi/features/import/data/import_providers.dart';
import 'package:ansi/features/import/domain/commit_payload.dart';
import 'package:ansi/features/import/domain/import_repository.dart';
import 'package:ansi/features/import/domain/line_resolution.dart';
import 'package:ansi/features/import/domain/line_validation.dart';
import 'package:ansi/features/import/domain/reconciliation_payload.dart';
import 'package:ansi/features/import/presentation/import_view_models.dart';
import 'package:ansi/features/import/presentation/recon_line_card.dart';
import 'package:ansi/features/ingredients/data/ingredient_providers.dart';
import 'package:ansi/features/ingredients/domain/ingredient.dart';
import 'package:ansi/features/ingredients/domain/ingredient_repository.dart';
import 'package:ansi/features/ingredients/domain/measure_repository.dart';
import 'package:ansi/features/recipes/data/recipe_providers.dart';
import 'package:ansi/features/recipes/domain/recipe.dart';
import 'package:ansi/features/recipes/domain/recipe_repository.dart';
import 'package:ansi/features/recipes/presentation/recipe_chip.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:forui/forui.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

import '../../helpers/fake_ingredient_repository.dart';

/// A fake edge function returning a fixed single-line payload; commit records.
class _FakeRepo implements ImportRepository {
  _FakeRepo(this.payload);
  final ReconciliationPayload payload;
  CommitPayload? committed;

  @override
  Future<ReconciliationPayload> startImport(ImportSource source) async =>
      payload;

  @override
  Future<String> commit(CommitPayload payload) async {
    committed = payload;
    return 'recipe-1';
  }
}

/// One unmatched `none` line — the amount + notes must stay disabled until an
/// ingredient is chosen, and the "needs you" flag must clear once it is.
ReconciliationPayload _nonePayload() => const ReconciliationPayload(
  title: 'T',
  servingsBase: 2,
  groups: [
    ReconGroup(
      lines: [
        ReconLine(
          raw: RawLineItem(
            ingredientText: 'mystery spice',
            rawAmount: 'a pinch',
          ),
          band: MatchBand.none,
        ),
      ],
    ),
  ],
);

/// One auto-matched line — resolved on arrival, but (owner refinement) still
/// fully editable.
ReconciliationPayload _autoPayload() => const ReconciliationPayload(
  title: 'T',
  servingsBase: 2,
  groups: [
    ReconGroup(
      lines: [
        ReconLine(
          raw: RawLineItem(
            ingredientText: 'spaghetti',
            qty: 200,
            unit: 'g',
            rawAmount: '200g',
          ),
          band: MatchBand.auto,
          candidates: [
            MatchCandidate(
              ingredientId: 'ing-spag',
              canonicalName: 'Spaghetti',
              score: 0.98,
            ),
          ],
        ),
      ],
    ),
  ],
);

/// An auto-matched line whose amount is an unpicked RANGE — the ingredient
/// must lock regardless of the range (round-3 #4).
ReconciliationPayload _autoRangePayload() => const ReconciliationPayload(
  title: 'T',
  servingsBase: 2,
  groups: [
    ReconGroup(
      lines: [
        ReconLine(
          raw: RawLineItem(
            ingredientText: 'garlic cloves, sliced',
            qtyLow: 2,
            qtyHigh: 3,
            unit: 'clove',
            rawAmount: '2–3 cloves',
          ),
          band: MatchBand.auto,
          candidates: [
            MatchCandidate(
              ingredientId: 'ing-garlic',
              canonicalName: 'Garlic',
              score: 0.95,
            ),
          ],
        ),
      ],
    ),
  ],
);

/// A matched line whose printed unit the ingredient cannot carry (`ml` on a
/// density-less garlic) — the "pick a supported unit" case.
ReconciliationPayload _unitMismatchPayload() => const ReconciliationPayload(
  title: 'T',
  servingsBase: 2,
  groups: [
    ReconGroup(
      lines: [
        ReconLine(
          raw: RawLineItem(
            ingredientText: 'garlic',
            qty: 2,
            unit: 'ml',
            rawAmount: '2 ml',
          ),
          band: MatchBand.auto,
          candidates: [
            MatchCandidate(
              ingredientId: 'ing-garlic',
              canonicalName: 'Garlic',
              score: 0.95,
            ),
          ],
        ),
      ],
    ),
  ],
);

/// The board's frame-(e) line: a printed cross-reference the server matched
/// against a household recipe TITLE, offered beside an ingredient candidate.
ReconciliationPayload _recipeOfferPayload() => const ReconciliationPayload(
  title: 'Sausage Sliders',
  servingsBase: 8,
  groups: [
    ReconGroup(
      lines: [
        ReconLine(
          raw: RawLineItem(
            ingredientText: 'Romesco Aioli (page 38)',
            qty: 0.25,
            unit: 'cup',
            rawAmount: '¼ cup',
          ),
          band: MatchBand.suggest,
          candidates: [
            MatchCandidate(
              ingredientId: 'ing-aioli',
              canonicalName: 'Aioli, jarred',
              score: 0.7,
            ),
          ],
          recipeCandidates: [
            RecipeCandidate(
              recipeId: 'r-aioli',
              title: 'Romesco Aioli',
              score: 1,
            ),
          ],
        ),
      ],
    ),
  ],
);

const _garlic = Ingredient(
  id: 'ing-garlic',
  canonicalName: 'Garlic',
  defaultUnit: g,
  status: IngredientStatus.complete,
);

const _clove = Measure(id: 'm-clove', label: 'clove', amount: 3);

class _FakeIngredientRepo
    with IngredientManagerStubs
    implements IngredientRepository {
  @override
  Future<Ingredient?> byId(String id) async => _garlic;

  @override
  Future<Map<String, Ingredient>> byIds(Set<String> ids) async => {
    for (final id in ids) id: _garlic,
  };

  @override
  Future<List<Ingredient>> search(String query, {int limit = 30}) async =>
      const [];

  @override
  Future<List<Ingredient>> recentlyUsed({int limit = 8}) async => const [];

  @override
  Future<Ingredient> createStub(
    String name, {
    String source = 'manual',
    Macros? macros,
    MacrosBasis macrosBasis = MacrosBasis.perG,
  }) async => _garlic;

  @override
  Future<Ingredient?> setDensity(String ingredientId, double gPerMl) async =>
      null;
}

class _FakeMeasureRepo implements MeasureRepository {
  @override
  Stream<List<Measure>> watchMeasures(String ingredientId) =>
      Stream.value(const [_clove]);

  @override
  Future<Map<String, List<Measure>>> measuresByIngredients(
    Set<String> ids,
  ) async => {
    for (final id in ids) id: const [_clove],
  };

  @override
  Future<Measure> addMeasure({
    required String ingredientId,
    required String label,
    required double amount,
  }) async => _clove;

  @override
  Future<void> softDeleteMeasure(String measureId) async {}
}

/// The household's recipes, as the component sheet reads them: one aioli that
/// says what a batch makes.
class _FakeRecipeRepo implements RecipeRepository {
  @override
  Stream<List<RecipeSummary>> watchRecipes() => Stream.value(const [
    RecipeSummary(
      id: 'r-aioli',
      title: 'Romesco Aioli',
      servingsBase: 4,
      yieldQty: 1,
      yieldUnit: cup,
    ),
  ]);

  @override
  Stream<Recipe?> watchRecipe(String id) => Stream.value(null);

  @override
  Future<void> saveRecipe(Recipe recipe) async {}

  @override
  Future<void> deleteRecipe(String id) async {}

  @override
  Future<void> setFavorite(String id, bool favorite) async {}

  @override
  Future<List<RecipeUse>> usedIn(String recipeId) async => const [];

  @override
  Future<bool> componentLinkWouldCycle({
    required String recipeId,
    required String subRecipeId,
  }) async => false;
}

Widget _host(ProviderContainer container, {LineValidation? validation}) =>
    UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
        home: FTheme(
          data: ansiThemeData(),
          child: FScaffold(child: _Body(validation: validation)),
        ),
      ),
    );

/// Renders the single expandable card for line 0 of the reconciling state.
/// Watching the provider at the top keeps the (autoDispose) controller alive.
class _Body extends ConsumerWidget {
  const _Body({this.validation});

  final LineValidation? validation;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(importControllerProvider);
    if (state is! ImportReconciling) return const SizedBox.shrink();
    return ListView(
      children: [
        ReviewLineCard(
          line: state.payload.flatLines[0],
          resolution: state.resolutions.firstWhere((r) => r.lineIndex == 0),
          validation: validation,
        ),
      ],
    );
  }
}

/// The card wired to the REAL validation provider (the review screen's own
/// wiring), so the ingredient + its measures resolve exactly as on device.
class _LiveBody extends ConsumerWidget {
  const _LiveBody();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(importControllerProvider);
    if (state is! ImportReconciling) return const SizedBox.shrink();
    final byLine = ref.watch(importValidationProvider).value;
    return ListView(
      children: [
        ReviewLineCard(
          line: state.payload.flatLines[0],
          resolution: state.resolutions.firstWhere((r) => r.lineIndex == 0),
          validation: byLine?[0],
        ),
      ],
    );
  }
}

/// Forui's text field trips a semantics merge assertion under the test
/// harness (the same one the quantity-sheet tests filter) — not our concern
/// here. Suppress only that assertion.
void _filterSemanticsAssertions() {
  final reportError = FlutterError.onError!;
  FlutterError.onError = (details) {
    if ('${details.exception}'.contains('semantics.dart')) return;
    reportError(details);
  };
  addTearDown(() => FlutterError.onError = reportError);
}

void main() {
  testWidgets('an auto line is compact, then expands into the editable card '
      '(re-match + amount + notes)', (tester) async {
    final container = ProviderContainer(
      overrides: [
        importRepositoryProvider.overrideWithValue(_FakeRepo(_autoPayload())),
      ],
    );
    addTearDown(container.dispose);
    await container
        .read(importControllerProvider.notifier)
        .startImport(const ImportFromUrl('x'));

    await tester.pumpWidget(_host(container));
    await tester.pumpAndSettle();

    // Compact by default: amount + name, no editors yet.
    expect(find.text('200 g'), findsOneWidget);
    expect(find.text('Spaghetti'), findsOneWidget);
    expect(find.text('NOTES'), findsNothing);

    // Tapping the pencil expands the same line in place.
    await tester.tap(find.byIcon(FLucideIcons.pencil));
    await tester.pumpAndSettle();

    // The full editable card: re-match affordance + amount + notes.
    // (an auto line is re-matchable too)
    expect(find.text('tap to change'), findsOneWidget);
    expect(find.text('AMOUNT'), findsOneWidget);
    expect(find.text('NOTES'), findsOneWidget);
  });

  testWidgets('editing the NOTES field writes through to the resolution', (
    tester,
  ) async {
    _filterSemanticsAssertions();
    final container = ProviderContainer(
      overrides: [
        importRepositoryProvider.overrideWithValue(_FakeRepo(_autoPayload())),
      ],
    );
    addTearDown(container.dispose);
    await container
        .read(importControllerProvider.notifier)
        .startImport(const ImportFromUrl('x'));

    await tester.pumpWidget(_host(container));
    await tester.pumpAndSettle();
    await tester.tap(find.byIcon(FLucideIcons.pencil));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField), 'finely chopped');
    await tester.pumpAndSettle();

    final state = container.read(importControllerProvider) as ImportReconciling;
    final line0 = state.resolutions.firstWhere((r) => r.lineIndex == 0);
    expect(line0.notes, 'finely chopped');
  });

  testWidgets('an unmatched line disables amount + notes and shows a clear '
      '"needs you" flag that clears once matched', (tester) async {
    _filterSemanticsAssertions();
    final container = ProviderContainer(
      overrides: [
        importRepositoryProvider.overrideWithValue(_FakeRepo(_nonePayload())),
      ],
    );
    addTearDown(container.dispose);
    await container
        .read(importControllerProvider.notifier)
        .startImport(const ImportFromUrl('x'));

    await tester.pumpWidget(_host(container));
    await tester.pumpAndSettle();
    await tester.tap(find.byIcon(FLucideIcons.pencil));
    await tester.pumpAndSettle();

    // Unmatched: a clear label (not a bare dot) + the fields locked.
    expect(find.text('Match an ingredient'), findsOneWidget);
    expect(
      find.textContaining('Match an ingredient first'),
      findsOneWidget, // the unlock hint under the disabled fields
    );
    final notesField = tester.widget<TextField>(find.byType(TextField));
    expect(notesField.enabled, isFalse);

    // Match it → the flag clears and notes unlock.
    container
        .read(importControllerProvider.notifier)
        .updateResolution(0, (r) => r.resolveToNewStub('Mystery spice'));
    await tester.pumpAndSettle();

    expect(find.text('Match an ingredient'), findsNothing);
    expect(find.textContaining('Match an ingredient first'), findsNothing);
    expect(tester.widget<TextField>(find.byType(TextField)).enabled, isTrue);
  });

  testWidgets('an unresolved line renders its candidates as "did you mean" '
      'pills', (tester) async {
    String? picked;
    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          home: FTheme(
            data: ansiThemeData(),
            child: FScaffold(
              child: Resolver(
                candidates: const [
                  MatchCandidate(
                    ingredientId: 'ing-garlic',
                    canonicalName: 'Garlic',
                  ),
                  MatchCandidate(
                    ingredientId: 'ing-gran',
                    canonicalName: 'Garlic granules',
                  ),
                ],
                resolution: const LineResolution(
                  lineIndex: 0,
                  band: MatchBand.suggest,
                  ingredientText: 'garlic cloves',
                  isRange: false,
                  unit: null,
                ),
                onResolveExisting: (id, name, {required correction}) =>
                    picked = id,
                onResolveStub: (_) {},
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Did you mean'), findsOneWidget);
    expect(find.text('Garlic'), findsOneWidget);
    expect(find.text('Garlic granules'), findsOneWidget);

    await tester.tap(find.text('Garlic'));
    await tester.pumpAndSettle();
    expect(picked, 'ing-garlic');
  });

  testWidgets('an auto line locks its ingredient even with an unpicked range; '
      'only the amount is flagged (round-3 #4)', (tester) async {
    final container = ProviderContainer(
      overrides: [
        importRepositoryProvider.overrideWithValue(
          _FakeRepo(_autoRangePayload()),
        ),
      ],
    );
    addTearDown(container.dispose);
    await container
        .read(importControllerProvider.notifier)
        .startImport(const ImportFromUrl('x'));

    await tester.pumpWidget(_host(container));
    await tester.pumpAndSettle();
    await tester.tap(find.byIcon(FLucideIcons.pencil));
    await tester.pumpAndSettle();

    // Ingredient LOCKED (not gated on the amount) — the re-match affordance
    // shows, and there is no "match an ingredient" prompt.
    expect(find.text('tap to change'), findsOneWidget);
    expect(find.text('Match an ingredient'), findsNothing);
    // The unpicked range is flagged separately.
    expect(find.text('Set the amount'), findsWidgets);
    // And the amount editor is live (matched → enabled).
    expect(find.byType(AmountEditor), findsOneWidget);
  });

  testWidgets('an unsupported unit is flagged (not shown ok) and offers valid '
      'unit chips that apply on tap (round-3 #1b/#2)', (tester) async {
    _filterSemanticsAssertions();
    final container = ProviderContainer(
      overrides: [
        importRepositoryProvider.overrideWithValue(_FakeRepo(_autoPayload())),
      ],
    );
    addTearDown(container.dispose);
    await container
        .read(importControllerProvider.notifier)
        .startImport(const ImportFromUrl('x'));
    await tester.pumpWidget(
      _host(
        container,
        validation: const LineValidation(
          issues: [LineIssue.unitNotAllowed],
          unitChoices: [
            UnitSuggestion(token: 'g', label: 'g'),
            UnitSuggestion(token: 'piece', label: 'piece'),
          ],
        ),
      ),
    );
    await tester.pumpAndSettle();

    // Flagged as needing a fix — never silently "ok".
    expect(find.text('Pick a supported unit'), findsWidgets);

    await tester.tap(find.byIcon(FLucideIcons.pencil));
    await tester.pumpAndSettle();

    // Inline unit chips, parallel to the ingredient pills.
    expect(find.text('UNIT'), findsOneWidget);
    expect(find.text('piece'), findsOneWidget);

    await tester.tap(find.text('piece'));
    await tester.pumpAndSettle();
    final updated =
        container.read(importControllerProvider) as ImportReconciling;
    expect(updated.resolutions.first.unit, 'piece');
  });

  testWidgets('the unit chips show five and fold the rest, expanding in place '
      'without losing the selection', (tester) async {
    _filterSemanticsAssertions();
    final container = ProviderContainer(
      overrides: [
        importRepositoryProvider.overrideWithValue(_FakeRepo(_autoPayload())),
      ],
    );
    addTearDown(container.dispose);
    await container
        .read(importControllerProvider.notifier)
        .startImport(const ImportFromUrl('x'));
    await tester.pumpWidget(
      _host(
        container,
        validation: const LineValidation(
          issues: [LineIssue.unitNotAllowed],
          unitChoices: [
            UnitSuggestion(token: 'g', label: 'g'),
            UnitSuggestion(token: 'kg', label: 'kg'),
            UnitSuggestion(token: 'clove', label: 'clove'),
            UnitSuggestion(token: 'tsp', label: 'tsp'),
            UnitSuggestion(token: 'tbsp', label: 'tbsp'),
            UnitSuggestion(token: 'cup', label: 'cup'),
            UnitSuggestion(token: 'pinch', label: 'pinch'),
            UnitSuggestion(token: 'to_taste', label: 'to taste'),
          ],
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byIcon(FLucideIcons.pencil));
    await tester.pumpAndSettle();

    // Five chips, and the imprecise tail is behind the fold.
    expect(find.text('+3 more'), findsOneWidget);
    expect(find.text('to taste'), findsNothing);
    expect(find.text('pinch'), findsNothing);

    // The fold expands IN PLACE — same card, no sheet.
    await tester.tap(find.text('+3 more'));
    await tester.pumpAndSettle();
    expect(find.text('to taste'), findsOneWidget);
    expect(find.text('fewer'), findsOneWidget);

    // Picking a folded chip writes through, and the choice survives the fold.
    await tester.tap(find.text('to taste'));
    await tester.pumpAndSettle();
    final updated =
        container.read(importControllerProvider) as ImportReconciling;
    expect(updated.resolutions.first.unit, 'to_taste');
    expect(find.text('to taste'), findsOneWidget);
  });

  testWidgets('an inadmissible unit opens the amount editor on the '
      'ingredient’s count measure — one confirm tap resolves it', (
    tester,
  ) async {
    _filterSemanticsAssertions();
    final container = ProviderContainer(
      overrides: [
        importRepositoryProvider.overrideWithValue(
          _FakeRepo(_unitMismatchPayload()),
        ),
        ingredientRepositoryProvider.overrideWithValue(_FakeIngredientRepo()),
        measureRepositoryProvider.overrideWithValue(_FakeMeasureRepo()),
      ],
    );
    addTearDown(container.dispose);
    await container
        .read(importControllerProvider.notifier)
        .startImport(const ImportFromUrl('x'));

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          home: FTheme(
            data: ansiThemeData(),
            child: const FScaffold(child: _LiveBody()),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    // Flagged: "ml" is not a unit density-less garlic can carry.
    expect(find.text('Pick a supported unit'), findsWidgets);

    await tester.tap(find.byIcon(FLucideIcons.pencil));
    await tester.pumpAndSettle();
    await tester.tap(find.byType(AmountEditor));
    await tester.pumpAndSettle();

    // The sheet opened ON the measure — confirming adopts it, no chip hunt.
    await tester.tap(find.text('Done'));
    await tester.pumpAndSettle();

    final updated =
        container.read(importControllerProvider) as ImportReconciling;
    expect(updated.resolutions.single.unit, 'clove');
    expect(updated.resolutions.single.quantity, 2);
    // And the flag clears now that the unit is one the ingredient carries.
    expect(find.text('Pick a supported unit'), findsNothing);
  });

  testWidgets('the bin drops the line into an "as deleted" card, and undo '
      'brings it back untouched', (tester) async {
    _filterSemanticsAssertions();
    final container = ProviderContainer(
      overrides: [
        importRepositoryProvider.overrideWithValue(_FakeRepo(_autoPayload())),
      ],
    );
    addTearDown(container.dispose);
    await container
        .read(importControllerProvider.notifier)
        .startImport(const ImportFromUrl('x'));
    await tester.pumpWidget(_host(container));
    await tester.pumpAndSettle();
    await tester.tap(find.byIcon(FLucideIcons.pencil));
    await tester.pumpAndSettle();

    await tester.tap(find.byIcon(FLucideIcons.trash2));
    await tester.pumpAndSettle();

    // Greyed, labelled, and out of the editing surface entirely.
    expect(find.text('removed — this line will not be saved'), findsOneWidget);
    expect(find.text('AMOUNT'), findsNothing);
    final dropped =
        container.read(importControllerProvider) as ImportReconciling;
    expect(dropped.resolutions.single.isDropped, isTrue);
    // It stops being work: no flag, and nothing left unresolved.
    expect(dropped.unresolvedCount, 0);

    await tester.tap(find.text('undo'));
    await tester.pumpAndSettle();
    final back = container.read(importControllerProvider) as ImportReconciling;
    expect(back.resolutions.single.isDropped, isFalse);
    expect(back.resolutions.single.chosenName, 'Spaghetti');
    expect(find.text('200 g'), findsOneWidget);
  });

  // --- Step 8.6 / D6 · board frame (e) -------------------------------------

  group('a recipe offered at review, never auto-linked', () {
    Future<ProviderContainer> reviewing() async {
      final container = ProviderContainer(
        overrides: [
          importRepositoryProvider.overrideWithValue(
            _FakeRepo(_recipeOfferPayload()),
          ),
          recipeRepositoryProvider.overrideWithValue(_FakeRecipeRepo()),
        ],
      );
      addTearDown(container.dispose);
      await container
          .read(importControllerProvider.notifier)
          .startImport(const ImportFromUrl('x'));
      return container;
    }

    testWidgets('the offer rides the did-you-mean row BESIDE the ingredient '
        'candidates — and nothing is linked until it is tapped', (
      tester,
    ) async {
      final container = await reviewing();
      await tester.pumpWidget(_host(container));
      await tester.pumpAndSettle();

      // Arrival: unlinked, and the tag names both doors.
      final arrived =
          container.read(importControllerProvider) as ImportReconciling;
      expect(arrived.resolutions.single.isComponent, isFalse);
      expect(
        find.text('Match an ingredient — or link your recipe'),
        findsOneWidget,
      );

      await tester.tap(find.byIcon(FLucideIcons.pencil));
      await tester.pumpAndSettle();

      // One chip row, both kinds of answer in it.
      expect(find.text('Did you mean'), findsOneWidget);
      expect(find.text('your recipe · Romesco Aioli'), findsOneWidget);
      expect(find.text('Aioli, jarred'), findsOneWidget);
      expect(find.byIcon(kSubRecipeIcon), findsOneWidget);
      // Still nothing linked by rendering it.
      expect(
        (container.read(importControllerProvider) as ImportReconciling)
            .resolutions
            .single
            .isComponent,
        isFalse,
      );
    });

    testWidgets('tapping the chip links the line: recipe chip, no ingredient, '
        'no allowed-units gate, valid for Save', (tester) async {
      final container = await reviewing();
      await tester.pumpWidget(_host(container));
      await tester.pumpAndSettle();
      await tester.tap(find.byIcon(FLucideIcons.pencil));
      await tester.pumpAndSettle();

      await tester.tap(find.text('your recipe · Romesco Aioli'));
      await tester.pumpAndSettle();

      final linked =
          (container.read(importControllerProvider) as ImportReconciling)
              .resolutions
              .single;
      expect(linked.linkedRecipeId, 'r-aioli');
      expect(linked.chosenIngredientId, isNull);
      // Its amount was already printed, so it is valid the moment it links.
      expect(linked.isResolved, isTrue);
      expect(lineIssues(linked), isEmpty);

      // The card says the two rules a linked line lives by…
      expect(find.textContaining('no ingredient match needed'), findsOneWidget);
      // …and the identity cell is lane U's recipe chip, with the unlink beside
      // it. (Two: the expanded card's cell — the collapsed row is not built.)
      expect(find.text('Romesco Aioli'), findsWidgets);
      expect(find.text('unlink'), findsOneWidget);
      // No ingredient prompt survives.
      expect(find.text('Match an ingredient'), findsNothing);
      expect(
        find.text('Match an ingredient — or link your recipe'),
        findsNothing,
      );
    });

    testWidgets('the link is reversible before Save — unlink puts the line '
        'back exactly as it arrived', (tester) async {
      final container = await reviewing();
      await tester.pumpWidget(_host(container));
      await tester.pumpAndSettle();
      await tester.tap(find.byIcon(FLucideIcons.pencil));
      await tester.pumpAndSettle();
      await tester.tap(find.text('your recipe · Romesco Aioli'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('unlink'));
      await tester.pumpAndSettle();

      final back =
          (container.read(importControllerProvider) as ImportReconciling)
              .resolutions
              .single;
      expect(back.isComponent, isFalse);
      expect(back.quantity, 0.25); // the printed amount is not disturbed
      // The offer is on the card again, unanswered.
      expect(find.text('your recipe · Romesco Aioli'), findsOneWidget);
      expect(
        find.text('Match an ingredient — or link your recipe'),
        findsOneWidget,
      );
    });

    testWidgets('a linked line with no amount is flagged "Set the amount" — '
        'its only gate', (tester) async {
      final container = await reviewing();
      await tester.pumpWidget(_host(container));
      await tester.pumpAndSettle();
      container
          .read(importControllerProvider.notifier)
          .updateResolution(
            0,
            (r) => r.linkToRecipe('r-aioli', 'Romesco Aioli').setAmount(),
          );
      await tester.pumpAndSettle();

      expect(find.text('Set the amount'), findsWidgets);
      expect(
        (container.read(importControllerProvider) as ImportReconciling)
            .canCommit,
        isFalse,
      );
    });

    testWidgets('editing a linked amount opens the COMPONENT sheet — batch '
        'chips against the target’s yield, not an ingredient’s units', (
      tester,
    ) async {
      _filterSemanticsAssertions();
      final container = await reviewing();
      await tester.pumpWidget(_host(container));
      await tester.pumpAndSettle();
      await tester.tap(find.byIcon(FLucideIcons.pencil));
      await tester.pumpAndSettle();
      await tester.tap(find.text('your recipe · Romesco Aioli'));
      await tester.pumpAndSettle();

      await tester.tap(find.byType(AmountEditor));
      await tester.pumpAndSettle();

      // Lane U's sheet, reading the target's yields off the local repository.
      expect(find.text('makes 1 cup · your recipe'), findsOneWidget);
      expect(find.textContaining('0.25 of a batch'), findsOneWidget);
      expect(find.text('batch'), findsOneWidget);

      await tester.tap(find.text('Done'));
      await tester.pumpAndSettle();
      final saved =
          (container.read(importControllerProvider) as ImportReconciling)
              .resolutions
              .single;
      expect(saved.quantity, 0.25);
      expect(saved.unit, 'cup');
    });
  });

  group('crossReferenceFlag (board frame e)', () {
    test('a printed page reference is surfaced, in its own words', () {
      expect(crossReferenceFlag('Romesco Aioli (page 38)'), '(page 38)');
      expect(crossReferenceFlag('Garlic Butter (p. 17)'), '(p. 17)');
      expect(crossReferenceFlag('Pretzel Buns (see page 97)'), '(see page 97)');
    });

    test('an ordinary parenthetical is NOT a cross-reference', () {
      expect(crossReferenceFlag('tomatoes (400 g tin)'), isNull);
      expect(crossReferenceFlag('parsley (optional)'), isNull);
      expect(crossReferenceFlag('onion'), isNull);
    });
  });

  group('amountLabel (round-3 #1a)', () {
    test('an imprecise unit reads as the clean unit, never the raw phrase', () {
      const r = LineResolution(
        lineIndex: 0,
        band: MatchBand.none,
        ingredientText: 'chilli',
        isRange: false,
        unit: 'pinch',
      );
      expect(
        amountLabel(
          r,
          const RawLineItem(
            ingredientText: 'chilli',
            rawAmount: 'A good pinch',
          ),
        ),
        'pinch',
      );
    });

    test('an unpicked range shows the printed original for reference', () {
      const r = LineResolution(
        lineIndex: 0,
        band: MatchBand.auto,
        ingredientText: 'garlic',
        isRange: true,
        unit: 'clove',
      );
      expect(
        amountLabel(
          r,
          const RawLineItem(ingredientText: 'garlic', rawAmount: '2–3 cloves'),
        ),
        '2–3 cloves',
      );
    });

    test('a picked quantity + unit reads plainly', () {
      const r = LineResolution(
        lineIndex: 0,
        band: MatchBand.auto,
        ingredientText: 'spaghetti',
        isRange: false,
        unit: 'g',
        quantity: 400,
      );
      expect(amountLabel(r, const RawLineItem(ingredientText: 'x')), '400 g');
    });

    test('a prose amount shows the qualifier, never the raw parenthetical', () {
      const r = LineResolution(
        lineIndex: 0,
        band: MatchBand.none,
        ingredientText: 'Tortilla chips',
        isRange: false,
        unit: null,
      );
      expect(
        amountLabel(
          r,
          const RawLineItem(
            ingredientText: 'Tortilla chips',
            rawAmount: '(to serve (optional))',
          ),
        ),
        'to serve',
      );
    });

    test('nothing printed reads as nothing — the caller renders "—"', () {
      const r = LineResolution(
        lineIndex: 0,
        band: MatchBand.none,
        ingredientText: 'Tortilla chips',
        isRange: false,
        unit: null,
      );
      expect(
        amountLabel(r, const RawLineItem(ingredientText: 'Tortilla chips')),
        '',
      );
    });

    test('a printed amount the vocab could not map still shows as printed', () {
      const r = LineResolution(
        lineIndex: 0,
        band: MatchBand.none,
        ingredientText: 'thyme',
        isRange: false,
        unit: 'sprig',
      );
      expect(
        amountLabel(
          r,
          const RawLineItem(ingredientText: 'thyme', rawAmount: '2 sprigs'),
        ),
        '2 sprigs',
      );
    });
  });
}
