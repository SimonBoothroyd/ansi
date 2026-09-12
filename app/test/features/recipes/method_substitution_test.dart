/// D6 + D3 (design board frame f): the open line card's `change ›` re-points
/// the line, so it keeps its id across a swap — and the chips that point at it
/// take the new name, visibly and revertibly.
///
/// The invariant, pinned here and in the domain suite: **a chip never names
/// something the recipe does not contain**, and a saved method never refs a
/// line the recipe does not have.
library;

import 'package:ansi/features/books/data/book_providers.dart';
import 'package:ansi/features/ingredients/data/ingredient_providers.dart';
import 'package:ansi/features/recipes/data/recipe_providers.dart';
import 'package:ansi/features/recipes/domain/method_step.dart';
import 'package:ansi/shared/picker_shell.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

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

/// Opens the line named [name], taps the card's `change ›` and picks the fake
/// vocab's only search result, "Pork sausage".
Future<void> substitute(WidgetTester tester, String name) async {
  await openLine(tester, name);
  await tester.tap(changeIdentity());
  await tester.pumpAndSettle();
  await tester.enterText(
    find.descendant(
      of: find.byType(PickerShell),
      matching: find.byType(EditableText),
    ),
    'pork',
  );
  await tester.pumpAndSettle();
  await tester.tap(
    find.descendant(
      of: find.byType(PickerShell),
      matching: find.text('Pork sausage'),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('the open card says what depends on the line, over the two '
      'controls that can break a chip', (tester) async {
    await openEditor(tester);
    // Not on the row: it is not a fact anybody needs while scanning a list of
    // ingredients, and every collapsed row is one height without it.
    expect(find.text('used in 1 step'), findsNothing);

    await openLine(tester, 'Fennel bulb');
    final used = find.text('used in 1 step');
    expect(used, findsOneWidget);
    // Under the head, so it stands over `change ›` and the bin.
    expect(
      tester.getRect(used).top,
      greaterThan(tester.getRect(changeIdentity()).top),
    );
  });

  testWidgets('the card’s identity door re-points the line, keeping its id', (
    tester,
  ) async {
    final repo = await openEditor(tester);
    await substitute(tester, 'Fennel bulb');
    await tapSave(tester);

    final line = repo.saved.single.groups.single.items.first;
    expect(line.id, 'l1', reason: 'the line id is what keeps the chips alive');
    expect(line.ingredientName, 'Pork sausage');
    expect(line.ingredientId, 'ing-new');
  });

  testWidgets('the chips take the new name and the steps are '
      'flagged', (tester) async {
    final repo = await openEditor(tester);
    await substitute(tester, 'Fennel bulb');

    expect(find.text('1 step mentioned Fennel bulb'), findsOneWidget);
    expect(
      find.textContaining('we don’t rewrite your sentences'),
      findsOneWidget,
    );
    expect(find.text('Step 1 · check'), findsOneWidget);
    expect(find.text('was “fennel bulb”'), findsOneWidget);
    // The stored name is "Pork sausage", but the word it replaces sat
    // mid-sentence in lower case, so that is how it reads here.
    expect(
      methodFieldText(tester, 0),
      'Halve the pork sausage and roast for 25–30 min.',
    );

    await tapSave(tester);
    final ref = repo.saved.single.methodSteps!.first.tokens
        .whereType<MethodRef>()
        .single;
    expect(ref.label, 'pork sausage');
    expect(ref.refs, ['l1']);
  });

  testWidgets('"keep the old word" restores the word and keeps the ref', (
    tester,
  ) async {
    final repo = await openEditor(tester);
    await substitute(tester, 'Fennel bulb');

    await tester.tap(find.text('keep the old word'));
    await tester.pumpAndSettle();

    expect(
      methodFieldText(tester, 0),
      'Halve the fennel bulb and roast for 25–30 min.',
    );
    await tapSave(tester);
    final ref = repo.saved.single.methodSteps!.first.tokens
        .whereType<MethodRef>()
        .single;
    expect(ref.label, 'fennel bulb');
    expect(ref.refs, ['l1']);
  });

  testWidgets('removing a referenced line asks, then keeps the words', (
    tester,
  ) async {
    final repo = await openEditor(tester);

    await openLine(tester, 'Fennel bulb');
    await tester.tap(removeLine());
    await tester.pumpAndSettle();
    expect(find.text('1 step mentions Fennel bulb.'), findsOneWidget);
    expect(find.textContaining('only the links go'), findsOneWidget);

    await tester.tap(find.text('Remove'));
    await tester.pumpAndSettle();

    expect(
      methodFieldText(tester, 0),
      'Halve the fennel bulb and roast for 25–30 min.',
    );
    await tapSave(tester);
    final step = repo.saved.single.methodSteps!.first;
    expect(step.tokens.whereType<MethodRef>(), isEmpty);
    expect(repo.saved.single.groups.single.items, hasLength(1));
  });

  testWidgets('save() prunes a dangling ref however it got there', (
    tester,
  ) async {
    filterForuiSemanticsAssertions();
    tallSurface(tester);
    // A method that already refs a line this recipe does not have — the shape
    // a delete + re-add used to leave behind, and what an out-of-order sync
    // can still produce.
    final repo = FakeRecipeRepo(danglingRecipe);
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
    await tapSave(tester);

    final step = repo.saved.single.methodSteps!.single;
    expect(step.tokens.whereType<MethodRef>(), isEmpty);
    // The word survives as prose; the sentence is byte-identical.
    expect((step.tokens.single as MethodText).s, 'Brown the sausage well.');
  });

  testWidgets('cancelling the prompt keeps the line and its chips', (
    tester,
  ) async {
    final repo = await openEditor(tester);

    await openLine(tester, 'Fennel bulb');
    await tester.tap(removeLine());
    await tester.pumpAndSettle();
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();

    await tapSave(tester);
    expect(repo.saved.single.groups.single.items, hasLength(2));
    expect(
      repo.saved.single.methodSteps!.first.tokens.whereType<MethodRef>(),
      hasLength(1),
    );
  });
}
