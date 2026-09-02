/// The METHOD slot as step cards (0022 D1 · D7 · D8, design board frames a
/// and e) — including the acceptance test the tracker row asked for: an
/// IMPORTED method opens editable, with every chip and timer intact.
library;

import 'package:ansi/features/books/data/book_providers.dart';
import 'package:ansi/features/ingredients/data/ingredient_providers.dart';
import 'package:ansi/features/recipes/data/recipe_providers.dart';
import 'package:ansi/features/recipes/domain/method_step.dart';
import 'package:ansi/shared/method_step_text.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/editor_harness.dart';

void main() {
  testWidgets('an IMPORTED method opens as editable step cards, chips intact', (
    tester,
  ) async {
    ignoreSemanticsAsserts();
    final repo = FakeRecipeRepo(importedRecipe);
    await tester.pumpWidget(
      hostEditor('1', [
        recipeRepositoryProvider.overrideWithValue(repo),
        ingredientRepositoryProvider.overrideWithValue(FakeIngredientRepo()),
        bookRepositoryProvider.overrideWithValue(FakeBookRepo()),
      ]),
    );
    await tester.pumpAndSettle();
    await scrollToMethod(tester);

    // The read-only notice is gone; the sentence is in an editable field.
    expect(
      find.textContaining('imported as ingredient chips'),
      findsNothing,
    );
    expect(find.text('Step 1'), findsOneWidget);
    expect(find.text('Step 2'), findsOneWidget);
    expect(
      methodFieldText(tester, 0),
      'Halve the fennel bulb and roast for 25–30 min.',
    );
  });

  testWidgets('the focused card grows the toolbar and the "Reads as" preview', (
    tester,
  ) async {
    ignoreSemanticsAsserts();
    await tester.pumpWidget(
      hostEditor('1', [
        recipeRepositoryProvider.overrideWithValue(
          FakeRecipeRepo(importedRecipe),
        ),
        ingredientRepositoryProvider.overrideWithValue(FakeIngredientRepo()),
        bookRepositoryProvider.overrideWithValue(FakeBookRepo()),
      ]),
    );
    await tester.pumpAndSettle();
    await scrollToMethod(tester);

    expect(find.text('READS AS'), findsNothing);
    final field = methodFields().first;
    await tester.ensureVisible(field);
    await tester.pumpAndSettle();
    await tester.tap(field);
    await tester.pumpAndSettle();

    expect(find.text('READS AS'), findsOneWidget);
    expect(find.text('ingredient'), findsOneWidget);
    expect(find.text('timer'), findsOneWidget);
    // The preview is the SHIPPED renderer, so the amount is the real fold.
    expect(find.byType(MethodStepText), findsOneWidget);
    expect(find.text('1'), findsWidgets); // the fennel line's live quantity
  });

  testWidgets('reorder, delete and add a step (D7)', (tester) async {
    ignoreSemanticsAsserts();
    final repo = FakeRecipeRepo(importedRecipe);
    await tester.pumpWidget(
      hostEditor('1', [
        recipeRepositoryProvider.overrideWithValue(repo),
        ingredientRepositoryProvider.overrideWithValue(FakeIngredientRepo()),
        bookRepositoryProvider.overrideWithValue(FakeBookRepo()),
      ]),
    );
    await tester.pumpAndSettle();
    await scrollToMethod(tester);

    final up = find.bySemanticsLabel('Move step 2 up');
    await tester.ensureVisible(up);
    await tester.pumpAndSettle();
    await tester.tap(up);
    await tester.pumpAndSettle();
    expect(methodFieldText(tester, 0), 'Then slice the buns.');

    await tester.ensureVisible(find.text('Add a step'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Add a step'));
    await tester.pumpAndSettle();
    expect(find.text('Step 3'), findsOneWidget);

    final del = find.bySemanticsLabel('Delete step 3');
    await tester.ensureVisible(del);
    await tester.pumpAndSettle();
    await tester.tap(del);
    await tester.pumpAndSettle();
    expect(find.text('Step 3'), findsNothing);
  });

  testWidgets('the editor writes methodSteps for EVERY recipe (D8)', (
    tester,
  ) async {
    ignoreSemanticsAsserts();
    final repo = FakeRecipeRepo(legacyRecipe);
    await tester.pumpWidget(
      hostEditor('1', [
        recipeRepositoryProvider.overrideWithValue(repo),
        ingredientRepositoryProvider.overrideWithValue(FakeIngredientRepo()),
        bookRepositoryProvider.overrideWithValue(FakeBookRepo()),
      ]),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();

    final saved = repo.saved.single;
    expect(saved.steps, isEmpty, reason: 'the plain shape is write-never');
    expect(saved.methodSteps, hasLength(2));
    expect(
      saved.methodSteps!.first.tokens.single,
      const MethodText(s: 'Dice the onion.'),
    );
  });

  testWidgets('typing inside a chip demotes it — asserted through save()', (
    tester,
  ) async {
    ignoreSemanticsAsserts();
    final repo = FakeRecipeRepo(importedRecipe);
    await tester.pumpWidget(
      hostEditor('1', [
        recipeRepositoryProvider.overrideWithValue(repo),
        ingredientRepositoryProvider.overrideWithValue(FakeIngredientRepo()),
        bookRepositoryProvider.overrideWithValue(FakeBookRepo()),
      ]),
    );
    await tester.pumpAndSettle();
    await scrollToMethod(tester);

    final controller = tester
        .widgetList<EditableText>(methodFields())
        .first
        .controller;
    // "fennel bulb" occupies [10, 21); retype inside it.
    controller.value = TextEditingValue(
      text: controller.text.replaceRange(13, 13, 'X'),
      selection: const TextSelection.collapsed(offset: 14),
    );
    await tester.pumpAndSettle();

    await tester.scrollUntilVisible(
      find.text('Save'),
      -240,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();

    final step = repo.saved.single.methodSteps!.first;
    expect(step.tokens.whereType<MethodRef>(), isEmpty);
    expect(step.tokens.whereType<MethodTimer>(), hasLength(1));
    expect(
      (step.tokens.first as MethodText).s,
      startsWith('Halve the fenXnel bulb'),
    );
  });
}
