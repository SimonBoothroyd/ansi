/// Widget tests for the ingredients manager (step 8.5, design board
/// "Ingredients manager · v1" frames a–e; plan 0027 front U, "The USDA
/// match" frames a–d).
///
/// The screen states that carry the plan's decisions are the ones worth
/// pinning: the stub band's **needs macros** wording (D5 overruled the
/// board's "needs density · macros"), the confirm CTA's gate and its
/// reversal, the delete refusal's count, the dashed density-locked chips
/// (D4), the USDA match named on the form with its two doors (U-D1/D2/D3)
/// and searched from the add sheet (U-D7), and — frame (e) — a barcode scan
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
import 'package:ansi/features/ingredients/domain/ingredient_repository.dart';
import 'package:ansi/features/ingredients/domain/measure_repository.dart';
import 'package:ansi/features/ingredients/domain/normalize.dart';
import 'package:ansi/features/ingredients/domain/usda_probe.dart';
import 'package:ansi/features/ingredients/presentation/density_entry.dart';
import 'package:ansi/features/ingredients/presentation/ingredient_detail_view.dart';
import 'package:ansi/features/ingredients/presentation/ingredient_list_view.dart';
import 'package:ansi/features/ingredients/presentation/measures_editor.dart';
import 'package:ansi/features/ingredients/presentation/serving_row.dart';
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

/// A stub the server prefill stamped and named (0027): the match is a close
/// one, so the form's provenance line says it matches every word.
const _curryLeaves = Ingredient(
  id: 'curry',
  canonicalName: 'Curry leaves, fresh',
  defaultUnit: g,
  status: IngredientStatus.stub,
  category: 'produce',
  source: 'usda_fdc:11216',
  sourceLabel: 'Curry leaves, raw',
  sourceScore: 1,
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
  description: 'Curry leaves, raw',
  category: 'Vegetables and Vegetable Products',
  source: 'usda_fdc:11216',
  score: 0.71,
  densityGPerMl: 0.35,
  macros: Macros(kcal: 108, protein: 6, carb: 19, fat: 1),
);

/// Records what it was asked. F1's whole point is that the question is about
/// the name as SAVED, so the recording is the assertion. Answers its one
/// candidate (or nothing), capped at the limit asked for.
class _RecordingProbe extends UsdaProbe {
  _RecordingProbe(UsdaCandidate? answer) : answers = [?answer];

  /// A short-list, best first — what the Choose-another sheet and the
  /// New-ingredient leg ask for.
  _RecordingProbe.list(this.answers);

  final List<UsdaCandidate> answers;
  final asked = <String>[];
  final limits = <int>[];

  @override
  Future<List<UsdaCandidate>> search(String matchText, {int limit = 5}) async {
    asked.add(matchText);
    limits.add(limit);
    return answers.take(limit).toList();
  }
}

/// The offline / unconfigured answer: nothing, without throwing.
class _SilentProbe extends UsdaProbe {
  const _SilentProbe();

  @override
  Future<List<UsdaCandidate>> search(String matchText, {int limit = 5}) async =>
      const [];
}

/// The flesh-out form is one long scroll; a phone-sized test viewport builds
/// only its top and every assertion below the fold fails for the wrong
/// reason. Give the whole form room instead of scrolling to each section.
void _tallScreen(WidgetTester tester) {
  tester.view.physicalSize = const Size(1000, 5000);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
}

/// The units the admission section says a density would unlock — D4b's whole
/// visible contract. They used to be dashed chips; since the v2 pass they are
/// one named line ("cup · tbsp · ml unlock when this row has a density"),
/// which answers "why can't I pick cup" with the remedy attached rather than
/// with a grey pill. Parsed off that line, so the test asserts exactly what
/// the user is told.
Set<String> _lockedUnitLabels(WidgetTester tester) {
  for (final t in find.byType(Text).evaluate()) {
    final data = (t.widget as Text).data;
    if (data == null || !data.contains('unlock when this row has a density')) {
      continue;
    }
    return data.split(' unlock').first.split(' · ').toSet();
  }
  return {};
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
/// Taps the form's own Save. Since the v2 pass **Save ends the page** — the
/// picker that pushes this form awaits its pop — so a test that goes on
/// asserting form state passes [reopen], the row's canonical name, and the
/// helper walks back in through the list the way a person would.
Future<void> _saveForm(WidgetTester tester, {String? reopen}) async {
  await tester.tap(find.byKey(kFormSaveKey));
  await tester.pumpAndSettle();
  if (reopen == null) return;
  expect(
    find.text('CANONICAL NAME'),
    findsNothing,
    reason: 'Save should have left the form',
  );
  await tester.tap(find.text(reopen).first);
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
      // Declared BEFORE `:id`, so `new` is a route and not an ingredient id.
      GoRoute(
        path: '/ingredients/new',
        builder: (_, state) => IngredientDetailView(
          name: state.uri.queryParameters['name'] ?? '',
          lookup: lookup,
          cameraPane: lookup == null ? null : (_, _) => const SizedBox.shrink(),
        ),
      ),
      GoRoute(
        path: '/ingredients/:id',
        builder: (_, state) => IngredientDetailView(
          ingredientId: state.pathParameters['id'],
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

/// Opens the flesh-out form's header `⋯` — where the actions that are not
/// part of filling the form in live (delete, and un-confirming a complete
/// row), drawn on the board frame since the section was locked.
/// Opens `Fill it in from ▸ Look up in USDA` and picks [description] from
/// the short-list it shows. The button used to run one probe and apply the
/// best hit sight-unseen; it now opens the same five-candidate search that
/// `Choose another ›` opens, so every one of these flows has a human pick in
/// the middle of it.
Future<void> _lookUpUsdaAndPick(WidgetTester tester, String description) async {
  await tester.tap(find.text('Look up in USDA'));
  await tester.pumpAndSettle();
  await tester.tap(find.text(description));
  await tester.pumpAndSettle();
}

/// Puts a density in the form's DRAFT (plan 0029 W5). The entry's inline
/// button reads `Add` on this host, because on this host it writes nothing —
/// the form's own Save is what lands it. `ml`'s ratio to base is 1, so
/// picking it makes the typed number a raw g/ml.
Future<void> _draftDensity(WidgetTester tester, String gPerMl) async {
  await tester.tap(
    find.descendant(of: find.byType(DensityEntry), matching: find.text('ml')),
  );
  await tester.pump();
  await tester.enterText(_densityField, gPerMl);
  await tester.pump();
  await tester.tap(find.widgetWithText(FButton, 'Add').first);
  await tester.pumpAndSettle();
}

/// The `FakeIngredientRepo` the pumped host is using — so a test can read
/// [FakeIngredientRepo.savedForms], which is what the form ASKED for, as
/// distinct from what the row ended up being.
FakeIngredientRepo _repoOf(WidgetTester tester) =>
    ProviderScope.containerOf(
          tester.element(find.byType(IngredientDetailView)),
          listen: false,
        ).read(ingredientRepositoryProvider)
        as FakeIngredientRepo;

Future<void> _openMoreMenu(WidgetTester tester) async {
  await tester.tap(find.byIcon(FLucideIcons.ellipsis));
  await tester.pumpAndSettle();
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
            // The G2 host measures LAYOUT, so the seam is inert here: the
            // widget no longer knows a repository, and this stands in for the
            // host that would land the write.
            onSave: (_) async => true,
            onRemove: () async => true,
          ),
        ),
      ),
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

      // Save is the way back now — it ends the page, which is what the
      // picker that pushes this form has always awaited.
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

    testWidgets('G4: a prefilled-but-unconfirmed stub hints NEEDS COMPLETING — '
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
      expect(find.text('needs completing · usda prefilled'), findsOneWidget);
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
      final cta = tester.widget<FButton>(find.byKey(kFormCompleteKey));
      expect(cta.onPress, isNull);
    });

    testWidgets('U-D1: a machine prefill is NAMED at the head of the macros '
        'section — the food, its FDC id, the band word — reads not '
        'confirmed, and offers both doors', (tester) async {
      _filterSemanticsAssertions();
      _tallScreen(tester);
      await tester.pumpWidget(
        _host(
          FakeIngredientRepo(const [_curryLeaves]),
          at: '/ingredients/curry',
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Filled from USDA · not confirmed'), findsOneWidget);
      expect(
        find.text(
          'Curry leaves, raw · FDC 11216 · matches every word of “Curry '
          'leaves, fresh”',
        ),
        findsOneWidget,
      );
      expect(find.widgetWithText(FButton, 'Not this food'), findsOneWidget);
      expect(find.widgetWithText(FButton, 'Choose another ›'), findsOneWidget);
      // The old lookup button has no job on a row USDA already filled: the
      // doors are how the match changes.
      expect(find.text('Look up in USDA'), findsNothing);
      // D5 still: the status line says what a stub costs.
      expect(find.textContaining('Still a stub'), findsOneWidget);
    });

    testWidgets('U-D1 as 0029 re-reads it: a pick covering only part of '
        'the name says so; a row filled before 0027 names the id alone', (
      tester,
    ) async {
      _filterSemanticsAssertions();
      _tallScreen(tester);
      final repo = FakeIngredientRepo([
        _curryLeaves.copyWith(sourceScore: 0.62),
      ]);
      await tester.pumpWidget(_host(repo, at: '/ingredients/curry'));
      await tester.pumpAndSettle();
      expect(
        find.textContaining('matches only part of “Curry leaves, fresh”'),
        findsOneWidget,
      );

      // A legacy stamp with no label and no score: honest, not invented.
      await tester.pumpWidget(
        _host(
          FakeIngredientRepo(const [
            Ingredient(
              id: 'old',
              canonicalName: 'Old prefill',
              defaultUnit: g,
              status: IngredientStatus.stub,
              source: 'usda_fdc:171705',
            ),
          ]),
          at: '/ingredients/old',
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('FDC 171705'), findsOneWidget);
      // No band word invented for a score the row never carried.
      expect(find.textContaining('for “Old prefill”'), findsNothing);
    });

    testWidgets('U-D1: a CONFIRMED prefill still names its match, and says '
        'confirmed', (tester) async {
      _filterSemanticsAssertions();
      _tallScreen(tester);
      final repo = FakeIngredientRepo([
        _curryLeaves.copyWith(
          status: IngredientStatus.complete,
          macros: _usdaAnswer.macros,
        ),
      ]);
      await tester.pumpWidget(_host(repo, at: '/ingredients/curry'));
      await tester.pumpAndSettle();
      expect(find.text('Filled from USDA · confirmed'), findsOneWidget);
      expect(find.widgetWithText(FButton, 'Not this food'), findsOneWidget);
    });

    testWidgets('U-D2: a DECLINED row names the food it refused, says the '
        'numbers were cleared, offers Choose another alone, and warns that a '
        'rename will not refill it', (tester) async {
      _filterSemanticsAssertions();
      _tallScreen(tester);
      final repo = FakeIngredientRepo([
        _curryLeaves.copyWith(source: usdaDeclinedSource),
      ]);
      await tester.pumpWidget(_host(repo, at: '/ingredients/curry'));
      await tester.pumpAndSettle();
      expect(find.text('USDA · declined'), findsOneWidget);
      expect(
        find.text(
          'Curry leaves, raw — not this food · the filled numbers were '
          'cleared',
        ),
        findsOneWidget,
      );
      expect(find.widgetWithText(FButton, 'Not this food'), findsNothing);
      expect(find.widgetWithText(FButton, 'Choose another ›'), findsOneWidget);
      expect(
        find.text('renaming this row will not refill it — you said no once'),
        findsOneWidget,
      );
      expect(find.text('Look up in USDA'), findsNothing);
    });

    testWidgets('U-D2: tapping Not this food clears the prefilled numbers '
        'from the row AND the open form, and the line turns into the '
        'declined one', (tester) async {
      _filterSemanticsAssertions();
      _tallScreen(tester);
      final repo = FakeIngredientRepo([
        _curryLeaves.copyWith(
          densityGPerMl: _usdaAnswer.densityGPerMl,
          macros: _usdaAnswer.macros,
          allowedUnits: const [g, kg, tsp, tbsp, cup, ml],
        ),
      ]);
      await tester.pumpWidget(_host(repo, at: '/ingredients/curry'));
      await tester.pumpAndSettle();
      expect(_macroFieldText(tester, 'kcal'), '108');
      // A pending edit in a field the undo has no business with.
      await tester.enterText(_measureLabelField, 'small bunch');
      await tester.pump();

      await tester.tap(find.widgetWithText(FButton, 'Not this food'));
      await tester.pumpAndSettle();

      final row = (await repo.byId('curry'))!;
      expect(row.source, usdaDeclinedSource);
      expect(row.densityGPerMl, isNull);
      expect(row.macros, isNull);
      expect(row.sourceLabel, 'Curry leaves, raw');
      expect(row.status, IngredientStatus.stub);
      // D4b on screen: the volume family the density alone admitted is out.
      expect(row.allowedUnits!.map((u) => u.id).toSet(), {'g', 'kg'});
      // The form followed the row (G1): four blank fields, not stale numbers
      // a Save would write straight back.
      expect(_macroFieldText(tester, 'kcal'), isEmpty);
      expect(_macroFieldText(tester, 'fat'), isEmpty);
      expect(
        tester.widget<TextField>(_measureLabelField).controller!.text,
        'small bunch',
      );
      expect(find.text('USDA · declined'), findsOneWidget);
      expect(find.widgetWithText(FButton, 'Not this food'), findsNothing);
      expect(
        find.textContaining('a rename will not bring them back'),
        findsOneWidget,
      );
    });

    testWidgets('U-D3: Choose another asks for FIVE under the name in the '
        'FIELD — writing nothing to get there — lists them with their band '
        'word (the current match tagged, a nameless one left out), and a pick '
        'replaces the fill through the explicit apply', (tester) async {
      _filterSemanticsAssertions();
      _tallScreen(tester);
      final repo = FakeIngredientRepo([
        _curryLeaves.copyWith(
          densityGPerMl: _usdaAnswer.densityGPerMl,
          macros: _usdaAnswer.macros,
        ),
      ]);
      final probe = _RecordingProbe.list(const [
        _usdaAnswer, // the current match, 11216
        UsdaCandidate(
          fdcId: 11217,
          description: 'Curry leaves, dried',
          category: 'Spices and Herbs',
          source: 'usda_fdc:11217',
          score: 1,
          macros: Macros(kcal: 300, protein: 12, carb: 60, fat: 5),
        ),
        UsdaCandidate(
          fdcId: 11218,
          description: 'Curry powder',
          source: 'usda_fdc:11218',
          score: 0.55,
          densityGPerMl: 0.5,
        ),
        UsdaCandidate(
          fdcId: 11219,
          description: 'Curry, nameless',
          source: 'usda_fdc:11219',
          score: 0.52,
        ),
      ]);
      await tester.pumpWidget(
        _host(repo, at: '/ingredients/curry', probe: probe),
      );
      await tester.pumpAndSettle();

      // A rename typed and not saved: the sheet must ask about THIS name.
      await tester.enterText(find.byType(TextField).first, 'Curry leaf');
      await tester.pump();
      await tester.tap(find.widgetWithText(FButton, 'Choose another ›'));
      await tester.pumpAndSettle();

      expect(probe.asked.single, normalizeMatchText('Curry leaf'));
      expect(probe.limits.single, 5);
      expect(find.text('USDA · for “Curry leaf”'), findsOneWidget);
      expect(find.text('Curry leaves, raw'), findsWidgets);
      expect(find.text('current'), findsOneWidget);
      expect(find.text('Curry leaves, dried'), findsOneWidget);
      expect(find.text('Spices and Herbs'), findsOneWidget);
      expect(find.text('all words'), findsOneWidget);
      expect(find.text('Curry powder'), findsOneWidget);
      expect(find.text('some words'), findsOneWidget);
      // Nothing to copy, nothing to pick.
      expect(find.text('Curry, nameless'), findsNothing);

      await tester.tap(find.text('Curry leaves, dried'));
      await tester.pumpAndSettle();

      // The pick is the DRAFT (plan 0029 W5) — it fills the fields and the
      // provenance it will stamp, and the form's one Save lands all of it.
      await _saveForm(tester, reopen: 'Curry leaf');
      final row = (await repo.byId('curry'))!;
      // Looking something up wrote nothing (F1 is retired) — and the Save
      // that follows carries the rename and the pick together, because to
      // the person they were always one act.
      expect(row.canonicalName, 'Curry leaf');
      expect(row.source, 'usda_fdc:11217');
      expect(row.sourceLabel, 'Curry leaves, dried');
      expect(row.sourceScore, 1);
      expect(row.macros!.kcal, 300);
      expect(row.densityGPerMl, isNull); // the old fill is replaced whole
      expect(row.status, IngredientStatus.stub);
      // The form followed: the line names the new food, the fields carry
      // its numbers.
      expect(
        find.textContaining(
          'Curry leaves, dried · FDC 11217 · matches every word',
        ),
        findsOneWidget,
      );
      expect(_macroFieldText(tester, 'kcal'), '300');
    });

    testWidgets('U-D3: on a DECLINED row the refused food is tagged and the '
        'pick lands despite the decline — a person’s own choice', (
      tester,
    ) async {
      _filterSemanticsAssertions();
      _tallScreen(tester);
      final repo = FakeIngredientRepo([
        _curryLeaves.copyWith(source: usdaDeclinedSource),
      ]);
      final probe = _RecordingProbe.list(const [
        _usdaAnswer,
        UsdaCandidate(
          fdcId: 11217,
          description: 'Curry leaves, dried',
          source: 'usda_fdc:11217',
          score: 1,
          macros: Macros(kcal: 300, protein: 12, carb: 60, fat: 5),
        ),
      ]);
      await tester.pumpWidget(
        _host(repo, at: '/ingredients/curry', probe: probe),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FButton, 'Choose another ›'));
      await tester.pumpAndSettle();

      expect(find.text('declined'), findsOneWidget);
      await tester.tap(find.text('Curry leaves, dried'));
      await tester.pumpAndSettle();

      // The pick is the DRAFT (plan 0029 W5) — it fills the fields and the
      // provenance it will stamp, and the form's one Save lands all of it.
      await _saveForm(tester, reopen: _curryLeaves.canonicalName);
      final row = (await repo.byId('curry'))!;
      expect(row.source, 'usda_fdc:11217');
      expect(row.sourceLabel, 'Curry leaves, dried');
      expect(find.text('Filled from USDA · not confirmed'), findsOneWidget);
    });

    testWidgets('U-D3 offline: the sheet says nothing came back, and closing '
        'it changes nothing', (tester) async {
      _filterSemanticsAssertions();
      _tallScreen(tester);
      final repo = FakeIngredientRepo(const [_curryLeaves]);
      await tester.pumpWidget(_host(repo, at: '/ingredients/curry'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FButton, 'Choose another ›'));
      await tester.pumpAndSettle();

      expect(
        find.textContaining('nothing came back for “Curry leaves, fresh”'),
        findsOneWidget,
      );
      expect(find.byType(FDialog), findsNothing);
      await tester.tap(find.byIcon(FLucideIcons.x).last);
      await tester.pumpAndSettle();
      expect((await repo.byId('curry'))!.source, 'usda_fdc:11216');
    });

    testWidgets('a row USDA never touched carries no provenance line at '
        'all', (tester) async {
      _filterSemanticsAssertions();
      _tallScreen(tester);
      await tester.pumpWidget(
        _host(FakeIngredientRepo(const [_blackRice]), at: '/ingredients/rice'),
      );
      await tester.pumpAndSettle();
      expect(find.textContaining('USDA ·'), findsNothing);
      expect(find.textContaining('from USDA'), findsNothing);
      expect(find.text('Look up in USDA'), findsOneWidget);
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

      await tester.tap(find.byKey(kFormCompleteKey));
      await tester.pumpAndSettle();

      final row = await repo.byId('curry');
      expect(row!.status, IngredientStatus.complete);
      expect(row.macros, const Macros(kcal: 108, protein: 6, carb: 19, fat: 1));
      expect(row.densityGPerMl, isNull); // never required (D5)
      // Completing ends the page — the caller that pushed it is waiting.
      expect(find.text('CANONICAL NAME'), findsNothing);
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
        await _openMoreMenu(tester);
        await tester.tap(find.text('Return it to a stub'));
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
      expect(
        find.textContaining('unlock when this row has a density'),
        findsNothing,
      );
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
      expect(_lockedUnitLabels(tester), {'tsp', 'tbsp', 'cup', 'ml', 'pt'});
      expect(
        find.textContaining('unlock when this row has a density'),
        findsOneWidget,
      );
      // The basis side is toggleable from the start — it never needed one.
      expect(_lockedUnitLabels(tester), isNot(contains('g')));
      expect(_lockedUnitLabels(tester), isNot(contains('piece')));

      // 2. A density in the draft: the chips come live IMMEDIATELY, because
      // they read what the form holds — but nothing is written until Save
      // (W5). That split is the whole point of lane B.
      await _draftDensity(tester, '0.66');

      expect(
        (await repo.byId('mango'))!.densityGPerMl,
        isNull,
        reason: 'the density is in the draft, not the database, until Save',
      );
      expect(_lockedUnitLabels(tester), isEmpty);
      expect(
        find.textContaining('unlock when this row has a density'),
        findsNothing,
      );

      await _saveForm(tester, reopen: 'Mango');
      expect((await repo.byId('mango'))!.densityGPerMl, 0.66);

      // 3. Delete it: the strip leg, in the same write, with the consequence
      // named before it happens.
      await tester.tap(find.text('remove the density'));
      await tester.pumpAndSettle();
      expect(find.textContaining('lock again'), findsOneWidget);
      await tester.tap(find.widgetWithText(FButton, 'Remove'));
      await tester.pumpAndSettle();
      // Same rule on the way out: the chips lock again at once, the row keeps
      // its number until Save.
      expect(_lockedUnitLabels(tester), {'tsp', 'tbsp', 'cup', 'ml', 'pt'});
      await _saveForm(tester, reopen: 'Mango');

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
      expect(_lockedUnitLabels(tester), {'tsp', 'tbsp', 'cup', 'ml', 'pt'});
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
        find.textContaining('unlock when this row has a density'),
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

      await _openMoreMenu(tester);
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
      await _openMoreMenu(tester);
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
          matching: find.widgetWithText(FButton, 'Add'),
        ),
      );
      await tester.pumpAndSettle();

      // On screen at once, and NOT written (plan 0029 W5): a pending measure
      // is indistinguishable from a stored one here, which is what lets the
      // `piece` question and "Counts as" point at it before it exists.
      expect(
        find.descendant(
          of: find.byType(MeasureRow),
          matching: find.text('half cheek'),
        ),
        findsOneWidget,
      );
      expect(
        measures.rows.map((m) => m.label),
        isNot(contains('half cheek')),
        reason: 'nothing is written until the form is saved',
      );

      // …and delete one. Also draft-only: it leaves the list, and the stored
      // row is untouched until Save.
      await tester.tap(find.byIcon(FLucideIcons.trash2).first);
      await tester.pumpAndSettle();
      expect(find.text('mango, medium'), findsNothing);
      expect(measures.rows.map((m) => m.label), contains('mango, medium'));

      // One Save carries both, and the form asked for exactly them.
      final repo = _repoOf(tester);
      await _saveForm(tester);
      final asked = repo.savedForms.single;
      expect(asked.measuresAdded.single.label, 'half cheek');
      expect(asked.measuresAdded.single.amount, 90);
      expect(asked.measuresRemoved, {'m-usda'});
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
          // `Add` on this host: the tap fills the draft, and the form's own
          // docked Save is what writes (plan 0029 R3).
          matching: find.widgetWithText(FButton, 'Add'),
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
      expect(find.text('of this weighs'), findsOneWidget);
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
          // `Add` on this host: the tap fills the draft, and the form's own
          // docked Save is what writes (plan 0029 R3).
          matching: find.widgetWithText(FButton, 'Add'),
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

      // The answer IS the draft now (plan 0029 W5): `piece` leaves the chips
      // the form holds at once, and the row keeps it until Save. That is the
      // lane B trap answered — the chips follow the draft, not a row nobody
      // has written.
      expect(allowedUnitsFor(repo.rows.single), contains(pieces));

      await _saveForm(tester);
      final asked = repo.savedForms.single;
      expect(asked.row.allowedUnits, isNot(contains(pieces)));
      // Nothing else went with it — one word, not a re-curation.
      expect(asked.row.allowedUnits, contains(g));
      // …and the same act said what a bare "1 mango" means (seam D1).
      expect(
        (asked.defaultMeasure as DefaultMeasureSet).measureId,
        asked.measuresAdded.single.id,
      );
      expect(asked.measuresAdded.single.label, 'mango, medium');
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

      // The measure leaves the list at once; the row is written on Save.
      expect(find.byType(MeasureRow), findsNothing);
      // Save ends the page, so walk back in to read the chips.
      await _saveForm(tester, reopen: 'Mango');
      // No automatic re-add: the household said no, and a deletion is not
      // them changing their mind.
      expect(repo.savedForms.last.row.allowedUnits, isNot(contains(pieces)));
      // But the chip is still drawn, and drawn LIVE (not dashed): a count
      // row needs no density for `piece`, so it is one tap from returning.
      expect(_lockedUnitLabels(tester), isNot(contains('piece')));
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

      // Both halves ride the form's one Save now, and they ride it together —
      // which is the point seam D1 was always making.
      await _saveForm(tester);
      final asked = repo.savedForms.single;
      expect(
        (asked.defaultMeasure as DefaultMeasureSet).measureId,
        asked.measuresAdded.single.id,
      );
      expect(asked.row.allowedUnits, isNot(contains(pieces)));
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

      expect(find.text('COUNTS AS'), findsOneWidget);
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

      expect(find.text('COUNTS AS'), findsNothing);
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

    testWidgets('THE OWNER’S FLOW, rebuilt: rename then look up — USDA is '
        'asked about the name in the FIELD, and nothing is written to get '
        'there', (tester) async {
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

      await _lookUpUsdaAndPick(tester, 'Curry leaves, raw');

      // The bug F1 was written for cannot recur: the query is the field, so
      // there is no stored name to go stale — and asking costs no write.
      expect(probe.asked.single, normalizeMatchText('Chicken Breast'));
      expect(
        (await repo.byId('curry'))!.macros,
        isNull,
        reason: 'a pick fills the draft; Save writes it (plan 0029 W5)',
      );

      // One Save carries the rename AND the pick — to the person they were
      // always one act, and now they are one write. Save ends the page, so
      // walk back in to read what the form says afterwards.
      await _saveForm(tester, reopen: 'Chicken Breast');
      final row = (await repo.byId('curry'))!;
      expect(row.canonicalName, 'Chicken Breast');
      expect(repo.matchTextById['curry'], normalizeMatchText('Chicken Breast'));
      // …and the picked answer landed, without completing the row (D5).
      expect(row.densityGPerMl, 0.35);
      expect(row.macros, const Macros(kcal: 108, protein: 6, carb: 19, fat: 1));
      expect(row.source, 'usda_fdc:11216');
      expect(row.sourceLabel, 'Curry leaves, raw');
      expect(row.status, IngredientStatus.stub);
      // Since 0027 the fill is NAMED where the numbers live, and the lookup
      // section (with its "filled this in" note) retires — the provenance
      // line and its doors are the way the match changes from here.
      expect(find.text('Filled from USDA · not confirmed'), findsOneWidget);
      expect(
        find.textContaining(
          'Curry leaves, raw · FDC 11216 · matches only part of ',
        ),
        findsOneWidget,
      );
      expect(find.text('Look up in USDA'), findsNothing);
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

      await _lookUpUsdaAndPick(tester, 'Curry leaves, raw');

      // The FIELDS got the numbers at once — which is G1's whole subject —
      // while the row waits for Save.
      expect((await repo.byId('curry'))!.macros, isNull);
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

      // Half a panel in flight. The lookup no longer saves the form to run
      // (F1 is retired), so an incoherent draft no longer BLOCKS it — the
      // question is the name in the field and costs nothing. What still
      // holds is G1's own rule: the pick's numbers reach the fields, and the
      // half-typed one they replace was the row's to replace.
      await tester.enterText(_macroField('kcal'), '999');
      await tester.pump();

      await _lookUpUsdaAndPick(tester, 'Curry leaves, raw');

      // The pick is an explicit act on the macros, so it wins the macro
      // fields outright…
      expect(_macroFieldText(tester, 'kcal'), '108');
      // …and an edit in a field the fill has no opinion about is untouched.
      expect(
        tester.widget<TextField>(find.byType(TextField).first).controller!.text,
        _curryLeaves.canonicalName,
      );
    });

    testWidgets('G1: a pick the user dismisses changes nothing at all', (
      tester,
    ) async {
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

      await tester.enterText(_macroField('kcal'), '999');
      await tester.pump();
      await tester.tap(find.text('Look up in USDA'));
      await tester.pumpAndSettle();
      // Close the short-list without choosing.
      await tester.tap(find.byIcon(FLucideIcons.x).first);
      await tester.pumpAndSettle();

      // Asked, and nothing else: no write, and the number in flight is still
      // in flight. This is what replaces F1's "Save this form first" state —
      // there is nothing to save first any more.
      expect(probe.asked, isNotEmpty);
      expect((await repo.byId('curry'))!.macros, isNull);
      expect(_macroFieldText(tester, 'kcal'), '999');
    });

    // **G3 is retired with `_UsdaLookup`.** Its test pinned a lookup STATUS
    // sentence — "USDA has that name but no numbers for it" — and the rule
    // that a later edit to the row must retire it, because the sentence was
    // the only feedback an automatic probe gave. The fill door is a search
    // now: the feedback is the short-list you are looking at, and a candidate
    // with nothing to copy is left out of it rather than reported afterwards
    // (see the U-D3 test's "Curry, nameless"). There is no status to go
    // stale, so there is nothing to retire.

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

      expect(find.text('of this weighs'), findsOneWidget);
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

      await tester.tap(find.text('switch to g'));
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

      // A density unlocks the whole selector again — off the DRAFT, before
      // anything is written (plan 0029 W5).
      await _draftDensity(tester, '0.75');

      expect(_defaultUnitChip(tester, 'ml').enabled, isTrue);
      expect(find.textContaining('needs a density on this row'), findsNothing);
    });

    testWidgets('offline: the short-list says nothing came back and never '
        'raises an error — the trigger is still the backstop', (tester) async {
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

      // The short-list's own empty state, which covers offline and "nothing
      // close enough" together — a person cannot act differently on the two,
      // and the server trigger re-runs the same probe on upload either way.
      expect(find.textContaining('nothing came back for'), findsOneWidget);
      // No dialog, and the row is untouched.
      expect(find.byType(FDialog), findsNothing);
      expect((await repo.byId('curry'))!.macros, isNull);
    });
  });

  group('creating an ingredient — the form IS the add flow (plan 0029 C2)', () {
    testWidgets('the ＋ opens a form with no row behind it: it says so, it '
        'offers no ⋯, and backing out writes nothing', (tester) async {
      _filterSemanticsAssertions();
      _tallScreen(tester);
      final repo = FakeIngredientRepo(const []);
      await tester.pumpWidget(_host(repo, at: '/ingredients/new'));
      await tester.pumpAndSettle();

      expect(find.text('CANONICAL NAME'), findsOneWidget);
      expect(
        find.text('New — nothing is saved until you tap Save.'),
        findsOneWidget,
      );
      // Nothing to delete and nothing to un-confirm on a row that is not
      // there, so the header carries no menu at all.
      expect(find.byIcon(FLucideIcons.ellipsis), findsNothing);
      expect(repo.rows, isEmpty);
    });

    testWidgets('one Save makes the row AND its children — the sheet needed '
        'two screens, and had already written by the time you saw the second', (
      tester,
    ) async {
      _filterSemanticsAssertions();
      _tallScreen(tester);
      final repo = FakeIngredientRepo(const []);
      await tester.pumpWidget(_host(repo, at: '/ingredients/new'));
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(TextField).first, 'Curry leaves');
      await tester.pump();
      await _draftDensity(tester, '0.4');
      // Still nothing written — the whole point of C2, and what makes backing
      // out of a half-filled form cost nothing.
      expect(repo.rows, isEmpty);

      await _saveForm(tester);
      final asked = repo.savedForms.single;
      expect(asked.row.canonicalName, 'Curry leaves');
      expect((asked.density as DensitySet).gPerMl, 0.4);
      expect(repo.rows.single.canonicalName, 'Curry leaves');
      // Born a stub whatever was filled in (D5): only Mark complete promotes,
      // and that is a human act.
      expect(repo.rows.single.status, IngredientStatus.stub);
    });

    testWidgets('a name carried in from a picker prefills the field', (
      tester,
    ) async {
      _filterSemanticsAssertions();
      _tallScreen(tester);
      await tester.pumpWidget(
        _host(
          FakeIngredientRepo(const []),
          at: '/ingredients/new?name=Curry%20leaves',
        ),
      );
      await tester.pumpAndSettle();
      expect(
        tester.widget<TextField>(find.byType(TextField).first).controller!.text,
        'Curry leaves',
      );
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
      await tester.tap(find.text('Scan a barcode'));
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
      // In the list at once and in the DRAFT, not the database (plan 0029
      // W5) — which is also what lets a barcode-CREATED row carry its pack
      // size before the row exists at all.
      expect(
        find.descendant(
          of: find.byType(MeasureRow),
          matching: find.text('pack'),
        ),
        findsOneWidget,
      );
      expect(measures.rows, isEmpty);
      expect(offer, findsNothing);
      expect(find.textContaining('pack added below'), findsOneWidget);

      await _saveForm(tester);
      final asked = repo.savedForms.single;
      expect(asked.measuresAdded.single.label, 'pack');
      expect(asked.measuresAdded.single.amount, 1000);
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
      expect(find.text('Scan a barcode'), findsNothing);
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

    /// The shared setup for the two M-D2 legs: a bare per-100 g stub, put
    /// into per-serving mode with a 14 g "1 tbsp" serving and a label's four.
    Future<Finder> armTheOffer(
      WidgetTester tester,
      FakeIngredientRepo repo,
    ) async {
      await tester.pumpWidget(_host(repo, at: '/ingredients/spread'));
      await tester.pumpAndSettle();
      expect(_lockedUnitLabels(tester), containsAll(['tbsp', 'ml']));

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

      expect(find.text('THIS SERVING ALSO SAYS'), findsOneWidget);
      final tick = find.byKey(const ValueKey('serving-offer'));
      expect(find.text('1 tbsp weighs 14 g — set as density'), findsOneWidget);
      expect(tester.widget<FCheckbox>(tick).value, isFalse);
      return tick;
    }

    testWidgets('M-D2: the offer is OFF by default — an untouched Save writes '
        'the macros and NOTHING else', (tester) async {
      _filterSemanticsAssertions();
      _tallScreen(tester);
      final repo = FakeIngredientRepo(const [spread]);
      await armTheOffer(tester, repo);

      await _saveForm(tester);
      final saved = (await repo.byId('spread'))!;
      expect(saved.macros, isNotNull);
      // The whole point: a pack's "about 1 tbsp" is sometimes a guess, and a
      // density minted from a guess would decide what units the row admits.
      expect(saved.densityGPerMl, isNull);
    });

    testWidgets('M-D2: ticked, the same Save lands it through setDensity and '
        'the volume chips unlock', (tester) async {
      _filterSemanticsAssertions();
      _tallScreen(tester);
      final repo = FakeIngredientRepo(const [spread]);
      final tick = await armTheOffer(tester, repo);

      await tester.tap(tick);
      await tester.pumpAndSettle();
      expect(tester.widget<FCheckbox>(tick).value, isTrue);
      expect(find.textContaining('= 0.947 g/ml'), findsOneWidget);

      // One Save: the macros through the row's own write, the density through
      // density entry's own spoon arithmetic (ADR-0008 §2), and ADR-0009's
      // unlock. Save ends the page, so we walk back in to read the chips.
      await _saveForm(tester, reopen: 'Buttery spread');
      final saved = (await repo.byId('spread'))!;
      expect(saved.densityGPerMl, closeTo(14 / tbsp.ratioToBase!, 1e-9));
      expect(_lockedUnitLabels(tester), isNot(contains('tbsp')));
      expect(_lockedUnitLabels(tester), isNot(contains('ml')));
      expect(find.textContaining('0.947 g/ml'), findsWidgets);
      // Landed, and it cannot be written twice: the reopened form reads the
      // row's own per-100 macros, so there is no serving and no offer at all.
      expect(find.text('THIS SERVING ALSO SAYS'), findsNothing);
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
      // The offer rides the form's ONE write now, so what it asked for is
      // where the assertion lives (plan 0029 W3).
      final asked = repo.savedForms.single;
      expect(asked.measuresAdded.single.label, 'slice');
      expect(asked.measuresAdded.single.amount, 28);
      expect((await repo.byId('spread'))!.macros!.kcal, closeTo(285.71, 0.01));
      // No density from a slice — that offer is a spoon's alone.
      expect(asked.density, isA<DensityUnchanged>());
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
        await tester.tap(find.text('Scan a barcode'));
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

      testWidgets('creating by barcode: the serving row under the card, '
          'prefilled — and Save stores the per-100 derivation', (tester) async {
        _filterSemanticsAssertions();
        _tallScreen(tester);
        final repo = FakeIngredientRepo(const []);
        await tester.pumpWidget(
          _addHost(repo, body: _fixture('peanut_butter_per_serving')),
        );
        await tester.pumpAndSettle();

        await tester.tap(find.text('Scan a barcode'));
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

        await _saveForm(tester);

        final created = repo.rows.single;
        expect(created.macros!.kcal, 562.5);
        expect(created.macros!.carb, 31.25);
        expect(created.macrosBasis, MacrosBasis.perG);
        expect(created.source, 'off:0851087000250');
        expect(created.status, IngredientStatus.stub);
      });

      testWidgets('creating by barcode, no numeric serving: flagged, and no '
          'panel is stored unless the weight is typed', (tester) async {
        _filterSemanticsAssertions();
        _tallScreen(tester);
        final repo = FakeIngredientRepo(const []);
        await tester.pumpWidget(_addHost(repo, body: withoutServingQuantity()));
        await tester.pumpAndSettle();

        await tester.tap(find.text('Scan a barcode'));
        await tester.pumpAndSettle();
        await tester.enterText(_scanField, '0851087000250');
        await tester.pump();
        await tester.tap(find.text('Look up'));
        await tester.pumpAndSettle();

        expect(_fieldText(tester, _servingAmountField), isEmpty);

        // Without the weight there is nothing to divide by, so Save REFUSES
        // and says which number is missing — the sheet used to warn about it
        // in advance, and the form's own guard is the better place for it:
        // it cannot be ignored, and it names the field.
        await tester.tap(find.byKey(kFormSaveKey));
        await tester.pumpAndSettle();
        expect(repo.rows, isEmpty);
        expect(find.textContaining('One serving is how much?'), findsOneWidget);

        await tester.enterText(_servingAmountField, '32');
        await tester.pumpAndSettle();

        await _saveForm(tester);
        expect(repo.rows.single.macros!.kcal, 562.5);
      });
    },
  );
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

/// The create form as the `＋` opens it (plan 0029 C2), over a router that
/// can receive it. [body] is what Open Food Facts answers with.
///
/// [viaProvider] chooses WHICH seam delivers that client. False (the default)
/// passes it as a parameter, the way a widget test reaches in. True passes
/// nothing and overrides [offLookupProvider] instead — the app's own wiring,
/// and the seam `make test-sim` drives, since the real screen opens this form
/// from inside a navigation stack no caller can thread a parameter through.
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
    initialLocation: '/ingredients/new',
    routes: [
      GoRoute(
        path: '/ingredients',
        builder: (_, _) => const IngredientListView(),
      ),
      GoRoute(
        path: '/ingredients/new',
        builder: (_, _) => IngredientDetailView(
          lookup: viaProvider ? null : buildLookup(),
          cameraPane: (_, _) => const SizedBox.shrink(),
        ),
      ),
      GoRoute(
        path: '/ingredients/:id',
        builder: (_, state) =>
            IngredientDetailView(ingredientId: state.pathParameters['id']),
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
