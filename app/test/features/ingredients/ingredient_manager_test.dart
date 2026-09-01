/// Widget tests for the ingredients manager (step 8.5, design board
/// "Ingredients manager · v1" frames a–e).
///
/// The screen states that carry the plan's decisions are the ones worth
/// pinning: the stub band's **needs macros** wording (D5 overruled the
/// board's "needs density · macros"), the confirm CTA's gate and its
/// reversal, the delete refusal's count, the dashed density-locked chips
/// (D4), the honest USDA note (D7), and — frame (e) — a barcode scan
/// prefilling a draft that never completes a row (D1): its provenance and
/// ODbL credit carried, a panel-less product left blank with the reason, and
/// a dismissed scan changing nothing.
// The pumped ProviderScope IS the root scope of each test's tree (the same
// pattern connecting_view_test documents).
// ignore_for_file: scoped_providers_should_specify_dependencies
library;

import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:forui/forui.dart';
import 'package:go_router/go_router.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:mise/core/theme/mise_theme.dart';
import 'package:mise/core/units/macros.dart';
import 'package:mise/core/units/measure.dart';
import 'package:mise/core/units/units.dart';
import 'package:mise/features/ingredients/barcode/barcode_add.dart';
import 'package:mise/features/ingredients/barcode/barcode_scan_sheet.dart';
import 'package:mise/features/ingredients/data/ingredient_providers.dart';
import 'package:mise/features/ingredients/domain/ingredient.dart';
import 'package:mise/features/ingredients/domain/measure_repository.dart';
import 'package:mise/features/ingredients/presentation/density_entry.dart';
import 'package:mise/features/ingredients/presentation/ingredient_detail_view.dart';
import 'package:mise/features/ingredients/presentation/ingredient_list_view.dart';
import 'package:mise/features/ingredients/presentation/measures_editor.dart';
import 'package:mise/features/ingredients/presentation/new_ingredient_sheet.dart';
import 'package:mise/shared/dashed_border_box.dart';

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

/// An in-memory measure store: enough for the flesh-out form's embedded
/// editor (F2) and for asserting what the barcode pack-size tick wrote.
class _FakeMeasures implements MeasureRepository {
  _FakeMeasures([List<Measure> initial = const []]) : rows = [...initial];

  final List<Measure> rows;
  final _changes = StreamController<void>.broadcast();

  @override
  Stream<List<Measure>> watchMeasures(String ingredientId) async* {
    yield [...rows];
    yield* _changes.stream.map((_) => [...rows]);
  }

  @override
  Future<Measure> addMeasure({
    required String ingredientId,
    required String label,
    required double amount,
  }) async {
    final m = Measure(id: 'm-${rows.length}', label: label, amount: amount);
    rows.add(m);
    _changes.add(null);
    return m;
  }

  @override
  Future<void> softDeleteMeasure(String measureId) async {
    rows.removeWhere((m) => m.id == measureId);
    _changes.add(null);
  }
}

/// The flesh-out form is one long scroll; a phone-sized test viewport builds
/// only its top and every assertion below the fold fails for the wrong
/// reason. Give the whole form room instead of scrolling to each section.
void _tallScreen(WidgetTester tester) {
  tester.view.physicalSize = const Size(1000, 5000);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
}

/// The labels of every dashed (density-locked) admission chip on screen —
/// D4b's whole visible contract. Read off [DashedBorderBox] rather than a
/// key, because the dashed border IS what "locked" means on this form; the
/// alias/delete affordances share the box but never carry a unit label.
Set<String> _dashedChipLabels(WidgetTester tester) {
  final labels = <String>{};
  for (final box in find.byType(DashedBorderBox).evaluate()) {
    final texts = find.descendant(
      of: find.byWidget(box.widget),
      matching: find.byType(Text),
    );
    for (final t in texts.evaluate()) {
      final data = (t.widget as Text).data;
      if (data != null && kAllUnits.any((u) => u.label == data)) {
        labels.add(data);
      }
    }
  }
  return labels;
}

/// The category dropdown. `FSelect.rich` builds a private subclass, so this
/// is a predicate rather than `byType`.
final Finder _categorySelect = find.byWidgetPredicate(
  (w) => w is FSelect<String>,
);

/// The density entry's g/ml input (the only field it renders unless the
/// spoon phrasing is picked).
final Finder _densityField = find.descendant(
  of: find.byType(DensityEntry),
  matching: find.byType(TextField),
);

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

Widget _host(
  FakeIngredientRepo repo, {
  String at = '/ingredients',
  _FakeMeasures? measures,
}) {
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
      measureRepositoryProvider.overrideWithValue(measures ?? _FakeMeasures()),
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

    testWidgets('D4b, the full cycle: locked → a density unlocks → deleting '
        'it strips again, with the basis family live throughout', (
      tester,
    ) async {
      _filterSemanticsAssertions();
      _tallScreen(tester);
      // A piece-default per-g row with no density: mass is its basis family
      // (always sayable), volume is the density-derived side.
      const bareMango = Ingredient(
        id: 'mango',
        canonicalName: 'Mango',
        defaultUnit: pieces,
        status: IngredientStatus.complete,
        category: 'produce',
        macros: _mangoMacros,
      );
      final repo = FakeIngredientRepo(const [bareMango]);
      await tester.pumpWidget(_host(repo, at: '/ingredients/mango'));
      await tester.pumpAndSettle();

      // 1. Locked: the cross-family chips are drawn dashed, with the hint.
      expect(_dashedChipLabels(tester), {'tsp', 'tbsp', 'cup', 'ml'});
      expect(
        find.textContaining('dashed chips need a density'),
        findsOneWidget,
      );
      // The basis side is toggleable from the start — it never needed one.
      expect(_dashedChipLabels(tester), isNot(contains('g')));
      expect(_dashedChipLabels(tester), isNot(contains('piece')));

      // 2. Save a density: the same chips come live.
      await tester.enterText(_densityField, '0.66');
      await tester.pump();
      await tester.tap(find.widgetWithText(FButton, 'Save').first);
      await tester.pumpAndSettle();

      expect((await repo.byId('mango'))!.densityGPerMl, 0.66);
      expect(_dashedChipLabels(tester), isEmpty);
      expect(find.textContaining('dashed chips need a density'), findsNothing);

      // 3. Delete it: the strip leg, in the same write, with the consequence
      // named before it happens.
      await tester.tap(find.text('remove the density'));
      await tester.pumpAndSettle();
      expect(
        find.textContaining('lock again — those were sayable only because'),
        findsOneWidget,
      );
      await tester.tap(find.widgetWithText(FButton, 'Remove'));
      await tester.pumpAndSettle();

      final after = (await repo.byId('mango'))!;
      expect(after.densityGPerMl, isNull);
      // The cross-family units are gone from the stored list; the basis
      // family and the default unit's own family survive.
      expect(after.allowedUnits!.map((u) => u.id).toSet(), {'piece', 'g'});
      expect(_dashedChipLabels(tester), {'tsp', 'tbsp', 'cup', 'ml'});
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

    testWidgets('F2: measures are EDITABLE here — the shared 7.7 editor, not '
        'a read-only note', (tester) async {
      _filterSemanticsAssertions();
      _tallScreen(tester);
      final measures = _FakeMeasures(const [
        Measure(id: 'm-usda', label: 'mango, medium', amount: 207),
      ]);
      await tester.pumpWidget(
        _host(
          FakeIngredientRepo(const [_mango]),
          at: '/ingredients/mango',
          measures: measures,
        ),
      );
      await tester.pumpAndSettle();

      // The deferral is gone.
      expect(
        find.textContaining('added from a recipe line’s quantity sheet'),
        findsNothing,
      );
      expect(find.byType(MeasuresEditor), findsOneWidget);
      expect(find.text('mango, medium'), findsOneWidget);

      // Author one, in the row's basis unit.
      final add = find.descendant(
        of: find.byType(MeasuresEditor),
        matching: find.byType(TextField),
      );
      await tester.enterText(add.first, 'half cheek');
      await tester.enterText(add.last, '90');
      await tester.pump();
      await tester.tap(
        find.descendant(
          of: find.byType(MeasuresEditor),
          matching: find.widgetWithText(FButton, 'Save'),
        ),
      );
      await tester.pumpAndSettle();

      expect(measures.rows.last.label, 'half cheek');
      expect(measures.rows.last.amount, 90);

      // …and delete one.
      await tester.tap(find.byIcon(FLucideIcons.trash2).first);
      await tester.pumpAndSettle();
      expect(
        measures.rows.map((m) => m.label),
        isNot(contains('mango, medium')),
      );
    });

    testWidgets('F2: a volume-named measure label is still refused and '
        'redirected into the density entry (ADR-0008 §2)', (tester) async {
      _filterSemanticsAssertions();
      _tallScreen(tester);
      final measures = _FakeMeasures();
      await tester.pumpWidget(
        _host(
          FakeIngredientRepo(const [_mango]),
          at: '/ingredients/mango',
          measures: measures,
        ),
      );
      await tester.pumpAndSettle();

      final add = find.descendant(
        of: find.byType(MeasuresEditor),
        matching: find.byType(TextField),
      );
      await tester.enterText(add.first, 'cup');
      await tester.enterText(add.last, '120');
      await tester.pump();
      await tester.tap(
        find.descendant(
          of: find.byType(MeasuresEditor),
          matching: find.widgetWithText(FButton, 'Save'),
        ),
      );
      await tester.pumpAndSettle();

      // Nothing written, the reason on screen, and the density entry above
      // switched to the spoon phrasing with `cup` picked — the one door.
      expect(measures.rows, isEmpty);
      expect(
        find.textContaining('that mapping is the density'),
        findsOneWidget,
      );
      expect(find.text('weighs'), findsOneWidget);
    });

    testWidgets("F3: the category is a dropdown of the household's own "
        'categories — free text is gone', (tester) async {
      _filterSemanticsAssertions();
      _tallScreen(tester);
      final repo = FakeIngredientRepo(const [_mango, _curryLeaves, _yeast]);
      await tester.pumpWidget(_host(repo, at: '/ingredients/yeast'));
      await tester.pumpAndSettle();

      // The only free-text fields left on the form are the ones that MUST be
      // free text — the name and the four macro inputs. The category is not
      // among them.
      expect(_categorySelect, findsOneWidget);
      expect(find.widgetWithText(FTextField, 'e.g. produce'), findsNothing);

      // Opening it offers what the vocabulary actually carries, plus the
      // honest "none" — not a fixed taxonomy this app invented.
      await tester.tap(_categorySelect);
      await tester.pumpAndSettle();
      expect(find.text('produce'), findsWidgets);
      expect(find.text('pantry'), findsWidgets);
      expect(find.text('no category'), findsWidgets);

      await tester.tap(find.text('produce').last);
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FButton, 'Save').last);
      await tester.pumpAndSettle();

      expect((await repo.byId('yeast'))!.category, 'produce');
    });

    testWidgets('F3: a category nothing else carries is still offered, and a '
        'new one can be coined', (tester) async {
      _filterSemanticsAssertions();
      _tallScreen(tester);
      // Its own category is unique to it — the dropdown must not orphan it.
      const onlyOne = Ingredient(
        id: 'yeast',
        canonicalName: 'Nutritional yeast',
        defaultUnit: tsp,
        status: IngredientStatus.complete,
        category: 'oddments',
        macros: Macros(kcal: 385, protein: 50, carb: 36, fat: 5),
      );
      final repo = FakeIngredientRepo(const [_mango, onlyOne]);
      await tester.pumpWidget(_host(repo, at: '/ingredients/yeast'));
      await tester.pumpAndSettle();
      expect(find.text('oddments'), findsWidgets);

      await tester.tap(find.widgetWithText(FButton, 'New'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField).last, 'store cupboard');
      await tester.tap(find.widgetWithText(FButton, 'Use it'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FButton, 'Save').last);
      await tester.pumpAndSettle();

      expect((await repo.byId('yeast'))!.category, 'store cupboard');
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
    testWidgets('the Source segment renders all three, Barcode included and '
        'live', (tester) async {
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
      // The merge seam is gone: nothing on this sheet says the option is
      // waiting for another lane.
      expect(find.textContaining('wired at merge'), findsNothing);
      final barcode = tester.widget<MiseModeChip>(
        find.ancestor(
          of: find.text('Barcode'),
          matching: find.byType(MiseModeChip),
        ),
      );
      expect(barcode.enabled, isTrue);
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

  group('the add flow ▸ barcode — frame (e)', () {
    /// Walks the sheet to a resolved scan of [barcode] against [body].
    Future<void> scan(
      WidgetTester tester, {
      required String barcode,
      bool lookUp = true,
    }) async {
      await tester.tap(find.text('Add an ingredient'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Barcode'));
      await tester.pumpAndSettle();
      if (!lookUp) return;
      await tester.enterText(_scanField, barcode);
      await tester.pump();
      await tester.tap(find.text('Look up'));
      await tester.pumpAndSettle();
    }

    testWidgets('a found product prefills the draft: the name, the macros in '
        'the basis the label read them in, and the ODbL credit', (
      tester,
    ) async {
      _filterSemanticsAssertions();
      final repo = FakeIngredientRepo(const []);
      await tester.pumpWidget(
        _addHost(repo, body: _fixture('oatly_per_100ml')),
      );
      await tester.pumpAndSettle();

      await scan(tester, barcode: '7394376616020');

      // The result card the frame draws — product, provenance, ODbL.
      expect(find.text('FOUND · OPEN FOOD FACTS'), findsOneWidget);
      // Twice on purpose: the card names what OFF said, and the field below
      // is seeded with it.
      expect(find.text('Ruokaan Fraiche'), findsNWidgets(2));
      expect(
        find.text('Oatly · barcode 7394376616020 · Open Food Facts · ODbL'),
        findsOneWidget,
      );
      // Macros as the label read them: a 100ml panel stays per 100 ml.
      expect(find.text('177 kcal · 1P 15F 9C'), findsOneWidget);
      expect(
        find.textContaining('panel read per 100 ml — stored as the basis'),
        findsOneWidget,
      );
      // The name field is seeded, and still the user's to change.
      expect(_nameFieldText(tester), 'Ruokaan Fraiche');

      // F2: the pack size the mapper parsed ("200ml") is offered as a measure
      // — the board's opt-in tick, read into this row's own basis.
      expect(find.text('ALSO ADD A MEASURE'), findsOneWidget);
      expect(find.text('= 200 ml'), findsOneWidget);

      // The sheet scrolls since F2 (a panel plus a pack-size tick is taller
      // than a phone's sheet), so the CTA has to be brought into view — as a
      // thumb would.
      await tester.ensureVisible(find.text('Save & review'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Save & review'));
      await tester.pumpAndSettle();

      final created = repo.rows.single;
      // Provenance is the draft's own `off:<barcode>` value…
      expect(created.source, 'off:7394376616020');
      expect(
        created.macros,
        const Macros(kcal: 177, protein: 1, carb: 9, fat: 15),
      );
      expect(created.macrosBasis, MacrosBasis.perMl);
      // …and a machine's numbers do not complete a row (D1/D5).
      expect(created.status, IngredientStatus.stub);
      expect(created.densityGPerMl, isNull);
      expect(find.text('detail created-0'), findsOneWidget);
    });

    testWidgets('a sparse product (the NESQUIK shape) leaves the macros blank '
        'with the reason — never zeros', (tester) async {
      _filterSemanticsAssertions();
      final repo = FakeIngredientRepo(const []);
      await tester.pumpWidget(
        _addHost(repo, body: _fixture('nesquik_no_panel')),
      );
      await tester.pumpAndSettle();

      await scan(tester, barcode: '3033710065967');

      expect(find.text('NESQUIK Cacao'), findsNWidgets(2));
      expect(
        find.text('Open Food Facts has no nutrition panel for this product.'),
        findsOneWidget,
      );
      // No panel means no numbers at all — not a row of zeros.
      expect(find.textContaining('kcal'), findsNothing);

      // The sheet scrolls since F2 (a panel plus a pack-size tick is taller
      // than a phone's sheet), so the CTA has to be brought into view — as a
      // thumb would.
      await tester.ensureVisible(find.text('Save & review'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Save & review'));
      await tester.pumpAndSettle();

      final created = repo.rows.single;
      expect(created.macros, isNull);
      expect(created.source, 'off:3033710065967');
      expect(created.status, IngredientStatus.stub);
    });

    testWidgets('F2: the pack-size tick writes a real measure, in the row’s '
        'own basis', (tester) async {
      _filterSemanticsAssertions();
      final repo = FakeIngredientRepo(const []);
      final measures = _FakeMeasures();
      await tester.pumpWidget(
        _addHost(repo, body: _fixture('nesquik_no_panel'), measures: measures),
      );
      await tester.pumpAndSettle();

      await scan(tester, barcode: '3033710065967');

      // "1 kg" on a per-100 g row, read into grams — not stored as "1 kg".
      expect(find.text('= 1000 g'), findsOneWidget);
      // The label is the user's: OFF's quantity carries an amount, no noun.
      await tester.enterText(_packLabelField, 'bag');
      await tester.pump();

      await tester.ensureVisible(find.text('Save & review'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Save & review'));
      await tester.pumpAndSettle();

      expect(measures.rows.single.label, 'bag');
      expect(measures.rows.single.amount, 1000);
    });

    testWidgets('F2: unticking it writes nothing — a pack size is a '
        'suggestion, never an auto-add', (tester) async {
      _filterSemanticsAssertions();
      final repo = FakeIngredientRepo(const []);
      final measures = _FakeMeasures();
      await tester.pumpWidget(
        _addHost(repo, body: _fixture('oatly_per_100ml'), measures: measures),
      );
      await tester.pumpAndSettle();

      await scan(tester, barcode: '7394376616020');
      await tester.tap(find.byIcon(FLucideIcons.check));
      await tester.pumpAndSettle();
      expect(find.textContaining('not added'), findsOneWidget);

      await tester.ensureVisible(find.text('Save & review'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Save & review'));
      await tester.pumpAndSettle();

      expect(repo.rows, hasLength(1)); // the ingredient still lands
      expect(measures.rows, isEmpty); // the measure does not
    });

    testWidgets('F2: a pack size that cannot be bridged honestly is not '
        'offered at all (16 oz on a per-100 ml row, no density)', (
      tester,
    ) async {
      _filterSemanticsAssertions();
      final repo = FakeIngredientRepo(const []);
      final measures = _FakeMeasures();
      await tester.pumpWidget(
        _addHost(repo, body: _fixture('monster_per_100ml'), measures: measures),
      );
      await tester.pumpAndSettle();

      await scan(tester, barcode: '0070847811169');

      // A mass pack size on a volume-basis row needs a density, and a barcode
      // never carries one — so the tick is absent rather than guessing.
      expect(find.text('ALSO ADD A MEASURE'), findsNothing);

      await tester.ensureVisible(find.text('Save & review'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Save & review'));
      await tester.pumpAndSettle();
      expect(measures.rows, isEmpty);
    });

    testWidgets('a dismissed scan changes nothing — back to the segment as it '
        'was found', (tester) async {
      _filterSemanticsAssertions();
      final repo = FakeIngredientRepo(const []);
      await tester.pumpWidget(
        _addHost(repo, body: _fixture('oatly_per_100ml')),
      );
      await tester.pumpAndSettle();

      await scan(tester, barcode: '', lookUp: false);
      await tester.tap(
        find.descendant(
          of: find.byType(BarcodeScanSheet),
          matching: find.byIcon(FLucideIcons.x),
        ),
      );
      await tester.pumpAndSettle();

      // No card, no name, the Manual copy back, the manual CTA back.
      expect(find.text('FOUND · OPEN FOOD FACTS'), findsNothing);
      expect(_nameFieldText(tester), isEmpty);
      expect(
        find.textContaining('Type the name your recipes will read'),
        findsOneWidget,
      );
      expect(find.text('Create & flesh out'), findsOneWidget);
      expect(repo.rows, isEmpty);
    });
  });
}

/// A committed Open Food Facts payload, verbatim — the same fixtures the
/// mapper's table-driven test reads.
String _fixture(String name) => File(
  'test/features/ingredients/barcode/fixtures/$name.json',
).readAsStringSync();

/// The scan surface's typed-number field. Both sheets are in the tree at once
/// while the scanner is open, so this is scoped rather than positional.
final Finder _scanField = find.descendant(
  of: find.byType(BarcodeScanSheet),
  matching: find.byType(TextField),
);

/// The pack-size tick's label field — the second text field on the add sheet
/// (the name is the first).
final Finder _packLabelField = find
    .descendant(
      of: find.byType(NewIngredientSheet),
      matching: find.byType(TextField),
    )
    .at(1);

String _nameFieldText(WidgetTester tester) => tester
    .widget<TextField>(
      find
          .descendant(
            of: find.byType(NewIngredientSheet),
            matching: find.byType(TextField),
          )
          .first,
    )
    .controller!
    .text;

/// The add sheet as the list screen opens it, over a router that can receive
/// the push a create makes. [body] is what Open Food Facts answers with.
Widget _addHost(
  FakeIngredientRepo repo, {
  required String body,
  _FakeMeasures? measures,
}) {
  final router = GoRouter(
    initialLocation: '/',
    routes: [
      GoRoute(
        path: '/',
        builder: (_, _) => FScaffold(
          child: Builder(
            builder: (context) => FButton(
              onPress: () => showNewIngredientSheet(
                context,
                lookup: OffLookup(
                  client: MockClient((_) async => http.Response(body, 200)),
                ),
                cameraPane: (_, _) => const SizedBox.shrink(),
              ),
              child: const Text('Add an ingredient'),
            ),
          ),
        ),
      ),
      GoRoute(
        path: '/ingredients/:id',
        builder: (_, state) =>
            FScaffold(child: Text('detail ${state.pathParameters['id']}')),
      ),
    ],
  );
  addTearDown(router.dispose);
  return ProviderScope(
    overrides: [
      ingredientRepositoryProvider.overrideWithValue(repo),
      measureRepositoryProvider.overrideWithValue(measures ?? _FakeMeasures()),
    ],
    child: MaterialApp.router(
      routerConfig: router,
      builder: (context, child) => FTheme(data: miseThemeData(), child: child!),
    ),
  );
}
