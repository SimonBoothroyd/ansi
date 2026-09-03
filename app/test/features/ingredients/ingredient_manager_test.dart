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
import 'dart:convert';
import 'dart:io';

import 'package:ansi/core/theme/ansi_theme.dart';
import 'package:ansi/core/units/macros.dart';
import 'package:ansi/core/units/measure.dart';
import 'package:ansi/core/units/units.dart';
import 'package:ansi/features/ingredients/barcode/barcode_add.dart';
import 'package:ansi/features/ingredients/barcode/barcode_scan_sheet.dart';
import 'package:ansi/features/ingredients/data/ingredient_providers.dart';
import 'package:ansi/features/ingredients/domain/allowed_units.dart';
import 'package:ansi/features/ingredients/domain/ingredient.dart';
import 'package:ansi/features/ingredients/domain/measure_repository.dart';
import 'package:ansi/features/ingredients/domain/normalize.dart';
import 'package:ansi/features/ingredients/domain/usda_probe.dart';
import 'package:ansi/features/ingredients/presentation/density_entry.dart';
import 'package:ansi/features/ingredients/presentation/ingredient_detail_view.dart';
import 'package:ansi/features/ingredients/presentation/ingredient_list_view.dart';
import 'package:ansi/features/ingredients/presentation/measures_editor.dart';
import 'package:ansi/features/ingredients/presentation/new_ingredient_sheet.dart';
import 'package:ansi/features/ingredients/presentation/serving_row.dart';
import 'package:ansi/shared/dashed_border_box.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:forui/forui.dart';
import 'package:go_router/go_router.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

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

/// The D4c shape the owner hit: a cup default on a per-100 g row with no
/// density, carrying an `allowed_units` list materialized under the looser
/// pre-D4c rule.
const _blackRice = Ingredient(
  id: 'rice',
  canonicalName: 'Black rice',
  defaultUnit: cup,
  status: IngredientStatus.stub,
  category: 'pantry',
  allowedUnits: [cup, tbsp, ml, l, g, kg],
  source: 'manual',
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
  Future<Map<String, List<Measure>>> measuresByIngredients(
    Set<String> ids,
  ) async => {
    for (final id in ids) id: [...rows],
  };

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

/// What the fake probe answers with — the curry-leaf candidate the server's
/// trigram match would have returned.
const _usdaAnswer = UsdaCandidate(
  fdcId: 11216,
  source: 'usda_fdc:11216',
  score: 0.71,
  densityGPerMl: 0.35,
  macros: Macros(kcal: 108, protein: 6, carb: 19, fat: 1),
);

/// Records what it was asked. F1's whole point is that the question is about
/// the name as SAVED, so the recording is the assertion.
class _RecordingProbe implements UsdaProbe {
  _RecordingProbe(this.answer);

  final UsdaCandidate? answer;
  final asked = <String>[];

  @override
  Future<UsdaCandidate?> probe(String matchText) async {
    asked.add(matchText);
    return answer;
  }
}

/// The offline / unconfigured answer: nothing, without throwing.
class _SilentProbe implements UsdaProbe {
  const _SilentProbe();

  @override
  Future<UsdaCandidate?> probe(String matchText) async => null;
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

/// What a macro field currently SHOWS — the assertion G1 exists for: the row
/// having the numbers is not the same as the open form having them.
String _macroFieldText(WidgetTester tester, String label) =>
    tester.widget<TextField>(_macroField(label)).controller!.text;

/// The per-serving mode's serving amount / name inputs (plan 0027 M-D1),
/// keyed on the shared row so both hosts' tests find the same field.
final Finder _servingAmountField = find.descendant(
  of: find.byKey(const ValueKey('serving-amount')),
  matching: find.byType(TextField),
);
final Finder _servingNameField = find.descendant(
  of: find.byKey(const ValueKey('serving-name')),
  matching: find.byType(TextField),
);
String _fieldText(WidgetTester tester, Finder field) =>
    tester.widget<TextField>(field).controller!.text;

/// The four macros the form enters, in the labelled order.
Future<void> _typeMacros(
  WidgetTester tester, {
  required String kcal,
  required String protein,
  required String carb,
  required String fat,
}) async {
  for (final (label, value) in [
    ('kcal', kcal),
    ('protein', protein),
    ('carb', carb),
    ('fat', fat),
  ]) {
    await tester.enterText(_macroField(label), value);
    await tester.pump();
  }
}

/// The form's own Save — the last one on the page (the density entry and
/// the measures editor each draw their own above it).
Future<void> _saveForm(WidgetTester tester) async {
  await tester.tap(find.widgetWithText(FButton, 'Save').last);
  await tester.pumpAndSettle();
}

/// The measures editor's label input — a field the form's own save never
/// touches, so a pending edit in it is the control for "did the re-seed
/// clobber anything else".
final Finder _measureLabelField = find
    .descendant(
      of: find.byType(MeasuresEditor),
      matching: find.byType(TextField),
    )
    .first;

/// A default-unit chip by label, scoped to the D4c selector row.
AnsiModeChip _defaultUnitChip(WidgetTester tester, String label) =>
    tester.widget<AnsiModeChip>(
      find.descendant(
        of: find.byKey(const ValueKey('default-unit-row')),
        matching: find.widgetWithText(AnsiModeChip, label),
      ),
    );

/// A phone-width viewport, tall enough that the whole form still builds:
/// width is what an overflow is about (G2), and the form is one long scroll.
void _phoneWidth(WidgetTester tester) {
  tester.view.physicalSize = const Size(402, 4000);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
}

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
  UsdaProbe? probe,
  OffLookup? lookup,
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
        builder: (_, state) => IngredientDetailView(
          ingredientId: state.pathParameters['id']!,
          // The form's own scan (plan 0025 #8): a test hands in the client
          // and a camera-less pane the way the add sheet's tests do.
          lookup: lookup,
          cameraPane: lookup == null ? null : (_, _) => const SizedBox.shrink(),
        ),
      ),
    ],
  );
  addTearDown(router.dispose);
  return ProviderScope(
    overrides: [
      ingredientRepositoryProvider.overrideWithValue(repo),
      measureRepositoryProvider.overrideWithValue(measures ?? _FakeMeasures()),
      usdaProbeProvider.overrideWithValue(probe ?? const _SilentProbe()),
    ],
    child: MaterialApp.router(
      routerConfig: router,
      builder: (context, child) => FTheme(data: ansiThemeData(), child: child!),
    ),
  );
}

/// The density section on its own, inside the form's own page padding — the
/// width G2 is about, without the rest of the scroll in the way.
Widget _densityHost(Ingredient ingredient) => ProviderScope(
  overrides: [
    ingredientRepositoryProvider.overrideWithValue(
      FakeIngredientRepo([ingredient]),
    ),
  ],
  child: MaterialApp(
    home: FTheme(
      data: ansiThemeData(),
      child: FScaffold(
        childPad: false,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: DensityEntry(
            ingredient: ingredient,
            redirectedSpoon: null,
            onSaved: (_) {},
          ),
        ),
      ),
    ),
  ),
);

/// The add sheet on its own, with the probe overridable — the creation flows
/// are where D7b's "born enriched" lives.
Widget _sheetHost(FakeIngredientRepo repo, {UsdaProbe? probe}) => ProviderScope(
  overrides: [
    ingredientRepositoryProvider.overrideWithValue(repo),
    measureRepositoryProvider.overrideWithValue(_FakeMeasures()),
    usdaProbeProvider.overrideWithValue(probe ?? const _SilentProbe()),
  ],
  child: MaterialApp(
    home: FTheme(
      data: ansiThemeData(),
      child: const FScaffold(child: NewIngredientSheet()),
    ),
  ),
);

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

    testWidgets('J4: the list comes back from the detail route still showing '
        'the band and the header — a round-trip is not a search', (
      tester,
    ) async {
      _filterSemanticsAssertions();
      _tallScreen(tester);
      final repo = FakeIngredientRepo(const [_mango, _curryLeaves, _yeast]);
      await tester.pumpWidget(_host(repo));
      await tester.pumpAndSettle();

      // Initial render is fine — this is the state we must get back to.
      expect(find.text('Needs fleshing out'), findsOneWidget);
      expect(find.text('All ingredients · 3'), findsOneWidget);

      // Push the detail, rename + save, pop back.
      await tester.tap(find.text('Mango').first);
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField).first, 'Mango, ripe');
      await tester.pump();
      await tester.tap(find.widgetWithText(FButton, 'Save').last);
      await tester.pumpAndSettle();
      expect((await repo.byId('mango'))!.canonicalName, 'Mango, ripe');

      // Back out through the form's own chevron, the way the owner did.
      await tester.tap(find.byType(FHeaderAction).first);
      await tester.pumpAndSettle();

      // The user typed nothing into search, so the list must not be in its
      // search-results branch.
      expect(find.text('Needs fleshing out'), findsOneWidget);
      expect(find.text('All ingredients · 3'), findsOneWidget);
      expect(find.text('Mango, ripe'), findsWidgets);
    });

    testWidgets('J4: typing still collapses the list into results, and '
        'clearing the field brings the band and the header straight back', (
      tester,
    ) async {
      _filterSemanticsAssertions();
      _tallScreen(tester);
      await tester.pumpWidget(
        _host(FakeIngredientRepo(const [_mango, _curryLeaves, _yeast])),
      );
      await tester.pumpAndSettle();
      expect(find.text('All ingredients · 3'), findsOneWidget);

      await tester.enterText(find.byType(TextField).first, 'mang');
      await tester.pumpAndSettle();
      // A search is a search: the band and the header collapse into results.
      expect(find.text('Needs fleshing out'), findsNothing);
      expect(find.text('All ingredients · 3'), findsNothing);

      await tester.enterText(find.byType(TextField).first, '');
      await tester.pumpAndSettle();
      // An empty field is the whole vocabulary — the branch follows the text
      // the user can actually see, never a query that outlived it.
      expect(find.text('Needs fleshing out'), findsOneWidget);
      expect(find.text('All ingredients · 3'), findsOneWidget);
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

    testWidgets('G4: a prefilled-but-unconfirmed stub hints NEEDS CONFIRM — '
        'the hint stops asking for what the row already has', (tester) async {
      _filterSemanticsAssertions();
      // Same row, one difference: the prefill has landed its panel.
      final prefilled = _curryLeaves.copyWith(macros: _usdaAnswer.macros);
      await tester.pumpWidget(
        _host(FakeIngredientRepo([_mango, prefilled, _blackRice])),
      );
      await tester.pumpAndSettle();

      // D5's language: the numbers are there, a human standing behind them
      // is what is missing.
      expect(find.text('needs confirm · usda prefilled'), findsOneWidget);
      // …while a truly bare stub still says the literal truth.
      expect(find.text('needs macros'), findsOneWidget);
      expect(find.text('2 stubs'), findsOneWidget);
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
      // G6's trim: the status line one row up already explains what a stub
      // costs, so the CTA's own note says only what it is waiting for.
      expect(find.text('needs macros'), findsOneWidget);
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
      expect(_dashedChipLabels(tester), {'tsp', 'tbsp', 'cup', 'ml', 'pt'});
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
      expect(find.textContaining('lock again'), findsOneWidget);
      await tester.tap(find.widgetWithText(FButton, 'Remove'));
      await tester.pumpAndSettle();

      final after = (await repo.byId('mango'))!;
      expect(after.densityGPerMl, isNull);
      // The cross-family units are gone from the stored list; the basis
      // family, the default unit's own family, and the category's imprecise
      // word (J3 — produce earns `handful`, which owes the density nothing)
      // all survive.
      expect(after.allowedUnits!.map((u) => u.id).toSet(), {
        'piece',
        'g',
        'handful',
      });
      expect(_dashedChipLabels(tester), {'tsp', 'tbsp', 'cup', 'ml', 'pt'});
    });

    testWidgets('G6: a density-less row draws the locked chips, and the note '
        'above them is ONE line naming exactly those units', (tester) async {
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
      // It used to be three sentences, one of which claimed a family was
      // locked from the basis rather than from what is actually dashed.
      expect(
        find.text('no density — tsp · tbsp · cup · ml · pt locked'),
        findsOneWidget,
      );
      expect(find.textContaining('That blocks nothing'), findsNothing);
    });

    testWidgets('G6: a row with a density says nothing at all there — a note '
        'with no news is noise', (tester) async {
      _filterSemanticsAssertions();
      _tallScreen(tester);
      await tester.pumpWidget(
        _host(FakeIngredientRepo(const [_mango]), at: '/ingredients/mango'),
      );
      await tester.pumpAndSettle();
      expect(find.textContaining('no density —'), findsNothing);
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

    // --- plan 0022 / ADR-0010: the one question in the `piece` model --------
    //
    // `piece` is the fallback for "we have nothing better to call it". The
    // moment a row's FIRST measure names the thing, that stops being true —
    // and the household decides, once, with a default, never a rule.

    /// Saves a measure through the shared editor and settles the dialog it
    /// may raise.
    Future<void> addMeasure(
      WidgetTester tester,
      String label,
      String amount,
    ) async {
      final fields = find.descendant(
        of: find.byType(MeasuresEditor),
        matching: find.byType(TextField),
      );
      await tester.enterText(fields.first, label);
      await tester.enterText(fields.last, amount);
      await tester.pump();
      await tester.tap(
        find.descendant(
          of: find.byType(MeasuresEditor),
          matching: find.widgetWithText(FButton, 'Save'),
        ),
      );
      await tester.pumpAndSettle();
    }

    testWidgets('the FIRST measure asks whether `piece` stays offered, and '
        'the default answer takes it out of allowed_units', (tester) async {
      _filterSemanticsAssertions();
      _tallScreen(tester);
      final repo = FakeIngredientRepo(const [_mango]);
      final measures = _FakeMeasures();
      await tester.pumpWidget(
        _host(repo, at: '/ingredients/mango', measures: measures),
      );
      await tester.pumpAndSettle();
      expect(allowedUnitsFor(repo.rows.single), contains(pieces));

      await addMeasure(tester, 'mango, medium', '207');

      // The board's frame (c): named, weighed, and about this row.
      expect(
        find.textContaining('Still offer “piece” for Mango?'),
        findsOneWidget,
      );
      expect(
        find.textContaining('nobody can tell which was meant'),
        findsOneWidget,
      );

      await tester.tap(find.text('No — “mango, medium” says it'));
      await tester.pumpAndSettle();

      expect(allowedUnitsFor(repo.rows.single), isNot(contains(pieces)));
      // Nothing else went with it — one word, not a re-curation.
      expect(allowedUnitsFor(repo.rows.single), contains(g));
      expect(measures.rows.single.label, 'mango, medium');
    });

    testWidgets('“Keep both” leaves the admission exactly as it was — and so '
        'does dismissing the question', (tester) async {
      _filterSemanticsAssertions();
      _tallScreen(tester);
      final repo = FakeIngredientRepo(const [_mango]);
      await tester.pumpWidget(
        _host(repo, at: '/ingredients/mango', measures: _FakeMeasures()),
      );
      await tester.pumpAndSettle();

      await addMeasure(tester, 'mango, medium', '207');
      await tester.tap(find.text('Keep both'));
      await tester.pumpAndSettle();

      expect(allowedUnitsFor(repo.rows.single), contains(pieces));
    });

    testWidgets('a SECOND measure asks nothing — the row already answered, '
        'whichever way', (tester) async {
      _filterSemanticsAssertions();
      _tallScreen(tester);
      final repo = FakeIngredientRepo(const [_mango]);
      await tester.pumpWidget(
        _host(
          repo,
          at: '/ingredients/mango',
          measures: _FakeMeasures(const [
            Measure(id: 'm-usda', label: 'mango, medium', amount: 207),
          ]),
        ),
      );
      await tester.pumpAndSettle();

      await addMeasure(tester, 'mango, large', '280');

      expect(find.textContaining('Still offer “piece”'), findsNothing);
      expect(allowedUnitsFor(repo.rows.single), contains(pieces));
    });

    testWidgets('deleting the last measure does NOT put `piece` back — the '
        'admission chips offer it, unlocked and one tap away', (tester) async {
      _filterSemanticsAssertions();
      _tallScreen(tester);
      final repo = FakeIngredientRepo(const [_mango]);
      final measures = _FakeMeasures();
      await tester.pumpWidget(
        _host(repo, at: '/ingredients/mango', measures: measures),
      );
      await tester.pumpAndSettle();

      await addMeasure(tester, 'mango, medium', '207');
      await tester.tap(find.text('No — “mango, medium” says it'));
      await tester.pumpAndSettle();

      await tester.tap(find.byIcon(FLucideIcons.trash2).first);
      await tester.pumpAndSettle();

      expect(measures.rows, isEmpty);
      // No automatic re-add: the household said no, and a deletion is not
      // them changing their mind.
      expect(allowedUnitsFor(repo.rows.single), isNot(contains(pieces)));
      // But the chip is still drawn, and drawn LIVE (not dashed): a count
      // row needs no density for `piece`, so it is one tap from returning.
      expect(_dashedChipLabels(tester), isNot(contains('piece')));
      expect(find.text('piece'), findsWidgets);
    });

    // --- seam D1: "Counts as", the second half of the same answer ----------

    testWidgets('answering No also sets Counts as — the two questions were '
        'always one, and the prompt says so', (tester) async {
      _filterSemanticsAssertions();
      _tallScreen(tester);
      final repo = FakeIngredientRepo(const [_mango]);
      final measures = _FakeMeasures();
      await tester.pumpWidget(
        _host(repo, at: '/ingredients/mango', measures: measures),
      );
      await tester.pumpAndSettle();
      expect(repo.rows.single.defaultMeasureId, isNull);

      await addMeasure(tester, 'mango, medium', '207');
      expect(
        find.textContaining('Answering No also sets Counts as: mango, medium'),
        findsOneWidget,
      );

      await tester.tap(find.text('No — “mango, medium” says it'));
      await tester.pumpAndSettle();

      expect(repo.rows.single.defaultMeasureId, measures.rows.single.id);
      expect(allowedUnitsFor(repo.rows.single), isNot(contains(pieces)));
    });

    testWidgets('“Keep both” leaves Counts as unset — the honest reading of '
        '"both words are sayable here"', (tester) async {
      _filterSemanticsAssertions();
      _tallScreen(tester);
      final repo = FakeIngredientRepo(const [_mango]);
      await tester.pumpWidget(
        _host(repo, at: '/ingredients/mango', measures: _FakeMeasures()),
      );
      await tester.pumpAndSettle();

      await addMeasure(tester, 'mango, medium', '207');
      await tester.tap(find.text('Keep both'));
      await tester.pumpAndSettle();

      expect(repo.rows.single.defaultMeasureId, isNull);
    });

    testWidgets('the Counts as picker sets it, and "Ask me each time" clears '
        'it without touching a single measure', (tester) async {
      _filterSemanticsAssertions();
      _tallScreen(tester);
      final repo = FakeIngredientRepo(const [_mango]);
      final measures = _FakeMeasures(const [
        Measure(id: 'm-med', label: 'mango, medium', amount: 207),
        Measure(id: 'm-lrg', label: 'mango, large', amount: 280),
      ]);
      await tester.pumpWidget(
        _host(repo, at: '/ingredients/mango', measures: measures),
      );
      await tester.pumpAndSettle();

      expect(find.text('COUNTS AS — WHAT “2 ONIONS” MEANS'), findsOneWidget);
      expect(find.text('One mango is'), findsOneWidget);
      expect(find.text('— not set'), findsOneWidget);

      await tester.tap(find.text('— not set'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('mango, medium · 207 g').last);
      await tester.pumpAndSettle();
      expect(repo.rows.single.defaultMeasureId, 'm-med');

      // …and back to "Ask me each time", which is a real answer.
      await tester.tap(find.text('mango, medium · 207 g').first);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Ask me each time').last);
      await tester.pumpAndSettle();
      expect(repo.rows.single.defaultMeasureId, isNull);
      // Clearing a default never destroys a measure: the row keeps every
      // label it had and only stops having a preferred one.
      expect(measures.rows.map((m) => m.label), [
        'mango, medium',
        'mango, large',
      ]);
    });

    testWidgets('a row with NO measures is not asked — there is nothing to '
        'choose and nothing to ask', (tester) async {
      _filterSemanticsAssertions();
      _tallScreen(tester);
      await tester.pumpWidget(
        _host(
          FakeIngredientRepo(const [_mango]),
          at: '/ingredients/mango',
          measures: _FakeMeasures(),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('COUNTS AS — WHAT “2 ONIONS” MEANS'), findsNothing);
      expect(find.text('One mango is'), findsNothing);
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

    testWidgets('F1 + D7b, THE OWNER’S FLOW: rename then look up — the save '
        'is flushed, USDA is asked about the NEW name, and the answer is '
        'applied', (tester) async {
      _filterSemanticsAssertions();
      _tallScreen(tester);
      final plain = _curryLeaves.copyWith(source: 'manual');
      final repo = FakeIngredientRepo([plain]);
      final probe = _RecordingProbe(_usdaAnswer);
      await tester.pumpWidget(
        _host(repo, at: '/ingredients/curry', probe: probe),
      );
      await tester.pumpAndSettle();

      // Rename in the form and DON'T save — the exact state the owner hit.
      await tester.enterText(find.byType(TextField).first, 'Chicken Breast');
      await tester.pump();

      await tester.tap(find.text('Look up in USDA'));
      await tester.pumpAndSettle();

      // The rename was flushed first, so the question was about the new name.
      expect(probe.asked.single, normalizeMatchText('Chicken Breast'));
      final row = (await repo.byId('curry'))!;
      expect(row.canonicalName, 'Chicken Breast');
      expect(repo.matchTextById['curry'], normalizeMatchText('Chicken Breast'));
      // …and the answer landed, without completing the row (D5).
      expect(row.densityGPerMl, 0.35);
      expect(row.macros, const Macros(kcal: 108, protein: 6, carb: 19, fat: 1));
      expect(row.source, 'usda_fdc:11216');
      expect(row.status, IngredientStatus.stub);
      expect(
        find.textContaining('USDA FoodData Central filled this in'),
        findsOneWidget,
      );
    });

    testWidgets('G1: a successful lookup lands its numbers in the OPEN form’s '
        'macro fields — the row filling up is not the same as the form '
        'showing it', (tester) async {
      _filterSemanticsAssertions();
      _tallScreen(tester);
      final repo = FakeIngredientRepo([
        _curryLeaves.copyWith(source: 'manual'),
      ]);
      final probe = _RecordingProbe(_usdaAnswer);
      await tester.pumpWidget(
        _host(repo, at: '/ingredients/curry', probe: probe),
      );
      await tester.pumpAndSettle();

      // A bare stub: four empty fields, and a pending edit in a field the
      // form's own save does not touch.
      expect(_macroFieldText(tester, 'kcal'), isEmpty);
      await tester.enterText(_measureLabelField, 'small bunch');
      await tester.pump();

      await tester.tap(find.text('Look up in USDA'));
      await tester.pumpAndSettle();

      // The row got the numbers…
      expect(
        (await repo.byId('curry'))!.macros,
        const Macros(kcal: 108, protein: 6, carb: 19, fat: 1),
      );
      // …and so did the fields, without leaving the screen. This is G1: the
      // controllers are seeded once at build, so before the row-version key
      // they went on showing the blanks they were born with.
      expect(_macroFieldText(tester, 'kcal'), '108');
      expect(_macroFieldText(tester, 'protein'), '6');
      expect(_macroFieldText(tester, 'carb'), '19');
      expect(_macroFieldText(tester, 'fat'), '1');
      // The density landed too, and the entry reads it off the row.
      expect(find.textContaining('0.35'), findsWidgets);
      // The uncommitted edit elsewhere is exactly where it was left: the
      // re-seed replaces the macro subtree at its own fixed slot, and shifts
      // nothing.
      expect(
        tester.widget<TextField>(_measureLabelField).controller!.text,
        'small bunch',
      );
    });

    testWidgets('G1: numbers the user is part-way through typing are never '
        'clobbered — a pending edit outranks the row', (tester) async {
      _filterSemanticsAssertions();
      _tallScreen(tester);
      final repo = FakeIngredientRepo([
        _curryLeaves.copyWith(source: 'manual'),
      ]);
      final probe = _RecordingProbe(_usdaAnswer);
      await tester.pumpWidget(
        _host(repo, at: '/ingredients/curry', probe: probe),
      );
      await tester.pumpAndSettle();

      // Half a panel: the save refuses it, so the lookup never runs…
      await tester.enterText(_macroField('kcal'), '999');
      await tester.pump();
      await tester.tap(find.text('Look up in USDA'));
      await tester.pumpAndSettle();

      expect(probe.asked, isEmpty);
      expect(find.textContaining('Save this form first'), findsOneWidget);
      // …and the number in flight is still in flight.
      expect(_macroFieldText(tester, 'kcal'), '999');
    });

    testWidgets('G3: a lookup status is retired the moment the row moves on — '
        'no superseded sentence under a banner that has changed', (
      tester,
    ) async {
      _filterSemanticsAssertions();
      _tallScreen(tester);
      final repo = FakeIngredientRepo([
        _curryLeaves.copyWith(source: 'manual'),
      ]);
      // A candidate with a name but nothing to copy — the note the owner saw
      // linger.
      final probe = _RecordingProbe(
        const UsdaCandidate(fdcId: 11216, source: 'usda_fdc:11216', score: 0.7),
      );
      await tester.pumpWidget(
        _host(repo, at: '/ingredients/curry', probe: probe),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('Look up in USDA'));
      await tester.pumpAndSettle();
      expect(find.textContaining('no numbers for it'), findsOneWidget);

      // Now the row changes underneath the note — a density lands, and it
      // stays a stub, so the section itself is still on screen.
      await tester.enterText(_densityField, '0.35');
      await tester.pump();
      await tester.tap(find.widgetWithText(FButton, 'Save').first);
      await tester.pumpAndSettle();

      expect(find.text('Look up in USDA'), findsOneWidget);
      expect(find.textContaining('no numbers for it'), findsNothing);
    });

    testWidgets('G2: the density row fits a phone — in its "none yet" state, '
        'and in the spoon phrasing', (tester) async {
      _filterSemanticsAssertions();
      _phoneWidth(tester);
      // The section on its own, at the width the form gives it. Scoped
      // deliberately: the test font draws every glyph as a square of the font
      // size, so a whole-form assertion would fail on rows that fit fine on a
      // real device — and pass nothing useful about this one.
      await tester.pumpWidget(_densityHost(_curryLeaves));
      await tester.pumpAndSettle();

      // The longest caption plus both phrasing chips: 55px of debug stripe on
      // the owner's 402pt device before G2.
      expect(find.text('none yet — unlocks volume⇄weight'), findsOneWidget);
      expect(tester.takeException(), isNull);

      await tester.tap(find.text('a spoon weighs…'));
      await tester.pumpAndSettle();
      expect(find.text('weighs'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('D4c: a cup default on a per-100 g row with no density is '
        'FLAGGED with its repair, never rewritten', (tester) async {
      _filterSemanticsAssertions();
      _tallScreen(tester);
      final repo = FakeIngredientRepo(const [_blackRice]);
      await tester.pumpWidget(_host(repo, at: '/ingredients/rice'));
      await tester.pumpAndSettle();

      expect(
        find.textContaining('cup needs a density on this row'),
        findsOneWidget,
      );
      // Reading the form changed nothing: how a household buys a thing is
      // not ours to edit behind its back.
      expect((await repo.byId('rice'))!.defaultUnit, cup);

      await tester.tap(find.widgetWithText(FButton, 'switch default to g'));
      await tester.pumpAndSettle();

      expect((await repo.byId('rice'))!.defaultUnit, g);
      expect(find.textContaining('needs a density on this row'), findsNothing);
    });

    testWidgets('D4c: the default-unit selector locks the other family while '
        'no density bridges it', (tester) async {
      _filterSemanticsAssertions();
      _tallScreen(tester);
      await tester.pumpWidget(
        _host(FakeIngredientRepo(const [_blackRice]), at: '/ingredients/rice'),
      );
      await tester.pumpAndSettle();

      // The basis family, count and imprecise stay pickable…
      expect(_defaultUnitChip(tester, 'g').enabled, isTrue);
      expect(_defaultUnitChip(tester, 'kg').enabled, isTrue);
      expect(_defaultUnitChip(tester, 'piece').enabled, isTrue);
      expect(_defaultUnitChip(tester, 'pinch').enabled, isTrue);
      // …the volume family does not, since nothing bridges it.
      expect(_defaultUnitChip(tester, 'ml').enabled, isFalse);
      expect(_defaultUnitChip(tester, 'tbsp').enabled, isFalse);
      // The stored default still renders as the selection — it is the truth
      // about the row, and the note is how it gets fixed.
      expect(_defaultUnitChip(tester, 'cup').selected, isTrue);

      // A density unlocks the whole selector again.
      await tester.enterText(_densityField, '0.75');
      await tester.pump();
      await tester.tap(find.widgetWithText(FButton, 'Save').first);
      await tester.pumpAndSettle();

      expect(_defaultUnitChip(tester, 'ml').enabled, isTrue);
      expect(find.textContaining('needs a density on this row'), findsNothing);
    });

    testWidgets('F1: offline says what it is waiting on and never raises an '
        'error — the trigger is still the backstop', (tester) async {
      _filterSemanticsAssertions();
      _tallScreen(tester);
      final plain = _curryLeaves.copyWith(source: 'manual');
      final repo = FakeIngredientRepo([plain]);
      await tester.pumpWidget(
        // The unconfigured probe answers exactly like an offline device.
        _host(repo, at: '/ingredients/curry', probe: const _SilentProbe()),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('Look up in USDA'));
      await tester.pumpAndSettle();

      expect(
        find.textContaining(
          'the server runs the same lookup when this row '
          'syncs up',
        ),
        findsOneWidget,
      );
      // No dialog, and the row is untouched.
      expect(find.byType(FDialog), findsNothing);
      expect((await repo.byId('curry'))!.macros, isNull);
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
              data: ansiThemeData(),
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
      final barcode = tester.widget<AnsiModeChip>(
        find.ancestor(
          of: find.text('Barcode'),
          matching: find.byType(AnsiModeChip),
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
              data: ansiThemeData(),
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

    testWidgets('F1: on an UNSAVED draft the lookup is drawn and disabled, '
        'with the reason — it used to be a silent no-op', (tester) async {
      _filterSemanticsAssertions();
      final probe = _RecordingProbe(_usdaAnswer);
      await tester.pumpWidget(
        _sheetHost(FakeIngredientRepo(const []), probe: probe),
      );
      await tester.pumpAndSettle();
      // Not offered at all until the USDA source is picked…
      expect(find.text('Look up in USDA'), findsNothing);

      await tester.tap(find.text('USDA FDC'));
      await tester.pumpAndSettle();
      expect(find.text('Look up in USDA'), findsOneWidget);
      expect(find.textContaining('save first'), findsOneWidget);

      // Tapping it does nothing — there is no row to fill in, and the
      // affordance says so rather than shrugging.
      await tester.tap(find.text('Look up in USDA'));
      await tester.pumpAndSettle();
      expect(probe.asked, isEmpty);
    });

    testWidgets('D7b: creating a manual ingredient probes at birth — it '
        'arrives enriched, and still a stub', (tester) async {
      _filterSemanticsAssertions();
      final repo = FakeIngredientRepo(const []);
      final probe = _RecordingProbe(_usdaAnswer);
      // The router-hosted sheet: creating pushes the flesh-out form.
      await tester.pumpWidget(
        _addHost(repo, body: _fixture('nutella_per_100g'), probe: probe),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Add an ingredient'));
      await tester.pumpAndSettle();

      await tester.enterText(_nameField, 'Curry leaves');
      await tester.pump();
      await tester.tap(find.text('Create & flesh out'));
      await tester.pumpAndSettle();

      expect(probe.asked.single, normalizeMatchText('Curry leaves'));
      final created = repo.rows.single;
      expect(created.densityGPerMl, 0.35);
      expect(created.macros!.kcal, 108);
      expect(created.source, 'usda_fdc:11216');
      expect(created.status, IngredientStatus.stub);
    });

    testWidgets('D7b offline: creation still works, the row is just bare — '
        'no error, and the server trigger is the backstop', (tester) async {
      _filterSemanticsAssertions();
      final repo = FakeIngredientRepo(const []);
      await tester.pumpWidget(
        _addHost(repo, body: _fixture('nutella_per_100g')),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Add an ingredient'));
      await tester.pumpAndSettle();

      await tester.enterText(_nameField, 'Curry leaves');
      await tester.pump();
      await tester.tap(find.text('Create & flesh out'));
      await tester.pumpAndSettle();

      final created = repo.rows.single;
      expect(created.macros, isNull);
      expect(created.source, 'manual');
      expect(find.byType(FDialog), findsNothing);
    });
  });

  group('the form scans a barcode into itself (plan 0025 #8)', () {
    /// A bare stub created by name — no numbers, `manual` provenance: the
    /// row the picker's add-new chain lands on the form.
    const bare = Ingredient(
      id: 'bare',
      canonicalName: 'Hazelnut spread',
      defaultUnit: g,
      status: IngredientStatus.stub,
      source: 'manual',
    );

    OffLookup lookupAnswering(String fixture) => OffLookup(
      client: MockClient((_) async => http.Response(_fixture(fixture), 200)),
    );

    /// Opens the form's scan surface and types [barcode] in.
    Future<void> scanOnForm(WidgetTester tester, String barcode) async {
      await tester.tap(find.text('Scan a barcode to fill this in'));
      await tester.pumpAndSettle();
      await tester.enterText(_scanField, barcode);
      await tester.pump();
      await tester.tap(find.text('Look up'));
      await tester.pumpAndSettle();
    }

    testWidgets('fills the EMPTY macro fields, keeps the name and a USDA '
        'provenance — and writes nothing until Save', (tester) async {
      _filterSemanticsAssertions();
      _tallScreen(tester);
      final repo = FakeIngredientRepo(const [_curryLeaves]);
      await tester.pumpWidget(
        _host(
          repo,
          at: '/ingredients/curry',
          lookup: lookupAnswering('nutella_per_100g'),
        ),
      );
      await tester.pumpAndSettle();

      await scanOnForm(tester, '3017620422003');

      // The card, with what it left alone named on it.
      expect(find.text('FOUND · OPEN FOOD FACTS'), findsOneWidget);
      expect(
        find.textContaining('kept: the name — yours stays'),
        findsOneWidget,
      );
      expect(
        find.textContaining('the provenance — this row already names a source'),
        findsOneWidget,
      );
      // The panel reached the FIELDS (the G1 lesson), the name did not move.
      expect(_macroFieldText(tester, 'kcal'), '539');
      expect(_macroFieldText(tester, 'fat'), '30.9');
      expect(
        tester.widget<TextField>(find.byType(TextField).first).controller!.text,
        'Curry leaves, fresh',
      );
      // Nothing has been written.
      expect((await repo.byId('curry'))!.macros, isNull);
      expect(find.textContaining('filled in, not saved'), findsOneWidget);

      await tester.tap(find.widgetWithText(FButton, 'Save').last);
      await tester.pumpAndSettle();
      final saved = (await repo.byId('curry'))!;
      expect(saved.macros!.kcal, 539);
      expect(saved.macrosBasis, MacrosBasis.perG);
      expect(saved.source, 'usda_fdc:11216', reason: 'a source stays');
      // A scan prefills and never completes (D1/D5).
      expect(saved.status, IngredientStatus.stub);
    });

    testWidgets('on a row with no source, Save stamps off:<barcode> in the '
        'same write as the macros', (tester) async {
      _filterSemanticsAssertions();
      _tallScreen(tester);
      final repo = FakeIngredientRepo(const [bare]);
      await tester.pumpWidget(
        _host(
          repo,
          at: '/ingredients/bare',
          lookup: lookupAnswering('nutella_per_100g'),
        ),
      );
      await tester.pumpAndSettle();

      await scanOnForm(tester, '3017620422003');
      expect(find.textContaining('the provenance'), findsNothing);
      expect((await repo.byId('bare'))!.source, 'manual');

      await tester.tap(find.widgetWithText(FButton, 'Save').last);
      await tester.pumpAndSettle();
      final saved = (await repo.byId('bare'))!;
      expect(saved.source, 'off:3017620422003');
      expect(saved.macros!.kcal, 539);
      expect(saved.status, IngredientStatus.stub);
    });

    testWidgets('a panel already typed is not overwritten, and the card says '
        'so', (tester) async {
      _filterSemanticsAssertions();
      _tallScreen(tester);
      final repo = FakeIngredientRepo(const [bare]);
      await tester.pumpWidget(
        _host(
          repo,
          at: '/ingredients/bare',
          lookup: lookupAnswering('nutella_per_100g'),
        ),
      );
      await tester.pumpAndSettle();
      await tester.enterText(_macroField('kcal'), '100');
      await tester.pump();

      await scanOnForm(tester, '3017620422003');

      expect(_macroFieldText(tester, 'kcal'), '100');
      expect(
        find.textContaining('the macros — the ones already entered stay'),
        findsOneWidget,
      );
    });

    testWidgets('the pack size is an offer: tapped, it becomes a measure in '
        'the row’s basis', (tester) async {
      _filterSemanticsAssertions();
      _tallScreen(tester);
      final repo = FakeIngredientRepo(const [bare]);
      final measures = _FakeMeasures();
      await tester.pumpWidget(
        _host(
          repo,
          at: '/ingredients/bare',
          measures: measures,
          lookup: lookupAnswering('nesquik_no_panel'),
        ),
      );
      await tester.pumpAndSettle();

      await scanOnForm(tester, '3033710065967');
      // No panel: the fields stay blank with the reason, never zeros.
      expect(_macroFieldText(tester, 'kcal'), isEmpty);
      expect(
        find.text('Open Food Facts has no nutrition panel for this product.'),
        findsOneWidget,
      );
      // "1 kg" on a per-100 g row is offered as 1000 g — and only offered.
      final offer = find.text('＋ add “pack” = 1000 g as a measure');
      expect(offer, findsOneWidget);
      expect(measures.rows, isEmpty);

      await tester.tap(offer);
      await tester.pumpAndSettle();
      expect(measures.rows.single.label, 'pack');
      expect(measures.rows.single.amount, 1000);
      expect(offer, findsNothing);
      expect(find.textContaining('pack added below'), findsOneWidget);
    });

    testWidgets('a confirmed row offers no scan — nothing on it is empty', (
      tester,
    ) async {
      _filterSemanticsAssertions();
      _tallScreen(tester);
      await tester.pumpWidget(
        _host(FakeIngredientRepo(const [_mango]), at: '/ingredients/mango'),
      );
      await tester.pumpAndSettle();
      expect(find.text('Scan a barcode to fill this in'), findsNothing);
    });
  });

  group('the macros section’s per-serving mode (plan 0027 front M)', () {
    /// A bare stub by name, per-100 g, no density — the row a US label
    /// lands on. Its volume chips are dashed until a density arrives.
    const spread = Ingredient(
      id: 'spread',
      canonicalName: 'Buttery spread',
      defaultUnit: g,
      status: IngredientStatus.stub,
      source: 'manual',
    );

    testWidgets('M-D1 + M-D3: the label typed as printed, the row stored per '
        '100 — unrounded, previewed live, and refused without the serving '
        'weight', (tester) async {
      _filterSemanticsAssertions();
      _tallScreen(tester);
      final repo = FakeIngredientRepo(const [spread]);
      await tester.pumpWidget(_host(repo, at: '/ingredients/spread'));
      await tester.pumpAndSettle();

      // Nobody who never taps the segment sees anything new.
      expect(find.text('One serving is'), findsNothing);
      await tester.tap(find.text('per serving'));
      await tester.pumpAndSettle();
      expect(find.text('One serving is'), findsOneWidget);
      expect(
        find.text('type the serving weight from the pack'),
        findsOneWidget,
      );

      await _typeMacros(
        tester,
        kcal: '100',
        protein: '0',
        carb: '0',
        fat: '11',
      );
      // The four are in, the serving is not: the preview says what it needs
      // and Save refuses rather than dividing by a blank.
      expect(
        find.textContaining('stored per 100 g: needs the serving weight'),
        findsOneWidget,
      );
      await _saveForm(tester);
      expect(find.textContaining('One serving is how much?'), findsOneWidget);
      expect((await repo.byId('spread'))!.macros, isNull);

      await tester.enterText(_servingAmountField, '14');
      await tester.pumpAndSettle();
      // The derivation, before Save, in the person's sight (invariant 3).
      expect(
        find.textContaining('stored per 100 g: 714 kcal · 0P 79F 0C'),
        findsOneWidget,
      );
      expect(
        find.textContaining(
          'from a 14 g serving — the label’s rounding scales with it',
        ),
        findsOneWidget,
      );

      await _saveForm(tester);
      final saved = (await repo.byId('spread'))!;
      // Per 100, unrounded (M-D3); the printed four are nowhere on the row.
      expect(saved.macros!.kcal, closeTo(714.2857, 0.0001));
      expect(saved.macros!.fat, closeTo(78.5714, 0.0001));
      expect(saved.macros!.protein, 0);
      expect(saved.macrosBasis, MacrosBasis.perG);
      // A label fills fields; confirming stays a human act (plan 0020 D5).
      expect(saved.status, IngredientStatus.stub);
      expect(saved.densityGPerMl, isNull);
    });

    testWidgets('the serving unit is the basis: an ml serving stores per 100 '
        'ml', (tester) async {
      _filterSemanticsAssertions();
      _tallScreen(tester);
      final repo = FakeIngredientRepo(const [spread]);
      await tester.pumpWidget(_host(repo, at: '/ingredients/spread'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('per serving'));
      await tester.pumpAndSettle();
      // The `ml` chip inside the serving row — the admission chips carry one
      // too, so scope it.
      await tester.tap(
        find.descendant(
          of: find.byType(ServingRow),
          matching: find.widgetWithText(AnsiModeChip, 'ml'),
        ),
      );
      await tester.pumpAndSettle();
      await tester.enterText(_servingAmountField, '240');
      await _typeMacros(
        tester,
        kcal: '120',
        protein: '8',
        carb: '12',
        fat: '5',
      );
      await tester.pumpAndSettle();
      expect(find.textContaining('stored per 100 ml: 50 kcal'), findsOneWidget);

      await _saveForm(tester);
      final saved = (await repo.byId('spread'))!;
      expect(saved.macrosBasis, MacrosBasis.perMl);
      expect(saved.macros!.kcal, 50);
    });

    testWidgets('M-D2: “1 tbsp = 14 g” is offered as the density — OFF by '
        'default, and when ticked it lands in the same Save and the volume '
        'chips unlock', (tester) async {
      _filterSemanticsAssertions();
      _tallScreen(tester);
      final repo = FakeIngredientRepo(const [spread]);
      await tester.pumpWidget(_host(repo, at: '/ingredients/spread'));
      await tester.pumpAndSettle();
      expect(_dashedChipLabels(tester), containsAll(['tbsp', 'ml']));

      await tester.tap(find.text('per serving'));
      await tester.pumpAndSettle();
      await tester.enterText(_servingAmountField, '14');
      await tester.enterText(_servingNameField, '1 tbsp');
      await _typeMacros(
        tester,
        kcal: '100',
        protein: '0',
        carb: '0',
        fat: '11',
      );
      await tester.pumpAndSettle();

      // The offer, drawn and unticked.
      expect(find.text('THIS SERVING ALSO SAYS'), findsOneWidget);
      final tick = find.byKey(const ValueKey('serving-offer'));
      expect(find.text('1 tbsp weighs 14 g — set as density'), findsOneWidget);
      expect(tester.widget<FCheckbox>(tick).value, isFalse);

      // Untouched, Save writes the macros and NOTHING else.
      await _saveForm(tester);
      final first = (await repo.byId('spread'))!;
      expect(first.macros, isNotNull);
      expect(first.densityGPerMl, isNull);
      expect(_dashedChipLabels(tester), containsAll(['tbsp', 'ml']));

      // Ticked, the same Save lands it through `setDensity` — the density
      // entry's own spoon arithmetic (ADR-0008 §2), and ADR-0009's unlock.
      await tester.tap(tick);
      await tester.pumpAndSettle();
      expect(tester.widget<FCheckbox>(tick).value, isTrue);
      expect(find.textContaining('= 0.947 g/ml'), findsOneWidget);
      await _saveForm(tester);
      final second = (await repo.byId('spread'))!;
      expect(second.densityGPerMl, closeTo(14 / tbsp.ratioToBase!, 1e-9));
      expect(_dashedChipLabels(tester), isNot(contains('tbsp')));
      expect(_dashedChipLabels(tester), isNot(contains('ml')));
      expect(find.textContaining('0.947 g/ml'), findsWidgets);
      // Landed, so unticked — a third Save must not write it again.
      expect(tester.widget<FCheckbox>(tick).value, isFalse);
    });

    testWidgets('M-D2: a serving that names a thing — “1 slice = 28 g” — is '
        'offered as a measure, through the measures editor’s write', (
      tester,
    ) async {
      _filterSemanticsAssertions();
      _tallScreen(tester);
      final repo = FakeIngredientRepo(const [spread]);
      final measures = _FakeMeasures();
      await tester.pumpWidget(
        _host(repo, at: '/ingredients/spread', measures: measures),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('per serving'));
      await tester.pumpAndSettle();
      await tester.enterText(_servingAmountField, '28');
      await tester.enterText(_servingNameField, '1 slice');
      await _typeMacros(tester, kcal: '80', protein: '3', carb: '14', fat: '1');
      await tester.pumpAndSettle();

      expect(find.text('1 slice = 28 g — add as a measure'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('serving-offer')));
      await tester.pumpAndSettle();
      expect(measures.rows, isEmpty, reason: 'a tick writes nothing yet');

      await _saveForm(tester);
      expect(measures.rows.single.label, 'slice');
      expect(measures.rows.single.amount, 28);
      expect((await repo.byId('spread'))!.macros!.kcal, closeTo(285.71, 0.01));
      // No density from a slice — that offer is a spoon's alone.
      expect((await repo.byId('spread'))!.densityGPerMl, isNull);
    });

    test('servingOfferFor: a spoon with a mass is a density per spoon, a '
        'spoon with a volume is nothing, a thing is a measure of one', () {
      const g14 = ServingDraft(amountText: '14', name: '1 tbsp');
      final density = servingOfferFor(g14, MacrosBasis.perG)! as DensityOffer;
      expect(density.unit, tbsp);
      expect(density.gPerMl, closeTo(14 / tbsp.ratioToBase!, 1e-9));
      // "2 Tbsp = 32 g" — per spoon, the way the pack's own line reads.
      final two =
          servingOfferFor(
                const ServingDraft(amountText: '32', name: '2 Tbsp'),
                MacrosBasis.perG,
              )!
              as DensityOffer;
      expect(two.gramsPerUnit, 16);
      expect(two.sentence, '1 tbsp weighs 16 g — set as density');
      // A spoon of ml is a volume of itself — not a density.
      expect(servingOfferFor(g14, MacrosBasis.perMl), isNull);
      // A thing is a measure; a count above one has no singular to name.
      final slice =
          servingOfferFor(
                const ServingDraft(amountText: '28', name: 'slice'),
                MacrosBasis.perG,
              )!
              as MeasureOffer;
      expect(slice.label, 'slice');
      expect(slice.amount, 28);
      expect(
        servingOfferFor(
          const ServingDraft(amountText: '56', name: '2 slices'),
          MacrosBasis.perG,
        ),
        isNull,
      );
      // Nothing to offer from nothing.
      expect(
        servingOfferFor(const ServingDraft(amountText: '14'), MacrosBasis.perG),
        isNull,
      );
      expect(
        servingOfferFor(const ServingDraft(name: '1 tbsp'), MacrosBasis.perG),
        isNull,
      );
    });
  });

  group(
    'a per-serving barcode panel lands on the selector (plan 0027 M-D5)',
    () {
      const bare = Ingredient(
        id: 'bare',
        canonicalName: 'Peanut butter',
        defaultUnit: g,
        status: IngredientStatus.stub,
        source: 'manual',
      );

      OffLookup lookupAnswering(String body) =>
          OffLookup(client: MockClient((_) async => http.Response(body, 200)));

      /// The peanut-butter fixture with OFF's numeric serving removed — the
      /// pack whose serving is prose only.
      String withoutServingQuantity() {
        final body =
            jsonDecode(_fixture('peanut_butter_per_serving'))
                as Map<String, Object?>;
        (body['product']! as Map<String, Object?>)
          ..remove('serving_quantity')
          ..remove('serving_quantity_unit');
        return jsonEncode(body);
      }

      Future<void> scanOnForm(WidgetTester tester) async {
        await tester.tap(find.text('Scan a barcode to fill this in'));
        await tester.pumpAndSettle();
        await tester.enterText(_scanField, '0851087000250');
        await tester.pump();
        await tester.tap(find.text('Look up'));
        await tester.pumpAndSettle();
      }

      testWidgets('on the form: per-serving mode opens, the four as printed, '
          'the serving prefilled from serving_quantity — and Save stores per '
          '100', (tester) async {
        _filterSemanticsAssertions();
        _tallScreen(tester);
        final repo = FakeIngredientRepo(const [bare]);
        await tester.pumpWidget(
          _host(
            repo,
            at: '/ingredients/bare',
            lookup: lookupAnswering(_fixture('peanut_butter_per_serving')),
          ),
        );
        await tester.pumpAndSettle();

        await scanOnForm(tester);

        expect(find.text('One serving is'), findsOneWidget);
        expect(_fieldText(tester, _servingAmountField), '32');
        expect(_fieldText(tester, _servingNameField), '2 Tbsp');
        expect(_macroFieldText(tester, 'kcal'), '180');
        expect(_macroFieldText(tester, 'fat'), '14');
        expect(
          find.textContaining('stored per 100 g: 563 kcal · 19P 44F 31C'),
          findsOneWidget,
        );
        // The card says what it read, and the M-D2 offer reads the pack's own
        // "2 Tbsp (32 g)" as a spoon.
        expect(
          find.textContaining('panel read per serving of 32 g'),
          findsOneWidget,
        );
        expect(
          find.text('1 tbsp weighs 16 g — set as density'),
          findsOneWidget,
        );
        // Nothing written until Save.
        expect((await repo.byId('bare'))!.macros, isNull);

        await _saveForm(tester);
        final saved = (await repo.byId('bare'))!;
        expect(saved.macros!.kcal, 562.5);
        expect(saved.macros!.protein, 18.75);
        expect(saved.macrosBasis, MacrosBasis.perG);
        expect(saved.source, 'off:0851087000250');
        expect(saved.status, IngredientStatus.stub);
        expect(saved.densityGPerMl, isNull, reason: 'the offer was not taken');
      });

      testWidgets('on the form, no numeric serving: the amount is empty and '
          'flagged with the pack’s words, never parsed out of them', (
        tester,
      ) async {
        _filterSemanticsAssertions();
        _tallScreen(tester);
        final repo = FakeIngredientRepo(const [bare]);
        await tester.pumpWidget(
          _host(
            repo,
            at: '/ingredients/bare',
            lookup: lookupAnswering(withoutServingQuantity()),
          ),
        );
        await tester.pumpAndSettle();

        await scanOnForm(tester);

        expect(_fieldText(tester, _servingAmountField), isEmpty);
        expect(
          find.text('the pack says “2 Tbsp (32 g)” — type the serving weight'),
          findsOneWidget,
        );
        expect(_macroFieldText(tester, 'kcal'), '180');
        await _saveForm(tester);
        expect(find.textContaining('One serving is how much?'), findsOneWidget);
        expect((await repo.byId('bare'))!.macros, isNull);

        await tester.enterText(_servingAmountField, '32');
        await tester.pumpAndSettle();
        await _saveForm(tester);
        expect((await repo.byId('bare'))!.macros!.kcal, 562.5);
      });

      testWidgets('on the add sheet: the serving row under the card, prefilled '
          '— and Create stores the per-100 derivation', (tester) async {
        _filterSemanticsAssertions();
        final repo = FakeIngredientRepo(const []);
        await tester.pumpWidget(
          _addHost(repo, body: _fixture('peanut_butter_per_serving')),
        );
        await tester.pumpAndSettle();

        await tester.tap(find.text('Add an ingredient'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Barcode'));
        await tester.pumpAndSettle();
        await tester.enterText(_scanField, '0851087000250');
        await tester.pump();
        await tester.tap(find.text('Look up'));
        await tester.pumpAndSettle();

        expect(find.text('180 kcal · 6P 14F 10C'), findsOneWidget);
        expect(
          find.textContaining(
            'panel read per serving of 32 g (“2 Tbsp (32 g)”)',
          ),
          findsOneWidget,
        );
        expect(_fieldText(tester, _servingAmountField), '32');
        expect(
          find.textContaining('stored per 100 g: 563 kcal · 19P 44F 31C'),
          findsOneWidget,
        );

        await tester.ensureVisible(find.text('Save & review'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Save & review'));
        await tester.pumpAndSettle();

        final created = repo.rows.single;
        expect(created.macros!.kcal, 562.5);
        expect(created.macros!.carb, 31.25);
        expect(created.macrosBasis, MacrosBasis.perG);
        expect(created.source, 'off:0851087000250');
        expect(created.status, IngredientStatus.stub);
      });

      testWidgets('on the add sheet, no numeric serving: flagged, stored as a '
          'panel-less stub unless the weight is typed', (tester) async {
        _filterSemanticsAssertions();
        final repo = FakeIngredientRepo(const []);
        await tester.pumpWidget(_addHost(repo, body: withoutServingQuantity()));
        await tester.pumpAndSettle();

        await tester.tap(find.text('Add an ingredient'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Barcode'));
        await tester.pumpAndSettle();
        await tester.enterText(_scanField, '0851087000250');
        await tester.pump();
        await tester.tap(find.text('Look up'));
        await tester.pumpAndSettle();

        expect(_fieldText(tester, _servingAmountField), isEmpty);
        expect(
          find.textContaining('the serving weight is what is missing'),
          findsOneWidget,
        );
        await tester.enterText(_servingAmountField, '32');
        await tester.pumpAndSettle();
        expect(
          find.textContaining('the serving weight is what is missing'),
          findsNothing,
        );

        await tester.ensureVisible(find.text('Save & review'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Save & review'));
        await tester.pumpAndSettle();
        expect(repo.rows.single.macros!.kcal, 562.5);
      });
    },
  );

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

    testWidgets('with no lookup passed in, the sheet takes the one the '
        'PROVIDER holds — the seam the integration harness overrides', (
      tester,
    ) async {
      _filterSemanticsAssertions();
      final repo = FakeIngredientRepo(const []);
      await tester.pumpWidget(
        _addHost(
          repo,
          body: _fixture('nutella_per_100g'),
          // The app's own wiring: `showNewIngredientSheet` is called with no
          // lookup, exactly as `ingredient_list_view` calls it.
          viaProvider: true,
        ),
      );
      await tester.pumpAndSettle();

      await scan(tester, barcode: '3017620422003');

      // The override answered, so the provider really is what the sheet reads
      // when no parameter is supplied. Without it this reaches the network.
      expect(find.text('FOUND · OPEN FOOD FACTS'), findsOneWidget);
      expect(
        find.text('Nutella · barcode 3017620422003 · Open Food Facts · ODbL'),
        findsOneWidget,
      );
    });

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

    testWidgets('D7b: a barcode row is NOT probed — an Open Food Facts '
        'provenance is never replaced by a USDA id', (tester) async {
      _filterSemanticsAssertions();
      final repo = FakeIngredientRepo(const []);
      final probe = _RecordingProbe(_usdaAnswer);
      await tester.pumpWidget(
        _addHost(repo, body: _fixture('oatly_per_100ml'), probe: probe),
      );
      await tester.pumpAndSettle();

      await scan(tester, barcode: '7394376616020');
      await tester.ensureVisible(find.text('Save & review'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Save & review'));
      await tester.pumpAndSettle();

      // The same exclusion the server trigger's WHEN clause makes: the probe
      // rewrites `source` wholesale, and `off:<barcode>` is not ours to lose.
      expect(probe.asked, isEmpty);
      expect(repo.rows.single.source, 'off:7394376616020');
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

/// The add sheet's canonical-name field (the first text field it renders).
final Finder _nameField = find
    .descendant(
      of: find.byType(NewIngredientSheet),
      matching: find.byType(TextField),
    )
    .first;

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

/// The add sheet as the list screen opens it — the sheet hands the row back
/// and the host pushes the form (plan 0025 D3) — over a router that can
/// receive that push. [body] is what Open Food Facts answers with.
///
/// [viaProvider] chooses WHICH seam delivers that client. False (the default)
/// passes it as a parameter, the way a widget test reaches in. True passes
/// nothing and overrides [offLookupProvider] instead — the app's own wiring,
/// and the seam `make test-sim` drives, since the real list screen opens this
/// sheet from inside a navigation stack no caller can thread a parameter
/// through.
Widget _addHost(
  FakeIngredientRepo repo, {
  required String body,
  _FakeMeasures? measures,
  UsdaProbe? probe,
  bool viaProvider = false,
}) {
  OffLookup buildLookup() =>
      OffLookup(client: MockClient((_) async => http.Response(body, 200)));
  final router = GoRouter(
    initialLocation: '/',
    routes: [
      GoRoute(
        path: '/',
        builder: (_, _) => FScaffold(
          child: Builder(
            builder: (context) => FButton(
              onPress: () async {
                final created = await showNewIngredientSheet(
                  context,
                  lookup: viaProvider ? null : buildLookup(),
                  cameraPane: (_, _) => const SizedBox.shrink(),
                );
                // What `ingredient_list_view` does with the row it is handed.
                if (created != null && context.mounted) {
                  await context.push('/ingredients/${created.id}');
                }
              },
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
      usdaProbeProvider.overrideWithValue(probe ?? const _SilentProbe()),
      if (viaProvider) offLookupProvider.overrideWithValue(buildLookup()),
    ],
    child: MaterialApp.router(
      routerConfig: router,
      builder: (context, child) => FTheme(data: ansiThemeData(), child: child!),
    ),
  );
}
