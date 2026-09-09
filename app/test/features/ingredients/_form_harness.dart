/// The ingredients-manager harness: the vocabulary rows every suite pumps,
/// the finders that target the form's fields by key, and the two hosts (the
/// list-plus-form router, and the create form the `＋` opens).
///
/// One 2,600-line file held eight suites over this one setup. The suites are
/// their own files now — list, form, USDA, macros, and the barcode scan — and
/// this is what they share.
// The pumped ProviderScope IS the root scope of each test's tree (the same
// pattern connecting_view_test documents).
// ignore_for_file: scoped_providers_should_specify_dependencies
library;

import 'dart:io';

import 'package:ansi/core/theme/ansi_theme.dart';
import 'package:ansi/core/units/macros.dart';
import 'package:ansi/core/units/units.dart';
import 'package:ansi/features/ingredients/barcode/barcode_add.dart';
import 'package:ansi/features/ingredients/barcode/barcode_scan_sheet.dart';
import 'package:ansi/features/ingredients/data/ingredient_providers.dart';
import 'package:ansi/features/ingredients/domain/ingredient.dart';
import 'package:ansi/features/ingredients/domain/usda_probe.dart';
import 'package:ansi/features/ingredients/presentation/density_entry.dart';
import 'package:ansi/features/ingredients/presentation/ingredient_detail_view.dart';
import 'package:ansi/features/ingredients/presentation/ingredient_list_view.dart';
import 'package:ansi/features/ingredients/presentation/measures_editor.dart';
import 'package:ansi/features/ingredients/presentation/piece_weight_entry.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:forui/forui.dart';
import 'package:go_router/go_router.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import '../../helpers/fake_ingredient_repository.dart';
import '../../helpers/fake_measure_repository.dart';
import '../../helpers/silent_usda_probe.dart';

const mangoMacros = Macros(kcal: 60, protein: 1, carb: 15, fat: 0);

/// A weighed count row: `piece` is sayable on it because the row says what
/// one weighs (ADR-0015), which is also what keeps its own default off the
/// stranded list.
const mango = Ingredient(
  id: 'mango',
  canonicalName: 'Mango',
  defaultUnit: pieces,
  status: IngredientStatus.complete,
  category: 'produce',
  densityGPerMl: 0.66,
  macros: mangoMacros,
  pieceBasisAmount: 200,
  pieceSource: 'manual',
  measureCount: 3,
  source: 'seed',
);

/// A stub the server prefill stamped and named (0027): the match is a close
/// one, so the form's provenance line says it matches every word.
const curryLeaves = Ingredient(
  id: 'curry',
  canonicalName: 'Curry leaves, fresh',
  defaultUnit: g,
  status: IngredientStatus.stub,
  category: 'produce',
  source: 'usda_fdc:11216',
  sourceLabel: 'Curry leaves, raw',
  sourceScore: 1,
);

/// A USDA-filled row a human has since EDITED (0034): the food is still named,
/// but the macros and the density on the row are the household's now.
const chex = Ingredient(
  id: 'chex',
  canonicalName: 'Chex Cereal',
  defaultUnit: g,
  status: IngredientStatus.complete,
  category: 'pantry',
  densityGPerMl: 0.13,
  macros: Macros(kcal: 379, protein: 7.1, carb: 84, fat: 2.5),
  measureCount: 1,
  source: 'usda_fdc:168930',
  sourceLabel: 'Cereals ready-to-eat, GENERAL MILLS, Corn CHEX',
  sourceScore: 0.91,
  sourceEdited: true,
);

/// A row filled before migration 0027 named the match: the stamp survived, the
/// food's name did not. A-D4 — it says nothing rather than inventing one.
const unnamedFill = Ingredient(
  id: 'unnamed',
  canonicalName: 'Tinned Tomatoes',
  defaultUnit: g,
  status: IngredientStatus.complete,
  category: 'pantry',
  macros: Macros(kcal: 32, protein: 1.6, carb: 7, fat: 0.3),
  source: 'usda_fdc:11529',
);

/// A row a barcode scan filled and a person saved: the stamp is a code, and
/// the label beside it is what every surface actually says out loud.
const scannedSpread = Ingredient(
  id: 'spread',
  canonicalName: 'Hazelnut spread',
  defaultUnit: g,
  status: IngredientStatus.stub,
  category: 'pantry',
  source: 'off:3017620422003',
  sourceLabel: 'Ferrero Nutella',
);

/// The D4c shape the owner hit: a cup default on a per-100 g row with no
/// density, carrying an `allowed_units` list materialized under the looser
/// pre-D4c rule.
const blackRice = Ingredient(
  id: 'rice',
  canonicalName: 'Black rice',
  defaultUnit: cup,
  status: IngredientStatus.stub,
  category: 'pantry',
  allowedUnits: [cup, tbsp, ml, l, g, kg],
  source: 'manual',
);

const yeast = Ingredient(
  id: 'yeast',
  canonicalName: 'Nutritional yeast',
  defaultUnit: tsp,
  status: IngredientStatus.complete,
  category: 'pantry',
  macros: Macros(kcal: 385, protein: 50, carb: 36, fat: 5),
  source: 'seed',
);

/// What the fake probe answers with — the curry-leaf candidate the server's
/// trigram match would have returned.
const usdaAnswer = UsdaCandidate(
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
class RecordingProbe extends UsdaProbe {
  RecordingProbe(UsdaCandidate? answer) : answers = [?answer];

  /// A short-list, best first — what the Choose-another sheet and the
  /// create form ask for.
  RecordingProbe.list(this.answers);

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

/// The route that opens a row in its EDITING posture — what these suites
/// drive. `/ingredients/<id>` on its own is the reading posture now, so a
/// form suite asks for the same route the manager's stub band and the recipe
/// page's fix markers hand over.
String editRoute(String id) => ingredientDetailRoute(id, edit: true);

/// The flesh-out form is one long scroll; a phone-sized test viewport builds
/// only its top and every assertion below the fold fails for the wrong
/// reason. Give the whole form room instead of scrolling to each section.
void tallScreen(WidgetTester tester) {
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
Set<String> lockedUnitLabels(WidgetTester tester) {
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
final Finder categorySelect = find.byWidgetPredicate(
  (w) => w is FSelect<String>,
);

/// The density entry's g/ml input (the only field it renders unless the
/// spoon phrasing is picked).
final Finder densityField = find.descendant(
  of: find.byType(DensityEntry),
  matching: find.byType(TextField),
);

/// The macro input for [label] — keyed on the form so position changes can't
/// silently retarget these.
Finder macroField(String label) => find.descendant(
  of: find.byKey(ValueKey('macro-$label')),
  matching: find.byType(TextField),
);

/// What a macro field currently SHOWS — the assertion G1 exists for: the row
/// having the numbers is not the same as the open form having them.
String macroFieldText(WidgetTester tester, String label) =>
    tester.widget<TextField>(macroField(label)).controller!.text;

/// The per-serving mode's serving amount / name inputs (plan 0027 M-D1),
/// keyed on the shared row so both hosts' tests find the same field.
final Finder servingAmountField = find.descendant(
  of: find.byKey(const ValueKey('serving-amount')),
  matching: find.byType(TextField),
);
final Finder servingNameField = find.descendant(
  of: find.byKey(const ValueKey('serving-name')),
  matching: find.byType(TextField),
);
String fieldText(WidgetTester tester, Finder field) =>
    tester.widget<TextField>(field).controller!.text;

/// The four macros the form enters, in the labelled order.
Future<void> typeMacros(
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
    await tester.enterText(macroField(label), value);
    await tester.pump();
  }
}

/// The form's own Save — the last one on the page (the density entry and
/// the measures editor each draw their own above it).
///
/// **Save puts the FORM down, not the page**: an existing row lands on its
/// reading posture, headed with what was just written. A test that goes on
/// asserting form state passes [reopen], the row's canonical name as the fact
/// sheet should now head with it, and the helper walks back in through
/// `⋯ ▸ Edit` the way a person would.
Future<void> saveForm(WidgetTester tester, {String? reopen}) async {
  await tester.tap(find.byKey(kFormSaveKey));
  await tester.pumpAndSettle();
  if (reopen == null) return;
  expect(
    find.text('CANONICAL NAME'),
    findsNothing,
    reason: 'Save should have put the form down',
  );
  expect(
    find.text(reopen),
    findsWidgets,
    reason: 'the fact sheet should head with the row that was just written',
  );
  await openMoreMenu(tester);
  await tester.tap(find.text('Edit'));
  await tester.pumpAndSettle();
}

/// The header's back chevron. Forui builds it from the theme's own icon, so
/// it is found as the header's first action rather than by an icon constant —
/// and `pageBack` does not see it at all, because it is neither a Material
/// nor a Cupertino back button.
Future<void> tapBack(WidgetTester tester) async {
  await tester.tap(find.byType(FHeaderAction).first);
  await tester.pumpAndSettle();
}

/// The measures editor's label input — a field the form's own save never
/// touches, so a pending edit in it is the control for "did the re-seed
/// clobber anything else".
final Finder measureLabelField = find
    .descendant(
      of: find.byType(MeasuresEditor),
      matching: find.byType(TextField),
    )
    .first;

/// A default-unit chip by label, scoped to the D4c selector row — the row
/// draws only the units the ingredient can be counted in, so this also asks
/// whether a unit is OFFERED at all.
Finder defaultUnitChipFinder(String label) => find.descendant(
  of: find.byKey(const ValueKey('default-unit-row')),
  matching: find.widgetWithText(AnsiModeChip, label),
);

/// The chip itself, for its selected / stranded / enabled state.
AnsiModeChip defaultUnitChip(WidgetTester tester, String label) =>
    tester.widget<AnsiModeChip>(defaultUnitChipFinder(label));

/// A macros-basis chip by its label — `per 100 g`, `per 100 ml`, `per
/// serving`.
AnsiModeChip basisChip(WidgetTester tester, String label) =>
    tester.widget<AnsiModeChip>(find.widgetWithText(AnsiModeChip, label));

/// The dock's own Save, for its enabled state — `onPress` is null while the
/// create form's completion gate is unmet.
FButton saveButton(WidgetTester tester) =>
    tester.widget<FButton>(find.byKey(kFormSaveKey));

/// A phone-width viewport, tall enough that the whole form still builds:
/// width is what an overflow is about (G2), and the form is one long scroll.
void phoneWidth(WidgetTester tester) {
  tester.view.physicalSize = const Size(402, 4000);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
}

Widget host(
  FakeIngredientRepo repo, {
  String at = '/ingredients',
  FakeMeasureRepo? measures,
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
      // The app's own wiring: `?edit=1` is what opens the editing posture,
      // so a suite that drives the form asks for the route the app hands a
      // fix door rather than being handed a flag no screen sets.
      GoRoute(
        path: '/ingredients/:id',
        builder: (_, state) => IngredientDetailView(
          ingredientId: state.pathParameters['id'],
          edit: state.uri.queryParameters[kEditPostureQueryParam] == '1',
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
      measureRepositoryProvider.overrideWithValue(
        measures ?? FakeMeasureRepo(),
      ),
      usdaProbeProvider.overrideWithValue(probe ?? const SilentUsdaProbe()),
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
Future<void> lookUpUsdaAndPick(WidgetTester tester, String description) async {
  await tester.tap(find.text('Look up in USDA'));
  await tester.pumpAndSettle();
  await tester.tap(find.text(description));
  await tester.pumpAndSettle();
}

/// Unfolds the density block when a stated density has folded it to
/// `0.66 g/ml · change` (plan 0036 C-D3), and does nothing when it is already
/// open. Every helper that touches the sentence goes through this, so a test
/// never has to know which state the row it picked happens to be in.
Future<void> openDensityEntry(WidgetTester tester) =>
    _unfold(tester, find.byType(DensityEntry));

/// The same, for the piece-weight block — both entries fold to `· change`, so
/// the opener is scoped to the one being driven.
Future<void> openPieceWeightEntry(WidgetTester tester) =>
    _unfold(tester, find.byType(PieceWeightEntry));

Future<void> _unfold(WidgetTester tester, Finder entry) async {
  final change = find.descendant(of: entry, matching: find.text('· change'));
  if (change.evaluate().isEmpty) return;
  await tester.tap(change);
  await tester.pumpAndSettle();
}

/// Puts a piece weight in the form's DRAFT — the count-side twin of
/// [draftDensity]. The inline button reads `Add` on this host because the
/// form's own Save is what lands it.
Future<void> draftPieceWeight(WidgetTester tester, String amount) async {
  await openPieceWeightEntry(tester);
  await tester.enterText(pieceWeightField, amount);
  await tester.pump();
  await tester.tap(find.byKey(const ValueKey('piece-weight-save')));
  await tester.pumpAndSettle();
}

/// The piece-weight sentence's amount input.
final Finder pieceWeightField = find.descendant(
  of: find.byKey(const ValueKey('piece-weight-field')),
  matching: find.byType(TextField),
);

/// Puts a density in the form's DRAFT (plan 0029 W5). The entry's inline
/// button reads `Add` on this host, because on this host it writes nothing —
/// the form's own Save is what lands it. `ml`'s ratio to base is 1, so
/// picking it makes the typed number a raw g/ml.
Future<void> draftDensity(WidgetTester tester, String gPerMl) async {
  await openDensityEntry(tester);
  await tester.tap(
    find.descendant(of: find.byType(DensityEntry), matching: find.text('ml')),
  );
  await tester.pump();
  await tester.enterText(densityField, gPerMl);
  await tester.pump();
  await tester.tap(find.widgetWithText(FButton, 'Add').first);
  await tester.pumpAndSettle();
}

/// The `FakeIngredientRepo` the pumped host is using — so a test can read
/// [FakeIngredientRepo.savedForms], which is what the form ASKED for, as
/// distinct from what the row ended up being.
FakeIngredientRepo repoOf(WidgetTester tester) =>
    ProviderScope.containerOf(
          tester.element(find.byType(IngredientDetailView)),
          listen: false,
        ).read(ingredientRepositoryProvider)
        as FakeIngredientRepo;

Future<void> openMoreMenu(WidgetTester tester) async {
  await tester.tap(find.byIcon(FLucideIcons.ellipsis));
  await tester.pumpAndSettle();
}

/// The density section on its own, inside the form's own page padding — the
/// width Front C is about, without the rest of the scroll in the way.
///
/// [landsAs] is the row the entry should draw once a save reports landed: both
/// real hosts swap the row under it (the form its draft, the sheet its live
/// copy), and C-D3's fold is a fact about the row that comes back.
Widget densityHost(
  Ingredient ingredient, {
  String saveLabel = 'Add',
  Ingredient? landsAs,
}) {
  var shown = ingredient;
  return ProviderScope(
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
            child: StatefulBuilder(
              builder: (context, setState) => DensityEntry(
                ingredient: shown,
                saveLabel: saveLabel,
                redirectedSpoon: null,
                // This host measures LAYOUT, so the write seam is inert: the
                // widget no longer knows a repository, and this stands in for
                // the host that would land it.
                onSave: (_) async {
                  if (landsAs != null) setState(() => shown = landsAs);
                  return true;
                },
                onRemove: () async {
                  setState(() => shown = ingredient);
                  return true;
                },
              ),
            ),
          ),
        ),
      ),
    ),
  );
}

/// A committed Open Food Facts payload, verbatim — the same fixtures the
/// mapper's table-driven test reads.
String offFixture(String name) => File(
  'test/features/ingredients/barcode/fixtures/$name.json',
).readAsStringSync();

/// The scan surface's typed-number field. Both sheets are in the tree at once
/// while the scanner is open, so this is scoped rather than positional.
final Finder scanField = find.descendant(
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
Widget addHost(
  FakeIngredientRepo repo, {
  required String body,
  FakeMeasureRepo? measures,
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
        builder: (_, state) => IngredientDetailView(
          ingredientId: state.pathParameters['id'],
          edit: state.uri.queryParameters[kEditPostureQueryParam] == '1',
        ),
      ),
    ],
  );
  addTearDown(router.dispose);
  return ProviderScope(
    overrides: [
      ingredientRepositoryProvider.overrideWithValue(repo),
      measureRepositoryProvider.overrideWithValue(
        measures ?? FakeMeasureRepo(),
      ),
      usdaProbeProvider.overrideWithValue(probe ?? const SilentUsdaProbe()),
      if (viaProvider) offLookupProvider.overrideWithValue(buildLookup()),
    ],
    child: MaterialApp.router(
      routerConfig: router,
      builder: (context, child) => FTheme(data: ansiThemeData(), child: child!),
    ),
  );
}
