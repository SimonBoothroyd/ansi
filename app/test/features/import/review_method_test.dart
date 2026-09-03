/// The review screen edits the method with the shipped editor v2 step cards
/// (seam **D4**, board frame c). The screen most likely to need a method fix
/// used to be the only one that could not make it — behind a note claiming
/// "Method is read-only in v1", which the step cards had already made false.
// The pumped ProviderScope IS the root scope of each test's tree.
// ignore_for_file: scoped_providers_should_specify_dependencies
library;

import 'package:ansi/core/theme/ansi_theme.dart';
import 'package:ansi/core/units/macros.dart';
import 'package:ansi/core/units/measure.dart';
import 'package:ansi/core/units/units.dart';
import 'package:ansi/features/books/data/book_providers.dart';
import 'package:ansi/features/import/data/import_providers.dart';
import 'package:ansi/features/import/domain/commit_payload.dart';
import 'package:ansi/features/import/domain/import_repository.dart';
import 'package:ansi/features/import/domain/reconciliation_payload.dart'
    hide Step;
import 'package:ansi/features/import/domain/reconciliation_payload.dart'
    as payload
    show Step;
import 'package:ansi/features/import/presentation/import_method_editing.dart';
import 'package:ansi/features/import/presentation/import_view_models.dart';
import 'package:ansi/features/import/presentation/reconciliation_view.dart';
import 'package:ansi/features/ingredients/data/ingredient_providers.dart';
import 'package:ansi/features/ingredients/domain/ingredient.dart';
import 'package:ansi/features/ingredients/domain/ingredient_repository.dart';
import 'package:ansi/features/ingredients/domain/measure_repository.dart';
import 'package:ansi/features/recipes/domain/recipe.dart';
import 'package:ansi/features/recipes/presentation/method_editor.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:forui/forui.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

import '../../helpers/fake_book_repository.dart';
import '../../helpers/fake_ingredient_repository.dart';

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

const _onion = Ingredient(
  id: 'ing-onion',
  canonicalName: 'Onion',
  defaultUnit: g,
  status: IngredientStatus.complete,
);

class _FakeIngredientRepo
    with IngredientManagerStubs
    implements IngredientRepository {
  @override
  Future<Ingredient?> byId(String id) async => _onion;

  @override
  Future<Map<String, Ingredient>> byIds(Set<String> ids) async => {
    for (final id in ids) id: _onion,
  };

  @override
  Future<IngredientMatches> search(String query, {int limit = 30}) async =>
      (rows: const <Ingredient>[], guessed: false);

  @override
  Future<List<Ingredient>> recentlyUsed({int limit = 8}) async => const [];

  @override
  Future<Ingredient> createStub(
    String name, {
    String source = 'manual',
    Macros? macros,
    MacrosBasis macrosBasis = MacrosBasis.perG,
  }) async => _onion;

  @override
  Future<Ingredient?> setDensity(String ingredientId, double gPerMl) async =>
      null;
}

class _FakeMeasureRepo implements MeasureRepository {
  @override
  Stream<List<Measure>> watchMeasures(String ingredientId) =>
      Stream.value(const []);

  @override
  Future<Map<String, List<Measure>>> measuresByIngredients(
    Set<String> ids,
  ) async => const {};

  @override
  Future<Measure> addMeasure({
    required String ingredientId,
    required String label,
    required double amount,
  }) async => throw UnimplementedError();

  @override
  Future<void> softDeleteMeasure(String measureId) async {}
}

/// One clean auto-matched line and a two-step method whose first step chips
/// it — so Save is open and the method is the only thing under test.
ReconciliationPayload _payload() => const ReconciliationPayload(
  title: 'Charred Pepper Traybake',
  servingsBase: 4,
  groups: [
    ReconGroup(
      lines: [
        ReconLine(
          raw: RawLineItem(
            ingredientText: 'onions, thinly sliced',
            qty: 200,
            unit: 'g',
            rawAmount: '200 g onions',
          ),
          band: MatchBand.auto,
          candidates: [
            MatchCandidate(ingredientId: 'ing-onion', canonicalName: 'Onion'),
          ],
        ),
      ],
    ),
  ],
  steps: [
    payload.Step(
      tokens: [
        TextToken(s: 'Toss the '),
        RefToken(refs: [0], label: 'onions'),
        TextToken(s: ' with the oil.'),
      ],
    ),
    payload.Step(tokens: [TextToken(s: 'Roast until charred.')]),
  ],
);

class _Body extends ConsumerWidget {
  const _Body();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(importControllerProvider);
    if (state is! ImportReconciling) return const SizedBox.shrink();
    return ReconciliationBody(state: state);
  }
}

Future<ProviderContainer> _reviewing(_FakeRepo repo) async {
  final container = ProviderContainer(
    overrides: [
      bookRepositoryProvider.overrideWithValue(const FakeBookRepository()),
      importRepositoryProvider.overrideWithValue(repo),
      ingredientRepositoryProvider.overrideWithValue(_FakeIngredientRepo()),
      measureRepositoryProvider.overrideWithValue(_FakeMeasureRepo()),
    ],
  );
  addTearDown(container.dispose);
  await container
      .read(importControllerProvider.notifier)
      .startImport(const ImportFromUrl('x'));
  return container;
}

Widget _host(ProviderContainer container) => UncontrolledProviderScope(
  container: container,
  child: MaterialApp(
    home: FTheme(
      data: ansiThemeData(),
      child: const FScaffold(child: _Body()),
    ),
  ),
);

/// The step card's own field, found by the sentence it is showing — the
/// review screen has other text fields (servings, MAKES) above the method.
Finder _stepField(String text) => find.byWidgetPredicate(
  (w) => w is EditableText && w.controller.text == text,
);

/// The review screen is one long ListView, and a ListView only builds what is
/// on screen — Save lives past the method. Give the harness a tall viewport
/// rather than driving a scroll in every test.
void _tallViewport(WidgetTester tester) {
  tester.view.physicalSize = const Size(1200, 4000);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
}

void _filterSemanticsAssertions() {
  final reportError = FlutterError.onError!;
  FlutterError.onError = (details) {
    if ('${details.exception}'.contains('semantics.dart')) return;
    reportError(details);
  };
  addTearDown(() => FlutterError.onError = reportError);
}

void main() {
  testWidgets('the step cards render at review, and the "read-only in v1" '
      'notice is gone', (tester) async {
    _filterSemanticsAssertions();
    _tallViewport(tester);
    final container = await _reviewing(_FakeRepo(_payload()));
    await tester.pumpWidget(_host(container));
    await tester.pumpAndSettle();

    expect(find.byType(MethodStepCard), findsNWidgets(2));
    expect(find.text('Step 1'), findsOneWidget);
    expect(find.text('Step 2'), findsOneWidget);
    expect(find.text('Add a step'), findsOneWidget);
    expect(find.textContaining('read-only in v1'), findsNothing);
    expect(find.textContaining('editing lands later'), findsNothing);
  });

  testWidgets('typing in a step lands in the draft and survives the rebuild', (
    tester,
  ) async {
    _filterSemanticsAssertions();
    _tallViewport(tester);
    final repo = _FakeRepo(_payload());
    final container = await _reviewing(repo);
    await tester.pumpWidget(_host(container));
    await tester.pumpAndSettle();

    await tester.enterText(
      _stepField('Roast until charred.'),
      'Roast until properly charred.',
    );
    await tester.pumpAndSettle();

    final state = container.read(importControllerProvider) as ImportReconciling;
    expect(state.editedSteps![1].text, 'Roast until properly charred.');
    // The card is showing what the state holds — no stale controller.
    expect(find.text('Roast until properly charred.'), findsWidgets);
  });

  testWidgets('the edit rides the commit, and the chip is still keyed to its '
      'line index', (tester) async {
    _filterSemanticsAssertions();
    _tallViewport(tester);
    final repo = _FakeRepo(_payload());
    final container = await _reviewing(repo);
    await tester.pumpWidget(_host(container));
    await tester.pumpAndSettle();

    await tester.enterText(
      _stepField('Roast until charred.'),
      'Roast until properly charred.',
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Save recipe').first);
    await tester.pumpAndSettle();

    final steps = repo.committed!.steps;
    expect(steps, hasLength(2));
    // Step 1 is untouched, chip and all — refs are back to LINE INDEXES.
    expect(steps[0].tokens[1], const StepToken.ref(refs: [0], label: 'onions'));
    expect(
      steps[1].tokens.single,
      const TextToken(s: 'Roast until properly charred.'),
    );
  });

  testWidgets('an untouched method commits the payload steps byte-for-byte', (
    tester,
  ) async {
    _filterSemanticsAssertions();
    _tallViewport(tester);
    final repo = _FakeRepo(_payload());
    final container = await _reviewing(repo);
    await tester.pumpWidget(_host(container));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Save recipe').first);
    await tester.pumpAndSettle();

    expect(repo.committed!.steps, _payload().steps);
    // Nothing was stored either: the common path holds no draft at all.
    expect(
      (container.read(importControllerProvider) as ImportCommitted).recipeId,
      'recipe-1',
    );
  });

  test('the review host refuses to mint a line, and says why', () {
    final payload = _payload();
    final host = ImportMethodEditing(
      controller: ProviderContainer().read(importControllerProvider.notifier),
      state: ImportReconciling(
        payload: payload,
        resolutions: const [],
        header: const Recipe(id: 'draft', title: 'T', servingsBase: 4),
      ),
      preview: const Recipe(id: 'preview', title: 'T', servingsBase: 4),
    );
    expect(host.canAddLine, isFalse);
    expect(host.addLineReason, isNotNull);
    expect(host.ensureGroupId, throwsUnsupportedError);
    expect(() => host.addLineItem('g', _onion), throwsUnsupportedError);
    // …and the two review-only simplifications the interface allows.
    expect(host.substitution(), isNull);
    expect(host.relabels(), isEmpty);
  });
}
