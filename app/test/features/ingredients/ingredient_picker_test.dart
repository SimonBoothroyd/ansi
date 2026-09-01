/// The picker's add-new row and its step-8.5 deep-link seam (plan 0020 D8:
/// one flesh-out surface, not a second inline one).
///
/// The default behaviour — create the stub and hand it straight back — is the
/// shipped 7.7 one and must stay: the shopping top-up embeds this row with no
/// router in scope and nowhere to navigate to.
// The pumped ProviderScope IS the root scope of each test's tree.
// ignore_for_file: scoped_providers_should_specify_dependencies
library;

import 'package:ansi/core/theme/ansi_theme.dart';
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

void main() {
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
