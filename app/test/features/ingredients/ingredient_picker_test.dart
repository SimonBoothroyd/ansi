/// The picker's result list — the "did you mean" band and the honest empty
/// state — plus its add-new row and the step-8.5 deep-link seam (plan 0020 D8:
/// one flesh-out surface, not a second inline one).
///
/// The default behaviour — create the stub and hand it straight back — is the
/// shipped 7.7 one and must stay: the shopping top-up embeds this row with no
/// router in scope and nowhere to navigate to.
// The pumped ProviderScope IS the root scope of each test's tree.
// ignore_for_file: scoped_providers_should_specify_dependencies
library;

import 'package:ansi/core/theme/ansi_theme.dart';
import 'package:ansi/core/units/units.dart';
import 'package:ansi/features/ingredients/data/ingredient_providers.dart';
import 'package:ansi/features/ingredients/domain/ingredient.dart';
import 'package:ansi/features/ingredients/presentation/ingredient_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:forui/forui.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

import '../../helpers/fake_ingredient_repository.dart';

Widget _host(
  FakeIngredientRepo repo, {
  required ValueChanged<Ingredient> onCreated,
  ValueChanged<Ingredient>? onFleshOut,
}) => ProviderScope(
  overrides: [ingredientRepositoryProvider.overrideWithValue(repo)],
  child: MaterialApp(
    home: FTheme(
      data: ansiThemeData(),
      child: FScaffold(
        child: AddNewIngredientRow(
          query: 'Curry leaves',
          onCreated: onCreated,
          onFleshOut: onFleshOut,
        ),
      ),
    ),
  ),
);

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
  });

  testWidgets('without a flesh-out target the row keeps 7.7 behaviour: create '
      'and hand back, no extra step', (tester) async {
    final repo = FakeIngredientRepo(const []);
    Ingredient? handedBack;
    await tester.pumpWidget(_host(repo, onCreated: (i) => handedBack = i));
    await tester.pumpAndSettle();

    await tester.tap(find.textContaining('add "Curry leaves"'));
    await tester.pumpAndSettle();

    expect(handedBack, isNotNull);
    expect(handedBack!.canonicalName, 'Curry leaves');
    expect(find.text('flesh out now'), findsNothing);
  });

  testWidgets('with one, the created stub offers BOTH doors — use it, or go '
      'fill it in', (tester) async {
    final repo = FakeIngredientRepo(const []);
    Ingredient? handedBack;
    Ingredient? fleshedOut;
    await tester.pumpWidget(
      _host(
        repo,
        onCreated: (i) => handedBack = i,
        onFleshOut: (i) => fleshedOut = i,
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.textContaining('add "Curry leaves"'));
    await tester.pumpAndSettle();

    // The stub already exists — the strip is about where you go next, not
    // whether it was saved.
    expect(repo.rows, hasLength(1));
    expect(find.text('added “Curry leaves” as a stub'), findsOneWidget);
    expect(handedBack, isNull);

    await tester.tap(find.text('flesh out now'));
    await tester.pumpAndSettle();
    expect(fleshedOut!.id, repo.rows.single.id);
  });

  testWidgets('the stub it creates carries the server-rule match_text (D6)', (
    tester,
  ) async {
    final repo = FakeIngredientRepo(const []);
    await tester.pumpWidget(_host(repo, onCreated: (_) {}));
    await tester.pumpAndSettle();
    await tester.tap(find.textContaining('add "Curry leaves"'));
    await tester.pumpAndSettle();
    expect(repo.matchTextById[repo.rows.single.id], 'curry leaf');
  });
}
