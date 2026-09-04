/// The review screen's header (plan 0025 #4, board frame b): the editor's
/// own `RecipeHeaderForm` hosted by the import controller, with what only
/// the review knows drawn AROUND it — the source-notes strip above, "not
/// printed — set it" beside SERVES, "from source: …" under MAKES — and the
/// whole header riding the commit. Nothing in it gates Save.
// The pumped ProviderScope IS the root scope of each test's tree.
// ignore_for_file: scoped_providers_should_specify_dependencies
library;

import 'package:ansi/core/theme/ansi_theme.dart';
import 'package:ansi/core/units/macros.dart';
import 'package:ansi/core/units/measure.dart';
import 'package:ansi/core/units/units.dart';
import 'package:ansi/features/books/data/book_providers.dart';
import 'package:ansi/features/books/domain/book.dart';
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
import 'package:ansi/features/recipes/presentation/recipe_header_form.dart';
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

/// One clean auto-matched line, so Save's gate is about the header and
/// nothing else, with whatever the page printed about the rest.
ReconciliationPayload _payload({
  String? yieldRaw,
  int? servingsBase = 8,
  TimeRange? cookTime,
  List<String> parseWarnings = const [],
}) => ReconciliationPayload(
  title: 'Sausage Sliders',
  servingsBase: servingsBase,
  yieldRaw: yieldRaw,
  cookTimeSeconds: cookTime,
  parseWarnings: parseWarnings,
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

Future<ProviderContainer> _reviewing(ReconciliationPayload payload) async {
  final container = ProviderContainer(
    overrides: [
      importRepositoryProvider.overrideWithValue(_FakeRepo(payload)),
      ingredientRepositoryProvider.overrideWithValue(_FakeIngredientRepo()),
      measureRepositoryProvider.overrideWithValue(_FakeMeasureRepo()),
      bookRepositoryProvider.overrideWithValue(
        const FakeBookRepository([Book(id: 'b1', name: 'Our Cookbook')]),
      ),
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

ImportReconciling _state(ProviderContainer container) =>
    container.read(importControllerProvider) as ImportReconciling;

/// A form field, found by what it is showing.
Finder _field(String text) => find.byWidgetPredicate(
  (w) => w is EditableText && w.controller.text == text,
);

/// The review is one long ListView; give it a surface tall enough to build
/// the whole header and Save, so nothing here drives a scroll.
void _tallViewport(WidgetTester tester) {
  tester.view.physicalSize = const Size(1200, 4400);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
}

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
  testWidgets('the source-notes strip sits ABOVE the form, and the form is '
      'the editor’s: every section, title editable', (tester) async {
    _filterSemanticsAssertions();
    _tallViewport(tester);
    final container = await _reviewing(
      _payload(parseWarnings: ['Serves was not printed.']),
    );
    await tester.pumpWidget(_host(container));
    await tester.pumpAndSettle();

    for (final section in kRecipeHeaderSections) {
      expect(find.text(section.label), findsOneWidget);
    }
    // Frame b: the strip reads as "about the whole import" before the fields
    // begin — it used to sit under a read-only title.
    final strip = tester.getTopLeft(find.text('WHAT WE COULD NOT READ')).dy;
    final title = tester.getTopLeft(find.text('TITLE')).dy;
    expect(strip, lessThan(title));
    // The title is a field now, not a heading.
    expect(_field('Sausage Sliders'), findsOneWidget);
  });

  testWidgets('"not printed — set it" sits beside SERVES when the page '
      'printed no serving count', (tester) async {
    _filterSemanticsAssertions();
    _tallViewport(tester);
    final container = await _reviewing(_payload(servingsBase: null));
    await tester.pumpWidget(_host(container));
    await tester.pumpAndSettle();
    expect(find.text('not printed — set it'), findsOneWidget);
    expect(_state(container).header.servingsBase, 1);
  });

  testWidgets('…and not when it did', (tester) async {
    _filterSemanticsAssertions();
    _tallViewport(tester);
    final container = await _reviewing(_payload());
    await tester.pumpWidget(_host(container));
    await tester.pumpAndSettle();
    expect(find.text('not printed — set it'), findsNothing);
    expect(_state(container).header.servingsBase, 8);
  });

  testWidgets('a plain amount + unit prefills MAKES, over its source line', (
    tester,
  ) async {
    _filterSemanticsAssertions();
    _tallViewport(tester);
    final container = await _reviewing(_payload(yieldRaw: 'MAKES: 8 SLIDERS'));
    await tester.pumpWidget(_host(container));
    await tester.pumpAndSettle();

    // The source line is always visible — the reference the field is filled
    // from, exactly as the ingredient cards show theirs.
    expect(find.text('from source:  MAKES: 8 SLIDERS'), findsOneWidget);
    expect(_state(container).header.yields, [(qty: 8.0, unit: pieces)]);
    // And it is rendered, not just held: "8" in the amount field, "piece" on
    // the unit selector — with the editor's second-denomination door open.
    expect(_field('8'), findsOneWidget);
    expect(find.text('piece'), findsWidgets);
    expect(find.text('Another denomination'), findsOneWidget);
    expect(find.textContaining('didn’t say a number'), findsNothing);
  });

  testWidgets('anything fancier leaves MAKES empty over the visible source '
      'text — never a guess', (tester) async {
    _filterSemanticsAssertions();
    _tallViewport(tester);
    final container = await _reviewing(
      _payload(yieldRaw: 'MAKES ENOUGH FOR A CROWD'),
    );
    await tester.pumpWidget(_host(container));
    await tester.pumpAndSettle();

    expect(find.text('from source:  MAKES ENOUGH FOR A CROWD'), findsOneWidget);
    expect(_state(container).header.yields, isEmpty);
    expect(find.textContaining('didn’t say a number'), findsOneWidget);
  });

  testWidgets('a page that printed nothing shows MAKES with no source line', (
    tester,
  ) async {
    _filterSemanticsAssertions();
    _tallViewport(tester);
    final container = await _reviewing(_payload());
    await tester.pumpWidget(_host(container));
    await tester.pumpAndSettle();

    expect(find.textContaining('from source:  MAKES'), findsNothing);
    expect(find.textContaining('didn’t say what this makes'), findsOneWidget);
  });

  testWidgets('TIMES is prefilled from the page; SHELF LIFE starts unset and '
      'FILE UNDER on the default book', (tester) async {
    _filterSemanticsAssertions();
    _tallViewport(tester);
    final container = await _reviewing(
      _payload(cookTime: const TimeRange(lowSeconds: 2100, highSeconds: 2100)),
    );
    await tester.pumpWidget(_host(container));
    await tester.pumpAndSettle();

    expect(find.text('35 min'), findsOneWidget);
    // Total, and the fridge window, read "not set" in the stepper's own
    // muted voice — nothing is invented for either.
    expect(find.text('not set'), findsNWidgets(2));
    // 0028 E9: the review states its filing on one line, and it is filed
    // from the start — a blank a human has to fill is never honest.
    expect(find.text('OUR COOKBOOK · UNSECTIONED'), findsOneWidget);
    final header = _state(container).header;
    expect(header.cookTimeSeconds, 2100);
    expect(header.totalTimeSeconds, isNull);
    expect(header.keepsForDays, isNull);
    expect(header.freezable, isFalse);
    expect(header.bookId, 'b1');
    expect(header.sectionId, isNull);
  });

  testWidgets('nothing in the header gates Save, and the whole header rides '
      'the commit', (tester) async {
    _filterSemanticsAssertions();
    _tallViewport(tester);
    final container = await _reviewing(
      _payload(yieldRaw: 'MAKES ENOUGH FOR A CROWD'),
    );
    await tester.pumpWidget(_host(container));
    await tester.pumpAndSettle();

    // Every line is clean, so Save is live with no yield, no times and no
    // shelf life stated at all.
    final button = tester.widget<FButton>(
      find.ancestor(
        of: find.text('Save recipe'),
        matching: find.byType(FButton),
      ),
    );
    expect(button.onPress, isNotNull);

    // Setting the facts the review could not carry before writes every one
    // of them through to the commit.
    container.read(importControllerProvider.notifier)
      ..setTitle('Sausage Sliders, ours')
      ..setYield(8, pieces)
      ..setSecondYield(1.2, kg)
      ..setCookTime(35 * 60)
      ..setTotalTime(70 * 60)
      ..setKeepsForDays(3)
      ..setFreezable(true)
      ..setFreezerDays(60)
      ..setSection('s-quick');
    await tester.pumpAndSettle();
    await tester.tap(find.text('Save recipe'));
    await tester.pumpAndSettle();

    final committed =
        (container.read(importRepositoryProvider) as _FakeRepo).committed!;
    expect(committed.title, 'Sausage Sliders, ours');
    expect(committed.servingsBase, 8);
    expect((committed.yieldQty, committed.yieldUnit), (8, pieces));
    expect((committed.yieldQty2, committed.yieldUnit2), (1.2, kg));
    expect(committed.cookTimeSeconds, 2100);
    expect(committed.totalTimeSeconds, 4200);
    expect(committed.keepsForDays, 3);
    expect(committed.freezable, isTrue);
    expect(committed.freezerDays, 60);
    expect(committed.bookId, 'b1');
    expect(committed.sectionId, 's-quick');
  });
}
