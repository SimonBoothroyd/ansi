/// Widget tests for the ingredients manager (step 8.5, design board
/// "Ingredients manager · v1" frames a–d).
///
/// The screen states that carry the plan's decisions are the ones worth
/// pinning: the stub band's **needs macros** wording (D5 overruled the
/// board's "needs density · macros"), the confirm CTA's gate and its
/// reversal, the delete refusal's count, the dashed density-locked chips
/// (D4), the honest USDA note (D7), and the Barcode option's marked-inert
/// state (lane B's seam).
// The pumped ProviderScope IS the root scope of each test's tree (the same
// pattern connecting_view_test documents).
// ignore_for_file: scoped_providers_should_specify_dependencies
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:forui/forui.dart';
import 'package:go_router/go_router.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:mise/core/theme/mise_theme.dart';
import 'package:mise/core/units/macros.dart';
import 'package:mise/core/units/measure.dart';
import 'package:mise/core/units/units.dart';
import 'package:mise/features/ingredients/data/ingredient_providers.dart';
import 'package:mise/features/ingredients/domain/ingredient.dart';
import 'package:mise/features/ingredients/domain/measure_repository.dart';
import 'package:mise/features/ingredients/presentation/ingredient_detail_view.dart';
import 'package:mise/features/ingredients/presentation/ingredient_list_view.dart';
import 'package:mise/features/ingredients/presentation/new_ingredient_sheet.dart';

import '../../helpers/fake_ingredient_repository.dart';

const _mangoMacros = Macros(kcal: 60, protein: 1, carb: 15, fat: 0);

const _mango = Ingredient(
  id: 'mango',
  canonicalName: 'Mango',
  defaultUnit: pieces,
  status: IngredientStatus.complete,
  category: 'produce',
  densityGPerMl: 0.66,
  macros: _mangoMacros,
  measureCount: 3,
  source: 'seed',
);

const _curryLeaves = Ingredient(
  id: 'curry',
  canonicalName: 'Curry leaves, fresh',
  defaultUnit: g,
  status: IngredientStatus.stub,
  category: 'produce',
  source: 'usda_fdc:11216',
);

const _yeast = Ingredient(
  id: 'yeast',
  canonicalName: 'Nutritional yeast',
  defaultUnit: tsp,
  status: IngredientStatus.complete,
  category: 'pantry',
  macros: Macros(kcal: 385, protein: 50, carb: 36, fat: 5),
  source: 'seed',
);

class _NoMeasures implements MeasureRepository {
  @override
  Stream<List<Measure>> watchMeasures(String ingredientId) =>
      Stream.value(const []);

  @override
  Future<Measure> addMeasure({
    required String ingredientId,
    required String label,
    required double amount,
  }) => throw UnimplementedError();

  @override
  Future<void> softDeleteMeasure(String measureId) async {}
}

/// The flesh-out form is one long scroll; a phone-sized test viewport builds
/// only its top and every assertion below the fold fails for the wrong
/// reason. Give the whole form room instead of scrolling to each section.
void _tallScreen(WidgetTester tester) {
  tester.view.physicalSize = const Size(1000, 5000);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
}

/// The macro input for [label] — keyed on the form so position changes can't
/// silently retarget these.
Finder _macroField(String label) => find.descendant(
  of: find.byKey(ValueKey('macro-$label')),
  matching: find.byType(TextField),
);

/// Opening a Forui sheet with the semantics tree live trips a framework
/// assertion (tracker row `app/ui`); filter exactly that, as the other sheet
/// tests do.
void _filterSemanticsAssertions() {
  final reportError = FlutterError.onError!;
  FlutterError.onError = (details) {
    if ('${details.exception}'.contains('semantics.dart')) return;
    reportError(details);
  };
  addTearDown(() => FlutterError.onError = reportError);
}

Widget _host(FakeIngredientRepo repo, {String at = '/ingredients'}) {
  final router = GoRouter(
    initialLocation: at,
    routes: [
      GoRoute(
        path: '/ingredients',
        builder: (_, _) => const IngredientListView(),
      ),
      GoRoute(
        path: '/ingredients/:id',
        builder: (_, state) =>
            IngredientDetailView(ingredientId: state.pathParameters['id']!),
      ),
    ],
  );
  addTearDown(router.dispose);
  return ProviderScope(
    overrides: [
      ingredientRepositoryProvider.overrideWithValue(repo),
      measureRepositoryProvider.overrideWithValue(_NoMeasures()),
    ],
    child: MaterialApp.router(
      routerConfig: router,
      builder: (context, child) => FTheme(data: miseThemeData(), child: child!),
    ),
  );
}

void main() {
  group('the vocabulary list — frame (a)', () {
    testWidgets('the stub band sits on top of the whole vocabulary, and its '
        'hint reads NEEDS MACROS (D5 overruled "needs density · macros")', (
      tester,
    ) async {
      _filterSemanticsAssertions();
      await tester.pumpWidget(
        _host(FakeIngredientRepo(const [_mango, _curryLeaves, _yeast])),
      );
      await tester.pumpAndSettle();

      expect(find.text('Needs fleshing out'), findsOneWidget);
      expect(find.text('1 stub'), findsOneWidget);
      expect(find.text('needs macros · usda prefilled'), findsOneWidget);
      // …and the full vocabulary is below it, not replaced by it.
      expect(find.text('All ingredients · 3'), findsOneWidget);
      expect(find.text('Mango'), findsWidgets);
      expect(find.text('Nutritional yeast'), findsWidgets);
    });

    testWidgets('rows are the 7.7 picker rows: honest hints, no zeros for a '
        'stub, and a missing density named as an advisory', (tester) async {
      _filterSemanticsAssertions();
      await tester.pumpWidget(
        _host(FakeIngredientRepo(const [_mango, _curryLeaves, _yeast])),
      );
      await tester.pumpAndSettle();

      expect(find.text('produce · has density · 3 measures'), findsOneWidget);
      expect(
        find.text('pantry · no density — volume units locked'),
        findsOneWidget,
      );
      // The stub carries both: the advisory (no density) and the blocker
      // (needs macros). D5 keeps them distinct.
      expect(
        find.text(
          'produce · no density — volume units locked · needs macros — '
          'no zeros shown',
        ),
        findsOneWidget,
      );
      // A stub shows no macro line at all — never a row of zeros. Only the
      // two complete rows carry one.
      expect(find.textContaining('kcal ·'), findsNWidgets(2));
      expect(find.textContaining('60 kcal · 1P 0F 15C'), findsOneWidget);
    });

    testWidgets('no band at all when nothing is a stub', (tester) async {
      _filterSemanticsAssertions();
      await tester.pumpWidget(_host(FakeIngredientRepo(const [_mango])));
      await tester.pumpAndSettle();
      expect(find.text('Needs fleshing out'), findsNothing);
      expect(find.text('All ingredients · 1'), findsOneWidget);
    });

    testWidgets('tapping a row opens its flesh-out form', (tester) async {
      _filterSemanticsAssertions();
      await tester.pumpWidget(
        _host(FakeIngredientRepo(const [_mango, _curryLeaves])),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Mango').last);
      await tester.pumpAndSettle();
      expect(find.text('CANONICAL NAME'), findsOneWidget);
    });
  });

  group('the flesh-out form — frames (b) and (c)', () {
    testWidgets('a stub without macros: the CTA is refused with its reason, '
        'and the status line says it is out of the totals', (tester) async {
      _filterSemanticsAssertions();
      _tallScreen(tester);
      await tester.pumpWidget(
        _host(
          FakeIngredientRepo(const [_curryLeaves]),
          at: '/ingredients/curry',
        ),
      );
      await tester.pumpAndSettle();

      expect(
        find.text('Still a stub — left out of macro totals until confirmed.'),
        findsOneWidget,
      );
      expect(
        find.textContaining('needs macros — a row can’t count'),
        findsOneWidget,
      );
      final cta = tester.widget<FButton>(
        find.ancestor(
          of: find.text('Confirm — it counts from here'),
          matching: find.byType(FButton),
        ),
      );
      expect(cta.onPress, isNull);
    });

    testWidgets('a machine prefill is flagged, and says nothing counts until '
        'a human confirms (D1/D5)', (tester) async {
      _filterSemanticsAssertions();
      _tallScreen(tester);
      await tester.pumpWidget(
        _host(
          FakeIngredientRepo(const [_curryLeaves]),
          at: '/ingredients/curry',
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Filled in for you — check it'), findsOneWidget);
      expect(
        find.textContaining('Nothing counts until you confirm.'),
        findsOneWidget,
      );
    });

    testWidgets('typing the four macros arms the CTA, and confirming flips '
        'the row to complete — density never asked for', (tester) async {
      _filterSemanticsAssertions();
      _tallScreen(tester);
      final repo = FakeIngredientRepo(const [_curryLeaves]);
      await tester.pumpWidget(_host(repo, at: '/ingredients/curry'));
      await tester.pumpAndSettle();

      for (final (label, value) in const [
        ('kcal', '108'),
        ('protein', '6'),
        ('carb', '19'),
        ('fat', '1'),
      ]) {
        await tester.enterText(_macroField(label), value);
        await tester.pump();
      }

      await tester.tap(find.text('Confirm — it counts from here'));
      await tester.pumpAndSettle();

      final row = await repo.byId('curry');
      expect(row!.status, IngredientStatus.complete);
      expect(row.macros, const Macros(kcal: 108, protein: 6, carb: 19, fat: 1));
      expect(row.densityGPerMl, isNull); // never required (D5)
      expect(find.text('Confirmed — it counts from here.'), findsOneWidget);
    });

    testWidgets(
      'a complete row opens here too, and the confirm is reversible',
      (tester) async {
        _filterSemanticsAssertions();
        _tallScreen(tester);
        final repo = FakeIngredientRepo(const [_mango]);
        await tester.pumpWidget(_host(repo, at: '/ingredients/mango'));
        await tester.pumpAndSettle();

        expect(
          find.text('Complete — counts in conversions and macro totals.'),
          findsOneWidget,
        );
        await tester.tap(find.text('return it to a stub'));
        await tester.pumpAndSettle();

        final row = await repo.byId('mango');
        expect(row!.status, IngredientStatus.stub);
        // Unconfirming stops it counting; it does not erase what was typed.
        expect(row.macros, _mangoMacros);
      },
    );

    testWidgets('THE MANGO CHIPS (D4): a piece default with a density admits '
        'cup, and nothing is dashed', (tester) async {
      _filterSemanticsAssertions();
      _tallScreen(tester);
      await tester.pumpWidget(
        _host(FakeIngredientRepo(const [_mango]), at: '/ingredients/mango'),
      );
      await tester.pumpAndSettle();
      for (final label in ['piece', 'g', 'cup', 'tbsp', 'tsp', 'ml']) {
        expect(find.text(label), findsWidgets, reason: label);
      }
      expect(find.textContaining('dashed chips need a density'), findsNothing);
    });

    testWidgets('a density-less row draws the locked chips and says a missing '
        'density blocks nothing', (tester) async {
      _filterSemanticsAssertions();
      _tallScreen(tester);
      await tester.pumpWidget(
        _host(
          FakeIngredientRepo(const [_curryLeaves]),
          at: '/ingredients/curry',
        ),
      );
      await tester.pumpAndSettle();
      expect(
        find.textContaining('dashed chips need a density'),
        findsOneWidget,
      );
      expect(
        find.textContaining('macros are what a row needs to count'),
        findsOneWidget,
      );
    });

    testWidgets('delete is refused with the count while a live line points '
        'here', (tester) async {
      _filterSemanticsAssertions();
      _tallScreen(tester);
      final repo = FakeIngredientRepo(
        const [_mango],
        references: const {'mango': (recipeCount: 3, lineCount: 4)},
      );
      await tester.pumpWidget(_host(repo, at: '/ingredients/mango'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Delete ingredient'));
      await tester.pumpAndSettle();

      expect(
        find.textContaining('Still used by 3 recipes (4 lines)'),
        findsOneWidget,
      );
      expect(repo.rows, hasLength(1)); // untouched
    });

    testWidgets('an unreferenced row deletes and leaves the form', (
      tester,
    ) async {
      _filterSemanticsAssertions();
      _tallScreen(tester);
      final repo = FakeIngredientRepo(const [_mango]);
      await tester.pumpWidget(_host(repo, at: '/ingredients/mango'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Delete ingredient'));
      await tester.pumpAndSettle();
      expect(repo.rows, isEmpty);
    });

    testWidgets('renaming rewrites the match text (D6) and says so on the '
        'form', (tester) async {
      _filterSemanticsAssertions();
      _tallScreen(tester);
      final repo = FakeIngredientRepo(const [_curryLeaves]);
      await tester.pumpWidget(_host(repo, at: '/ingredients/curry'));
      await tester.pumpAndSettle();

      expect(
        find.textContaining('renaming rewrites the match text'),
        findsOneWidget,
      );
      await tester.enterText(find.byType(TextField).first, 'Curry leaf, dried');
      // The last "Save" is the form's; the density entry has one too.
      await tester.tap(find.widgetWithText(FButton, 'Save').last);
      await tester.pumpAndSettle();

      expect(repo.matchTextById['curry'], 'curry leaf dried');
    });

    testWidgets('the USDA button is honest about what it can do: usda_food '
        'never reaches the device, so it re-reads the row (D7)', (
      tester,
    ) async {
      _filterSemanticsAssertions();
      _tallScreen(tester);
      final plain = _curryLeaves.copyWith(source: 'manual');
      await tester.pumpWidget(
        _host(FakeIngredientRepo([plain]), at: '/ingredients/curry'),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('Look up in USDA'));
      await tester.pumpAndSettle();
      expect(
        find.textContaining('The lookup runs on the server'),
        findsOneWidget,
      );
    });
  });

  group('the add flow — frame (d)', () {
    testWidgets('the Source segment renders all three, with Barcode inert and '
        'labelled as landing at merge', (tester) async {
      _filterSemanticsAssertions();
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            ingredientRepositoryProvider.overrideWithValue(
              FakeIngredientRepo(const []),
            ),
          ],
          child: MaterialApp(
            home: FTheme(
              data: miseThemeData(),
              child: const FScaffold(child: NewIngredientSheet()),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Manual'), findsOneWidget);
      expect(find.text('USDA FDC'), findsOneWidget);
      expect(find.text('Barcode'), findsOneWidget);
      expect(find.textContaining('Barcode — wired at merge'), findsOneWidget);

      // Tapping the inert option changes nothing — no half-built flow opens.
      await tester.tap(find.text('Barcode'));
      await tester.pumpAndSettle();
      expect(
        find.textContaining('Type the name your recipes will read'),
        findsOneWidget,
      );
    });

    testWidgets('the USDA source explains that the lookup is server-side, not '
        'a catalogue this app browses (ADR-0005)', (tester) async {
      _filterSemanticsAssertions();
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            ingredientRepositoryProvider.overrideWithValue(
              FakeIngredientRepo(const []),
            ),
          ],
          child: MaterialApp(
            home: FTheme(
              data: miseThemeData(),
              child: const FScaffold(child: NewIngredientSheet()),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('USDA FDC'));
      await tester.pumpAndSettle();
      expect(find.textContaining('it never leaves the server'), findsOneWidget);
    });
  });
}
