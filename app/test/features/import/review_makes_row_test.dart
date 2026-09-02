/// The review screen's MAKES row (step 8.6 / D2 · D9, board frame h — the
/// Review half): the `yield_raw` source line stays visible, the fields are
/// prefilled only from a plain amount + unit, and the yield never gates Save.
// The pumped ProviderScope IS the root scope of each test's tree.
// ignore_for_file: scoped_providers_should_specify_dependencies
library;

import 'package:ansi/core/theme/ansi_theme.dart';
import 'package:ansi/core/units/macros.dart';
import 'package:ansi/core/units/measure.dart';
import 'package:ansi/core/units/units.dart';
import 'package:ansi/features/import/data/import_providers.dart';
import 'package:ansi/features/import/domain/commit_payload.dart';
import 'package:ansi/features/import/domain/import_repository.dart';
import 'package:ansi/features/import/domain/reconciliation_payload.dart';
import 'package:ansi/features/import/presentation/import_view_models.dart';
import 'package:ansi/features/import/presentation/reconciliation_view.dart';
import 'package:ansi/features/ingredients/data/ingredient_providers.dart';
import 'package:ansi/features/ingredients/domain/ingredient.dart';
import 'package:ansi/features/ingredients/domain/ingredient_repository.dart';
import 'package:ansi/features/ingredients/domain/measure_repository.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:forui/forui.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

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
  defaultUnit: pieces,
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

/// One clean auto-matched line, so Save's gate is about the yield and nothing
/// else, with whatever the page printed about what it makes.
ReconciliationPayload _payload(String? yieldRaw) => ReconciliationPayload(
  title: 'Sausage Sliders',
  servingsBase: 8,
  yieldRaw: yieldRaw,
  groups: const [
    ReconGroup(
      lines: [
        ReconLine(
          raw: RawLineItem(
            ingredientText: 'onion, diced',
            qty: 1,
            unit: 'piece',
            rawAmount: '1 onion',
          ),
          band: MatchBand.auto,
          candidates: [
            MatchCandidate(ingredientId: 'ing-onion', canonicalName: 'Onion'),
          ],
        ),
      ],
    ),
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

Future<ProviderContainer> _reviewing(String? yieldRaw) async {
  final container = ProviderContainer(
    overrides: [
      importRepositoryProvider.overrideWithValue(_FakeRepo(_payload(yieldRaw))),
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

/// Forui's text field trips a semantics merge assertion under the test
/// harness — not this suite's concern.
void _filterSemanticsAssertions() {
  final reportError = FlutterError.onError!;
  FlutterError.onError = (details) {
    if ('${details.exception}'.contains('semantics.dart')) return;
    reportError(details);
  };
  addTearDown(() => FlutterError.onError = reportError);
}

void main() {
  testWidgets('a plain amount + unit prefills the row, over its source line', (
    tester,
  ) async {
    _filterSemanticsAssertions();
    final container = await _reviewing('MAKES: 8 SLIDERS');
    await tester.pumpWidget(_host(container));
    await tester.pumpAndSettle();

    expect(find.text('MAKES'), findsOneWidget);
    // The source line is always visible — the reference the field is filled
    // from, exactly as the ingredient cards show theirs.
    expect(find.text('from source:  MAKES: 8 SLIDERS'), findsOneWidget);

    final state = container.read(importControllerProvider) as ImportReconciling;
    expect(state.yieldQty, 8);
    expect(state.yieldUnit, pieces);
    // And it is rendered, not just held: "8" in the amount field, "piece" on
    // the unit selector.
    expect(find.text('8'), findsWidgets);
    expect(find.text('piece'), findsWidgets);
    // Nothing to apologise for — the empty-state hint is gone.
    expect(find.textContaining('didn’t say a number'), findsNothing);
  });

  testWidgets('anything fancier leaves the fields EMPTY over the visible '
      'source text — never a guess', (tester) async {
    _filterSemanticsAssertions();
    final container = await _reviewing('MAKES ENOUGH FOR A CROWD');
    await tester.pumpWidget(_host(container));
    await tester.pumpAndSettle();

    expect(find.text('from source:  MAKES ENOUGH FOR A CROWD'), findsOneWidget);
    final state = container.read(importControllerProvider) as ImportReconciling;
    expect(state.yieldQty, isNull);
    expect(state.yieldUnit, isNull);
    expect(find.textContaining('didn’t say a number'), findsOneWidget);
  });

  testWidgets('a page that printed nothing shows the row with no source line', (
    tester,
  ) async {
    _filterSemanticsAssertions();
    final container = await _reviewing(null);
    await tester.pumpWidget(_host(container));
    await tester.pumpAndSettle();

    expect(find.text('MAKES'), findsOneWidget);
    expect(find.textContaining('from source:  MAKES'), findsNothing);
    expect(find.textContaining('didn’t say what this makes'), findsOneWidget);
  });

  testWidgets('the yield NEVER gates Save — an unset one still saves, and a '
      'set one rides the commit', (tester) async {
    _filterSemanticsAssertions();
    final container = await _reviewing('MAKES ENOUGH FOR A CROWD');
    await tester.pumpWidget(_host(container));
    await tester.pumpAndSettle();

    // Every line is clean, so Save is live with no yield stated at all.
    expect(find.text('Save recipe'), findsOneWidget);
    final button = tester.widget<FButton>(
      find.ancestor(
        of: find.text('Save recipe'),
        matching: find.byType(FButton),
      ),
    );
    expect(button.onPress, isNotNull);

    // Setting one writes it through to the commit.
    container.read(importControllerProvider.notifier).setYield(1, cup);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Save recipe'));
    await tester.pumpAndSettle();

    final repo = container.read(importRepositoryProvider) as _FakeRepo;
    expect(repo.committed!.yieldQty, 1);
    expect(repo.committed!.yieldUnit, cup);
  });

  testWidgets('typing an amount with no unit picked states the honest count', (
    tester,
  ) async {
    _filterSemanticsAssertions();
    final container = await _reviewing(null);
    await tester.pumpWidget(_host(container));
    await tester.pumpAndSettle();

    // The MAKES amount is the first field on the screen.
    await tester.enterText(find.byType(TextField).first, '12');
    await tester.pumpAndSettle();

    final state = container.read(importControllerProvider) as ImportReconciling;
    expect(state.yieldQty, 12);
    expect(state.yieldUnit, pieces);
  });
}
