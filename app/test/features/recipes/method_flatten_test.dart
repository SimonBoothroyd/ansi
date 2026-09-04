/// D5 (design board frame g): convert to plain text — knowingly, and one-way.
library;

import 'package:ansi/features/books/data/book_providers.dart';
import 'package:ansi/features/ingredients/data/ingredient_providers.dart';
import 'package:ansi/features/recipes/data/recipe_providers.dart';
import 'package:ansi/features/recipes/domain/method_step.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:forui/forui.dart';

import '../../helpers/editor_harness.dart';
import '../../helpers/forui_semantics.dart';

Future<FakeRecipeRepo> openEditor(WidgetTester tester) async {
  filterForuiSemanticsAssertions();
  tallSurface(tester);
  final repo = FakeRecipeRepo(importedRecipe);
  await tester.pumpWidget(
    hostEditor('1', [
      recipeRepositoryProvider.overrideWithValue(repo),
      ingredientRepositoryProvider.overrideWithValue(
        const FakeIngredientRepo(),
      ),
      bookRepositoryProvider.overrideWithValue(FakeBookRepo()),
    ]),
  );
  await tester.pumpAndSettle();
  return repo;
}

Future<void> openMethodMenu(WidgetTester tester) async {
  await tester.tap(find.byIcon(FLucideIcons.ellipsis));
  await tester.pumpAndSettle();
  await tester.tap(find.text('Convert to plain text'));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('the confirm counts what dies, and says why there is no way '
      'back', (tester) async {
    await openEditor(tester);
    await openMethodMenu(tester);

    expect(find.text('Convert the method to plain text?'), findsOneWidget);
    expect(
      find.textContaining('1 ingredient chip and 1 timer become ordinary'),
      findsOneWidget,
    );
    expect(
      find.textContaining('Every sentence reads exactly the same'),
      findsOneWidget,
    );
    expect(find.text('This can’t be undone here'), findsOneWidget);
    expect(
      find.textContaining('matching is online-only, and only at import'),
      findsOneWidget,
    );
  });

  testWidgets('cancelling changes nothing', (tester) async {
    final repo = await openEditor(tester);
    await openMethodMenu(tester);
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();

    await tapSave(tester);
    expect(
      repo.saved.single.methodSteps!.first.tokens.whereType<MethodRef>(),
      hasLength(1),
    );
  });

  testWidgets('converting keeps every sentence and drops every link', (
    tester,
  ) async {
    final repo = await openEditor(tester);
    final before = methodFieldText(tester, 0);

    await openMethodMenu(tester);
    await tester.tap(find.text('Convert to plain text').last);
    await tester.pumpAndSettle();

    // Byte-identical prose — the cards were already showing the fold's text.
    expect(methodFieldText(tester, 0), before);

    await tapSave(tester);
    final steps = repo.saved.single.methodSteps!;
    expect(steps, hasLength(2));
    for (final step in steps) {
      expect(step.tokens.whereType<MethodRef>(), isEmpty);
      expect(step.tokens.whereType<MethodTimer>(), isEmpty);
      expect(step.tokens.single, isA<MethodText>());
    }
    expect(
      (steps.first.tokens.single as MethodText).s,
      'Halve the fennel bulb and roast for 25–30 min.',
    );
  });

  testWidgets('there is no re-chip: converting twice is a no-op', (
    tester,
  ) async {
    await openEditor(tester);
    await openMethodMenu(tester);
    await tester.tap(find.text('Convert to plain text').last);
    await tester.pumpAndSettle();

    // Nothing left to count, so the confirm does not even open.
    await tester.tap(find.byIcon(FLucideIcons.ellipsis));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Convert to plain text'));
    await tester.pumpAndSettle();
    expect(find.text('Convert the method to plain text?'), findsNothing);
  });
}
