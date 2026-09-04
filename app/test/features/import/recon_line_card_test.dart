// The pumped ProviderScope IS the root scope of each test's tree.
// ignore_for_file: scoped_providers_should_specify_dependencies

import 'package:ansi/core/theme/ansi_theme.dart';
import 'package:ansi/core/units/macros.dart';
import 'package:ansi/core/units/measure.dart';
import 'package:ansi/core/units/units.dart';
import 'package:ansi/features/books/data/book_providers.dart';
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
import 'package:ansi/shared/picker_shell.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:forui/forui.dart';
import 'package:go_router/go_router.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

import '../../helpers/fake_book_repository.dart';
import '../../helpers/fake_ingredient_repository.dart';
import '../../helpers/fake_measure_repository.dart';
import '../../helpers/forui_semantics.dart';
import '../../helpers/silent_usda_probe.dart';

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

/// A `piece` line on a row whose measure names the thing — the board's frame
/// (a). Post-curation (plan 0022) `piece` is not in the row's `allowed_units`,
/// so the shipped `unitNotAllowed` machinery finally reaches this line.
ReconciliationPayload _piecePayload(String name, String ingredientId) =>
    ReconciliationPayload(
      title: 'T',
      servingsBase: 2,
      groups: [
        ReconGroup(
          lines: [
            ReconLine(
              raw: RawLineItem(
                ingredientText: '1 large ripe $name',
                qty: 1,
                unit: 'piece',
                rawAmount: '1 large',
              ),
              band: MatchBand.auto,
              candidates: [
                MatchCandidate(
                  ingredientId: ingredientId,
                  canonicalName: name,
                  score: 0.97,
                ),
              ],
            ),
          ],
        ),
      ],
    );

/// Seam frame (a): a sized family with a curated default — "2 red peppers"
/// means two mediums, and the review says so on the card.
const _pepper = Ingredient(
  id: 'ing-pepper',
  canonicalName: 'Red bell pepper',
  defaultUnit: pieces,
  category: 'produce',
  status: IngredientStatus.complete,
  densityGPerMl: 0.5,
  allowedUnits: [g, tsp, tbsp, cup, ml, handful],
  defaultMeasureId: 'm-pep-med',
);
const _pepperSizes = [
  Measure(id: 'm-pep-med', label: 'pepper, medium', amount: 119),
  Measure(id: 'm-pep-lrg', label: 'pepper, large', amount: 164),
  Measure(id: 'm-pep-sml', label: 'pepper, small', amount: 74),
];

/// Seam D3: one measure and no stated default. There is nothing else the line
/// could have meant, which is ADR-0010 consequence 4's own sentence.
const _cucumber = Ingredient(
  id: 'ing-cucumber',
  canonicalName: 'Cucumber',
  defaultUnit: pieces,
  category: 'produce',
  status: IngredientStatus.complete,
  allowedUnits: [g, handful],
);
const _cucumberMeasure = Measure(id: 'm-cuc', label: 'cucumber', amount: 301);

/// Seam frame (b): a fragment set — three KINDS of countable thing and no
/// dominant one, so the row states no default and the line keeps its flag.
const _broccoli = Ingredient(
  id: 'ing-broccoli',
  canonicalName: 'Broccoli',
  defaultUnit: pieces,
  category: 'produce',
  status: IngredientStatus.complete,
  allowedUnits: [g, handful],
);
const _broccoliParts = [
  Measure(id: 'm-b-whole', label: 'whole', amount: 608),
  Measure(id: 'm-b-spear', label: 'spear', amount: 31),
  Measure(id: 'm-b-crown', label: 'crown', amount: 150),
];

/// The scope rule's counter-case: a row whose default is its SOLE measure,
/// on a line that printed a word of its own.
const _cilantro = Ingredient(
  id: 'ing-cilantro',
  canonicalName: 'Cilantro',
  defaultUnit: pieces,
  category: 'produce',
  status: IngredientStatus.complete,
  allowedUnits: [g, handful],
  defaultMeasureId: 'm-cil-sprig',
);
const _cilantroSprig = Measure(id: 'm-cil-sprig', label: 'sprig', amount: 2.22);

/// "1 bunch cilantro, chopped" — the source named a THING the row does not
/// carry. Today's flag stands; the default answers a number and no thing.
ReconciliationPayload _bunchPayload() => ReconciliationPayload(
  title: 'T',
  servingsBase: 2,
  groups: [
    ReconGroup(
      lines: [
        ReconLine(
          raw: const RawLineItem(
            ingredientText: '1 bunch cilantro, chopped',
            qty: 1,
            unit: 'bunch',
            rawAmount: '1 bunch',
          ),
          band: MatchBand.auto,
          candidates: [
            MatchCandidate(
              ingredientId: _cilantro.id,
              canonicalName: 'Cilantro',
              score: 0.97,
            ),
          ],
        ),
      ],
    ),
  ],
);

/// Frame (a) right: three sizes, so nothing is pre-selected and the user picks.
const _potato = Ingredient(
  id: 'ing-potato',
  canonicalName: 'Gold Potato',
  defaultUnit: pieces,
  category: 'produce',
  status: IngredientStatus.complete,
  densityGPerMl: 0.59,
  allowedUnits: [g, tsp, tbsp, cup, ml, handful],
);
const _potatoSizes = [
  Measure(id: 'm-p-med', label: 'potato, medium', amount: 213),
  Measure(id: 'm-p-lrg', label: 'potato, large', amount: 369),
  Measure(id: 'm-p-sml', label: 'potato, small', amount: 170),
];

class _FakeIngredientRepo
    with IngredientManagerStubs
    implements IngredientRepository {
  _FakeIngredientRepo([this.row = _garlic]);

  final Ingredient row;

  @override
  Future<Ingredient?> saveForm(String? ingredientId, IngredientFormEdit edit) =>
      throw UnimplementedError();

  @override
  Future<Ingredient?> byId(String id) async => row;

  @override
  Future<Map<String, Ingredient>> byIds(Set<String> ids) async => {
    for (final id in ids) id: row,
  };

  @override
  Future<IngredientMatches> search(String query, {int limit = 30}) async =>
      (rows: const <Ingredient>[], guessed: false);

  @override
  Future<List<Ingredient>> recentlyUsed({int limit = 8}) async => const [];

  @override
  Future<Ingredient?> setDensity(String ingredientId, double gPerMl) async =>
      null;
}

class _FakeMeasureRepo implements MeasureRepository {
  _FakeMeasureRepo([this.rows = const [_clove]]);

  final List<Measure> rows;

  @override
  Stream<List<Measure>> watchMeasures(String ingredientId) =>
      Stream.value(rows);

  @override
  Future<Map<String, List<Measure>>> measuresByIngredients(
    Set<String> ids,
  ) async => {for (final id in ids) id: rows};

  @override
  Future<Measure> addMeasure({
    required String ingredientId,
    required String label,
    required double amount,
  }) async => rows.first;

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
  Future<void> setFiling(String id, String bookId, String? sectionId) async {}

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

void main() {
  testWidgets('an auto line is compact, then expands into the editable card '
      '(re-match + amount + notes)', (tester) async {
    final container = ProviderContainer(
      overrides: [
        bookRepositoryProvider.overrideWithValue(const FakeBookRepository()),
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
    filterForuiSemanticsAssertions();
    final container = ProviderContainer(
      overrides: [
        bookRepositoryProvider.overrideWithValue(const FakeBookRepository()),
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
    filterForuiSemanticsAssertions();
    final container = ProviderContainer(
      overrides: [
        bookRepositoryProvider.overrideWithValue(const FakeBookRepository()),
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
        .updateResolution(
          0,
          (r) => r.resolveToIngredient('ing-mystery', 'Mystery spice'),
        );
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
        bookRepositoryProvider.overrideWithValue(const FakeBookRepository()),
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
    filterForuiSemanticsAssertions();
    final container = ProviderContainer(
      overrides: [
        bookRepositoryProvider.overrideWithValue(const FakeBookRepository()),
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
    filterForuiSemanticsAssertions();
    final container = ProviderContainer(
      overrides: [
        bookRepositoryProvider.overrideWithValue(const FakeBookRepository()),
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
    filterForuiSemanticsAssertions();
    final container = ProviderContainer(
      overrides: [
        bookRepositoryProvider.overrideWithValue(const FakeBookRepository()),
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

  testWidgets("the amount sheet's Optional switch writes the line fact back "
      'onto the resolution (plan 0025 / D6a)', (tester) async {
    filterForuiSemanticsAssertions();
    final container = ProviderContainer(
      overrides: [
        bookRepositoryProvider.overrideWithValue(const FakeBookRepository()),
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

    await tester.tap(find.byIcon(FLucideIcons.pencil));
    await tester.pumpAndSettle();
    await tester.tap(find.byType(AmountEditor));
    await tester.pumpAndSettle();

    // The same sheet the editor uses, so the review gets the row for free.
    expect(find.text('Optional'), findsOneWidget);
    await tester.tap(find.byType(FSwitch));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Done'));
    await tester.pumpAndSettle();

    final updated =
        container.read(importControllerProvider) as ImportReconciling;
    expect(updated.resolutions.single.optional, isTrue);
  });

  // --- plan 0022 / ADR-0010 · the board's frame (a) -------------------------
  //
  // "1 large ripe avocado" extracts as unit="piece" and used to commit as a
  // bare count that the macro engine honestly excluded — while the vocab held
  // avocado = 201 g. Nothing new is built for it: taking `piece` out of the
  // row's admission list is what finally switches the shipped machinery on.

  Future<void> pumpPieceLine(
    WidgetTester tester,
    ProviderContainer container,
  ) async {
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
  }

  // --- plan 0024 · seam D2 + D3 · the board's frames (a) and (b) ------------
  //
  // D3, named: `preselectedMeasure` pre-selected the SHEET, never the LINE, so
  // a sole-measure row stayed flagged until somebody opened and confirmed it.
  // D2 writes the LINE, so a line that named a number and no thing arrives on
  // its curated default (or its sole measure), clean, with the fact said out
  // loud on the card and the chips still beside it.

  testWidgets('a sized row arrives on its curated default, unflagged, with '
      'the fact on the card and the alternatives beside it (frame a)', (
    tester,
  ) async {
    filterForuiSemanticsAssertions();
    final container = ProviderContainer(
      overrides: [
        bookRepositoryProvider.overrideWithValue(const FakeBookRepository()),
        importRepositoryProvider.overrideWithValue(
          _FakeRepo(_piecePayload('Red Pepper', _pepper.id)),
        ),
        ingredientRepositoryProvider.overrideWithValue(
          _FakeIngredientRepo(_pepper),
        ),
        measureRepositoryProvider.overrideWithValue(
          _FakeMeasureRepo(_pepperSizes),
        ),
      ],
    );
    addTearDown(container.dispose);
    await pumpPieceLine(tester, container);

    // No flag, nothing held up — the card is clean for the ORDINARY reason:
    // the resolution's unit is one the row carries.
    expect(find.text('Pick a supported unit'), findsNothing);
    var state = container.read(importControllerProvider) as ImportReconciling;
    expect(state.resolutions.single.unit, 'pepper, medium');
    expect(state.resolutions.single.unitFromDefault, isTrue);

    await tester.tap(find.byIcon(FLucideIcons.pencil));
    await tester.pumpAndSettle();

    // The source line is still there, and so is the sentence that makes the
    // default honest: shown at the moment it is applied.
    expect(find.textContaining('ripe Red Pepper'), findsWidgets);
    expect(find.textContaining('counts as  pepper, medium · 119 g'), findsOne);

    // The chips stay VISIBLE — the choice made for you, beside the ones you
    // could make instead. Hiding them would make tap-to-change invisible.
    expect(find.text('UNIT'), findsOneWidget);
    for (final m in _pepperSizes) {
      expect(find.text(m.label), findsWidgets);
    }
    expect(find.text('piece'), findsNothing);

    // One tap changes it, and the card stops claiming the default answered.
    await tester.tap(find.text('pepper, large').last);
    await tester.pumpAndSettle();
    state = container.read(importControllerProvider) as ImportReconciling;
    expect(state.resolutions.single.unit, 'pepper, large');
    expect(state.resolutions.single.unitFromDefault, isFalse);
    expect(find.textContaining('counts as'), findsNothing);
    expect(find.text('Pick a supported unit'), findsNothing);
  });

  testWidgets('a SOLE-measure row arrives on it too — the preselect that only '
      'ever opened the sheet now writes the line (D3)', (tester) async {
    filterForuiSemanticsAssertions();
    final repo = _FakeRepo(_piecePayload('Cucumber', _cucumber.id));
    final container = ProviderContainer(
      overrides: [
        bookRepositoryProvider.overrideWithValue(const FakeBookRepository()),
        importRepositoryProvider.overrideWithValue(repo),
        ingredientRepositoryProvider.overrideWithValue(
          _FakeIngredientRepo(_cucumber),
        ),
        measureRepositoryProvider.overrideWithValue(
          _FakeMeasureRepo(const [_cucumberMeasure]),
        ),
      ],
    );
    addTearDown(container.dispose);
    await pumpPieceLine(tester, container);

    expect(find.text('Pick a supported unit'), findsNothing);
    final state = container.read(importControllerProvider) as ImportReconciling;
    expect(state.resolutions.single.unit, 'cucumber');
    expect(state.resolutions.single.unitFromDefault, isTrue);

    await tester.tap(find.byIcon(FLucideIcons.pencil));
    await tester.pumpAndSettle();
    expect(find.textContaining('counts as  cucumber · 301 g'), findsOne);
    expect(find.text('piece'), findsNothing);

    // And the commit is byte-for-byte what a TAPPED chip produces: the
    // measure's label rides through, and the repository re-resolves it to the
    // `measure_id` FK exactly as it does for a hand-picked one. No new token,
    // no provenance, no `inferred` mark on the stored line.
    await container
        .read(importControllerProvider.notifier)
        .commit(issuesByLine: const {0: []});
    expect(repo.committed!.groups.single.lines.single.unit, 'cucumber');
  });

  testWidgets('a fragment set has no default and stays flagged — the model '
      'can say "I don\'t know", which a rule never can (frame b)', (
    tester,
  ) async {
    filterForuiSemanticsAssertions();
    final container = ProviderContainer(
      overrides: [
        bookRepositoryProvider.overrideWithValue(const FakeBookRepository()),
        importRepositoryProvider.overrideWithValue(
          _FakeRepo(_piecePayload('Broccoli', _broccoli.id)),
        ),
        ingredientRepositoryProvider.overrideWithValue(
          _FakeIngredientRepo(_broccoli),
        ),
        measureRepositoryProvider.overrideWithValue(
          _FakeMeasureRepo(_broccoliParts),
        ),
      ],
    );
    addTearDown(container.dispose);
    await pumpPieceLine(tester, container);

    expect(find.text('Pick a supported unit'), findsWidgets);
    final state = container.read(importControllerProvider) as ImportReconciling;
    expect(state.resolutions.single.unit, 'piece');
    expect(state.resolutions.single.unitFromDefault, isFalse);

    await tester.tap(find.byIcon(FLucideIcons.pencil));
    await tester.pumpAndSettle();
    // Three different things — the user picks; we don't.
    for (final m in _broccoliParts) {
      expect(find.text(m.label), findsWidgets);
    }
    expect(find.textContaining('counts as'), findsNothing);
  });

  testWidgets('a line that PRINTED a word the row refuses is untouched — the '
      'default never overrules the source', (tester) async {
    filterForuiSemanticsAssertions();
    final container = ProviderContainer(
      overrides: [
        bookRepositoryProvider.overrideWithValue(const FakeBookRepository()),
        importRepositoryProvider.overrideWithValue(_FakeRepo(_bunchPayload())),
        ingredientRepositoryProvider.overrideWithValue(
          _FakeIngredientRepo(_cilantro),
        ),
        measureRepositoryProvider.overrideWithValue(
          _FakeMeasureRepo(const [_cilantroSprig]),
        ),
      ],
    );
    addTearDown(container.dispose);
    await pumpPieceLine(tester, container);

    // Cilantro's default IS `sprig` (2.22 g) and a bunch is ~25 of them.
    // Applying it here would be a silent 25× error, so the flag stands.
    final state = container.read(importControllerProvider) as ImportReconciling;
    expect(state.resolutions.single.unit, 'bunch');
    expect(state.resolutions.single.unitFromDefault, isFalse);
    expect(find.text('Pick a supported unit'), findsWidgets);

    await tester.tap(find.byIcon(FLucideIcons.pencil));
    await tester.pumpAndSettle();
    expect(find.textContaining('counts as'), findsNothing);
    expect(find.text('sprig'), findsWidgets);
  });

  testWidgets('three measures pre-select nothing — Save stays gated until the '
      'user picks a size, and then it clears', (tester) async {
    filterForuiSemanticsAssertions();
    final container = ProviderContainer(
      overrides: [
        bookRepositoryProvider.overrideWithValue(const FakeBookRepository()),
        importRepositoryProvider.overrideWithValue(
          _FakeRepo(_piecePayload('Gold Potato', _potato.id)),
        ),
        ingredientRepositoryProvider.overrideWithValue(
          _FakeIngredientRepo(_potato),
        ),
        measureRepositoryProvider.overrideWithValue(
          _FakeMeasureRepo(_potatoSizes),
        ),
      ],
    );
    addTearDown(container.dispose);
    await pumpPieceLine(tester, container);

    expect(find.text('Pick a supported unit'), findsWidgets);
    await tester.tap(find.byIcon(FLucideIcons.pencil));
    await tester.pumpAndSettle();

    // All three sizes in front of the fold, `piece` nowhere.
    for (final m in _potatoSizes) {
      expect(find.text(m.label), findsOneWidget);
    }
    expect(find.text('piece'), findsNothing);

    // Confirming the sheet without picking resolves NOTHING: no medium
    // tie-break, no first-in-sort_order guess.
    await tester.tap(find.byType(AmountEditor));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Done'));
    await tester.pumpAndSettle();
    var state = container.read(importControllerProvider) as ImportReconciling;
    expect(state.resolutions.single.unit, 'piece');
    expect(find.text('Pick a supported unit'), findsWidgets);

    // The user picks. That is the whole interaction.
    await tester.tap(find.text('potato, large'));
    await tester.pumpAndSettle();
    state = container.read(importControllerProvider) as ImportReconciling;
    expect(state.resolutions.single.unit, 'potato, large');
    expect(find.text('Pick a supported unit'), findsNothing);
  });

  testWidgets('the bin drops the line into an "as deleted" card, and undo '
      'brings it back untouched', (tester) async {
    filterForuiSemanticsAssertions();
    final container = ProviderContainer(
      overrides: [
        bookRepositoryProvider.overrideWithValue(const FakeBookRepository()),
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
          bookRepositoryProvider.overrideWithValue(const FakeBookRepository()),
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
      filterForuiSemanticsAssertions();
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

  group('create-new at review is the one add flow (plan 0025 D3, frame d)', () {
    testWidgets('the footer opens the New-ingredient sheet with the line’s '
        'text, walks the form pushed over the search sheet, and resolves the '
        'line to the re-read row as an existing ingredient', (tester) async {
      filterForuiSemanticsAssertions();
      final repo = FakeIngredientRepo(const []);
      final picks = <ReconcilePick?>[];
      final router = GoRouter(
        initialLocation: '/',
        routes: [
          GoRoute(
            path: '/',
            builder: (_, _) => FScaffold(
              child: Builder(
                builder: (context) => FButton(
                  onPress: () async => picks.add(
                    await showReconcileIngredientSheet(
                      context,
                      seedName: 'curry leaves',
                    ),
                  ),
                  child: const Text('match'),
                ),
              ),
            ),
          ),
          // The flesh-out form's stand-in: pops on tap, like back does.
          GoRoute(
            path: '/ingredients/new',
            builder: (context, state) => FScaffold(
              child: FButton(
                onPress: () async {
                  // What ONE Save does (plan 0029 C2): the row and everything
                  // the form set, then pop with it.
                  final saved = await repo.saveForm(
                    null,
                    IngredientFormEdit(
                      row: IngredientEdit(
                        canonicalName: state.uri.queryParameters['name'] ?? '',
                        defaultUnit: g,
                        macrosBasis: MacrosBasis.perG,
                        allowedUnits: {g, kg},
                      ),
                    ),
                  );
                  if (context.mounted) context.pop(saved);
                },
                child: const Text('create'),
              ),
            ),
          ),
          GoRoute(
            path: '/ingredients/:id',
            builder: (context, state) => FScaffold(
              child: FButton(
                onPress: () => context.pop(),
                child: Text('form ${state.pathParameters['id']}'),
              ),
            ),
          ),
        ],
      );
      addTearDown(router.dispose);
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            ingredientRepositoryProvider.overrideWithValue(repo),
            measureRepositoryProvider.overrideWithValue(FakeMeasureRepo()),
            usdaProbeProvider.overrideWithValue(const SilentUsdaProbe()),
          ],
          child: MaterialApp.router(
            routerConfig: router,
            builder: (context, child) =>
                FTheme(data: ansiThemeData(), child: child!),
          ),
        ),
      );
      await tester.tap(find.text('match'));
      await tester.pumpAndSettle();

      // The row reads in the picker footer's voice, seeded with the line's
      // own text — no "add as stub" (round-3 detail 9).
      final create = find.text('create "curry leaves" as a new ingredient');
      expect(create, findsOneWidget);
      await tester.tap(create);
      await tester.pumpAndSettle();
      expect(repo.rows, isEmpty, reason: 'tapping the row writes nothing');
      // The FORM opens, seeded with the line's own text (plan 0029 C2) — one
      // screen, and still nothing written.
      expect(find.text('create'), findsOneWidget);
      expect(picks, isEmpty, reason: 'the line resolves after the form pops');

      await tester.tap(find.text('create'));
      await tester.pumpAndSettle();
      final created = repo.rows.single;

      // Resolved as the ordinary matched state, on the row the form's one
      // Save produced; the search sheet has closed with it.
      expect(picks.single, isA<PickExisting>());
      final row = (picks.single! as PickExisting).ingredient;
      expect(row.id, created.id);
      expect(row.canonicalName, 'curry leaves');
      expect(row.allowedUnits, [g, kg]);
      expect(row.status, IngredientStatus.stub);
      expect(find.byType(PickerShell), findsNothing);
    });
  });

  group(
    'a pick lands even when the card is gone by the time the sheet closes',
    () {
      // The review is a viewport. On a phone the search sheet's keyboard
      // shrinks it, and the card that opened the sheet can scroll out and
      // UNMOUNT while the sheet is still open. Riverpod 3 throws on a
      // `WidgetRef` used after unmount, so the pick was lost (owner field
      // report, 2026-09-03: "swapped wild garlic for kale, it didn't set") —
      // and the amount sheets share the shape. The pick must land regardless
      // of what happened to the card underneath.
      testWidgets('the search sheet resolves the line through the controller, '
          'not the unmounted card', (tester) async {
        filterForuiSemanticsAssertions();
        const kale = Ingredient(
          id: 'ing-kale',
          canonicalName: 'Kale',
          defaultUnit: g,
          status: IngredientStatus.complete,
        );
        final container = ProviderContainer(
          overrides: [
            bookRepositoryProvider.overrideWithValue(
              const FakeBookRepository(),
            ),
            importRepositoryProvider.overrideWithValue(
              _FakeRepo(_nonePayload()),
            ),
            ingredientRepositoryProvider.overrideWithValue(
              FakeIngredientRepo(const [kale]),
            ),
            measureRepositoryProvider.overrideWithValue(FakeMeasureRepo()),
            usdaProbeProvider.overrideWithValue(const SilentUsdaProbe()),
          ],
        );
        addTearDown(container.dispose);
        await container
            .read(importControllerProvider.notifier)
            .startImport(const ImportFromUrl('x'));

        final showCard = ValueNotifier(true);
        addTearDown(showCard.dispose);
        await tester.pumpWidget(_toggleHost(container, showCard));
        await tester.pumpAndSettle();
        await tester.tap(find.byIcon(FLucideIcons.pencil));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Find or create ingredient'));
        await tester.pumpAndSettle();
        expect(find.byType(PickerShell), findsOneWidget);

        // The card leaves the tree while the sheet is up.
        showCard.value = false;
        await tester.pumpAndSettle();
        expect(find.byType(ReviewLineCard), findsNothing);
        expect(find.byType(PickerShell), findsOneWidget);

        await tester.tap(
          find.descendant(
            of: find.byType(PickerShell),
            matching: find.text('Kale'),
          ),
        );
        await tester.pumpAndSettle();

        expect(tester.takeException(), isNull);
        final state = container.read(importControllerProvider);
        final line = (state as ImportReconciling).resolutions.single;
        expect(line.chosenIngredientId, 'ing-kale');
        expect(line.chosenName, 'Kale');
        expect(
          line.isCorrection,
          isTrue,
          reason: 'a search pick is a correction',
        );
      });
    },
  );
}

/// [_host], but the card can be removed from the tree mid-flow — the state
/// stays watched at the top so the (autoDispose) controller lives on.
Widget _toggleHost(ProviderContainer container, ValueNotifier<bool> show) =>
    UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
        home: FTheme(
          data: ansiThemeData(),
          child: FScaffold(
            child: ValueListenableBuilder<bool>(
              valueListenable: show,
              builder: (_, visible, _) =>
                  visible ? const _Body() : const _Watcher(),
            ),
          ),
        ),
      ),
    );

/// Keeps the controller alive without rendering a card.
class _Watcher extends ConsumerWidget {
  const _Watcher();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    ref.watch(importControllerProvider);
    return const SizedBox.shrink();
  }
}
