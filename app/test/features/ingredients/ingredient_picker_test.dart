/// The picker's result list — the "did you mean" band and the honest empty
/// state — plus its add-new footer, which since plan 0025 D3 is one chain:
/// the New-ingredient sheet (name prefilled from the query) → the flesh-out
/// form pushed over the picker → back → the picker resolves with the row AS
/// THE FORM LEFT IT. No stub is minted before anyone has said anything, and
/// there is no "use it" door that skips the form.
// The pumped ProviderScope IS the root scope of each test's tree.
// ignore_for_file: scoped_providers_should_specify_dependencies
library;

import 'package:ansi/core/theme/ansi_theme.dart';
import 'package:ansi/core/units/units.dart';
import 'package:ansi/features/ingredients/data/ingredient_providers.dart';
import 'package:ansi/features/ingredients/domain/ingredient.dart';
import 'package:ansi/features/ingredients/presentation/ingredient_picker.dart';
import 'package:ansi/features/ingredients/presentation/new_ingredient_sheet.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:forui/forui.dart';
import 'package:go_router/go_router.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

import '../../helpers/fake_ingredient_repository.dart';
import '../../helpers/fake_measure_repository.dart';
import '../../helpers/forui_semantics.dart';
import '../../helpers/silent_usda_probe.dart';

/// The list and the add-new footer together, the way the sheet composes them:
/// an empty result list is only honest if the way out is still on screen.
Widget _resultsHost({
  required List<Ingredient> results,
  required String query,
  bool guessed = false,
}) => ProviderScope(
  overrides: [
    ingredientRepositoryProvider.overrideWithValue(FakeIngredientRepo(results)),
  ],
  child: MaterialApp(
    home: FTheme(
      data: ansiThemeData(),
      child: FScaffold(
        child: Column(
          children: [
            Expanded(
              child: IngredientResultList(
                results: results,
                query: query,
                showingRecents: false,
                guessed: guessed,
                onPick: (_) {},
              ),
            ),
            AddNewIngredientRow(query: query, onCreated: (_) {}),
          ],
        ),
      ),
    ),
  ),
);

Ingredient _row(String name) => Ingredient(
  id: name,
  canonicalName: name,
  defaultUnit: g,
  status: IngredientStatus.stub,
);

/// The picker over a router that can receive the form push the chain makes.
/// The "form" is a stand-in page that pops on `back`; what the real form
/// would have written is written straight into [repo] while it is up.
Widget _chainHost(
  FakeIngredientRepo repo, {
  required void Function(Ingredient?) onPicked,
}) {
  final router = GoRouter(
    initialLocation: '/',
    routes: [
      GoRoute(
        path: '/',
        builder: (_, _) => FScaffold(
          child: Builder(
            builder: (context) => FButton(
              onPress: () async =>
                  onPicked(await showIngredientPicker(context)),
              child: const Text('open'),
            ),
          ),
        ),
      ),
      GoRoute(
        path: '/ingredients/:id',
        builder: (context, state) => FScaffold(
          child: Column(
            children: [
              Text('form ${state.pathParameters['id']}'),
              FButton(onPress: () => context.pop(), child: const Text('back')),
            ],
          ),
        ),
      ),
    ],
  );
  addTearDown(router.dispose);
  return ProviderScope(
    overrides: [
      ingredientRepositoryProvider.overrideWithValue(repo),
      measureRepositoryProvider.overrideWithValue(FakeMeasureRepo()),
      usdaProbeProvider.overrideWithValue(const SilentUsdaProbe()),
    ],
    child: MaterialApp.router(
      routerConfig: router,
      builder: (context, child) => FTheme(data: ansiThemeData(), child: child!),
    ),
  );
}

/// The add sheet's name field — the first text field it renders.
String _sheetNameText(WidgetTester tester) => tester
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

void main() {
  group('the "did you mean" band', () {
    testWidgets('guessed rows arrive under a header that says so', (
      tester,
    ) async {
      await tester.pumpWidget(
        _resultsHost(
          results: [_row('Onion'), _row('Red Onion')],
          query: 'nion',
          guessed: true,
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('DID YOU MEAN'), findsOneWidget);
      expect(find.text('Onion'), findsOneWidget);
      // The way out is still offered — a guess is never the only option.
      expect(find.textContaining('add "nion"'), findsOneWidget);
    });

    testWidgets('a spelled result carries no header at all', (tester) async {
      await tester.pumpWidget(
        _resultsHost(results: [_row('Onion')], query: 'onion'),
      );
      await tester.pumpAndSettle();

      expect(find.text('DID YOU MEAN'), findsNothing);
      expect(find.text('Onion'), findsOneWidget);
    });
  });

  group('the empty state', () {
    testWidgets('names the query, and keeps the add-new footer', (
      tester,
    ) async {
      await tester.pumpWidget(_resultsHost(results: const [], query: 'tfu'));
      await tester.pumpAndSettle();

      expect(find.text('No match for "tfu".'), findsOneWidget);
      expect(find.textContaining('add "tfu"'), findsOneWidget);
      expect(find.text('DID YOU MEAN'), findsNothing);
    });

    testWidgets('says when the query was too short to guess from', (
      tester,
    ) async {
      // Three characters is where the phone stops guessing, and the silence
      // is explained rather than left mysterious.
      await tester.pumpWidget(_resultsHost(results: const [], query: 'tfu'));
      await tester.pumpAndSettle();
      expect(
        find.textContaining('Too few letters to guess from'),
        findsOneWidget,
      );

      // A long query that simply has no match gets no such excuse.
      await tester.pumpWidget(
        _resultsHost(results: const [], query: 'xylophone'),
      );
      await tester.pumpAndSettle();
      expect(find.text('No match for "xylophone".'), findsOneWidget);
      expect(find.textContaining('Too few letters'), findsNothing);
    });

    testWidgets('an unsearched, empty vocabulary reads differently', (
      tester,
    ) async {
      await tester.pumpWidget(_resultsHost(results: const [], query: ''));
      await tester.pumpAndSettle();
      expect(find.text('No ingredients yet.'), findsOneWidget);
    });

    testWidgets('with nothing typed the footer is inert and says what to do', (
      tester,
    ) async {
      await tester.pumpWidget(_resultsHost(results: const [], query: '  '));
      await tester.pumpAndSettle();
      expect(find.text('can’t find it? type a name to add it'), findsOneWidget);
    });
  });

  group('the add-new chain (plan 0025 D3, frames c1–c4)', () {
    testWidgets('sheet (name prefilled) → form → back → the picker resolves '
        'with the row as the form left it', (tester) async {
      filterForuiSemanticsAssertions();
      final repo = FakeIngredientRepo(const []);
      final picked = <Ingredient?>[];
      await tester.pumpWidget(_chainHost(repo, onPicked: picked.add));
      await tester.pumpAndSettle();
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(TextField).first, 'Curry leaves');
      await tester.pumpAndSettle();
      // Nothing is written by the tap itself — the sheet is what opens.
      await tester.tap(find.textContaining('add "Curry leaves"'));
      await tester.pumpAndSettle();
      expect(repo.rows, isEmpty);
      expect(find.text('New ingredient'), findsOneWidget);
      // Frame c2: prefilled from what was typed in the picker.
      expect(_sheetNameText(tester), 'Curry leaves');
      // The sheet's own prose and CTA, unchanged (round-3 detail 6).
      expect(find.text('Create & flesh out'), findsOneWidget);

      await tester.tap(find.text('Create & flesh out'));
      await tester.pumpAndSettle();

      // The row exists, D6-honest, and the form is up OVER the picker —
      // which has NOT resolved: nothing downstream (the quantity sheet) can
      // run before the form is done.
      final created = repo.rows.single;
      expect(created.canonicalName, 'Curry leaves');
      expect(repo.matchTextById[created.id], 'curry leaf');
      expect(find.text('form ${created.id}'), findsOneWidget);
      expect(picked, isEmpty);

      // What the form would do: admit units, land a density.
      repo.rows[0] = created.copyWith(
        allowedUnits: [g, kg, tbsp],
        densityGPerMl: 1,
      );
      await tester.tap(find.text('back'));
      await tester.pumpAndSettle();

      // Back is the only exit, and it is the pop the picker was awaiting: it
      // resolves with the RE-READ row, so the units the form set are what
      // the next surface offers (frame c4).
      expect(picked, hasLength(1));
      expect(picked.single!.id, created.id);
      expect(picked.single!.allowedUnits, [g, kg, tbsp]);
      expect(picked.single!.densityGPerMl, 1);
      // Still a stub — backing out unconfirmed lands the line honestly
      // badged (detail 7), and the picker itself has closed.
      expect(picked.single!.status, IngredientStatus.stub);
      expect(find.text('Add an ingredient'), findsNothing);
      // No strip, no second door.
      expect(find.text('use it'), findsNothing);
      expect(find.text('flesh out now'), findsNothing);
    });

    testWidgets('closing the sheet without creating leaves the picker where '
        'it was, with nothing written', (tester) async {
      filterForuiSemanticsAssertions();
      final repo = FakeIngredientRepo(const []);
      final picked = <Ingredient?>[];
      await tester.pumpWidget(_chainHost(repo, onPicked: picked.add));
      await tester.pumpAndSettle();
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField).first, 'Curry leaves');
      await tester.pumpAndSettle();
      await tester.tap(find.textContaining('add "Curry leaves"'));
      await tester.pumpAndSettle();

      await tester.tap(
        find.descendant(
          of: find.byType(NewIngredientSheet),
          matching: find.byIcon(FLucideIcons.x),
        ),
      );
      await tester.pumpAndSettle();

      expect(repo.rows, isEmpty);
      expect(picked, isEmpty);
      expect(find.text('Add an ingredient'), findsOneWidget);
    });

    testWidgets('a row deleted on the form hands nothing back — the picker '
        'is simply open again', (tester) async {
      filterForuiSemanticsAssertions();
      final repo = FakeIngredientRepo(const []);
      final picked = <Ingredient?>[];
      await tester.pumpWidget(_chainHost(repo, onPicked: picked.add));
      await tester.pumpAndSettle();
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField).first, 'Curry leaves');
      await tester.pumpAndSettle();
      await tester.tap(find.textContaining('add "Curry leaves"'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Create & flesh out'));
      await tester.pumpAndSettle();

      repo.rows.clear(); // the form's delete action
      await tester.tap(find.text('back'));
      await tester.pumpAndSettle();

      expect(picked, isEmpty);
      expect(find.text('Add an ingredient'), findsOneWidget);
    });
  });
}
