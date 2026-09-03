/// The audit's highest-severity site: a `saveRecipe` that threw used to show
/// only as the editor *not navigating*, which reads as a laggy Save button.
/// Save now reports the failure and stays put; a retry that lands navigates.
library;

import 'package:ansi/features/books/data/book_providers.dart';
import 'package:ansi/features/ingredients/data/ingredient_providers.dart';
import 'package:ansi/features/recipes/data/recipe_providers.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/editor_harness.dart';

Future<FakeRecipeRepo> openEditor(
  WidgetTester tester, {
  required bool saveThrows,
}) async {
  ignoreSemanticsAsserts();
  tallSurface(tester);
  final repo = FakeRecipeRepo(importedRecipe, saveThrows: saveThrows);
  await tester.pumpWidget(
    hostEditor('1', [
      recipeRepositoryProvider.overrideWithValue(repo),
      ingredientRepositoryProvider.overrideWithValue(FakeIngredientRepo()),
      bookRepositoryProvider.overrideWithValue(FakeBookRepo()),
    ]),
  );
  await tester.pumpAndSettle();
  return repo;
}

void main() {
  testWidgets('a save that does not land says so, and stays on the editor', (
    tester,
  ) async {
    final repo = await openEditor(tester, saveThrows: true);

    await tapSave(tester);

    expect(repo.saved, isEmpty);
    expect(find.text('Couldn’t save the recipe.'), findsOneWidget);
    expect(find.text('Retry'), findsOneWidget);
    // Still the editor — the navigation is what a landed save buys.
    expect(find.text('Edit recipe'), findsOneWidget);
  });

  testWidgets('a save that lands says nothing at all', (tester) async {
    final repo = await openEditor(tester, saveThrows: false);

    await tapSave(tester);

    expect(repo.saved, hasLength(1));
    expect(find.textContaining('Couldn’t'), findsNothing);
  });
}
