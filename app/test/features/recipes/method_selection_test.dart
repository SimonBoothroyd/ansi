/// Selection → chip (0022 D2b): highlight a run of a step, and the platform
/// selection toolbar offers **To ingredient** and **To timer** right after
/// Copy.
///
/// The two properties worth pinning: the ingredient path changes NO text (the
/// selected words become the chip's word verbatim), and the timer path parses
/// only the selected substring — never prose it was not pointed at.
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
      ingredientRepositoryProvider.overrideWithValue(FakeIngredientRepo()),
      bookRepositoryProvider.overrideWithValue(FakeBookRepo()),
    ]),
  );
  await tester.pumpAndSettle();
  return repo;
}

/// Selects `[start, end)` of the second step card and raises the platform
/// selection toolbar over it.
Future<void> selectAndShowToolbar(
  WidgetTester tester,
  int card,
  int start,
  int end,
) async {
  final field = methodFields().at(card);
  // The toolbar only exists once the field owns the selection overlay, which
  // means it has to be focused first — exactly as a real long-press does.
  await tester.tap(field);
  await tester.pumpAndSettle();
  tester.widget<EditableText>(field).controller.selection = TextSelection(
    baseOffset: start,
    extentOffset: end,
  );
  await tester.pumpAndSettle();
  tester.state<EditableTextState>(field).showToolbar();
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('the toolbar gains the two items, right after Copy', (
    tester,
  ) async {
    await openEditor(tester);
    // "buns" in "Then slice the buns." — [15, 19).
    await selectAndShowToolbar(tester, 1, 15, 19);

    expect(find.text('To ingredient'), findsOneWidget);
    expect(find.text('To timer'), findsOneWidget);
  });

  testWidgets('To ingredient chips the selection without changing the text', (
    tester,
  ) async {
    final repo = await openEditor(tester);
    await selectAndShowToolbar(tester, 1, 15, 19);

    await tester.tap(find.text('To ingredient'));
    await tester.pumpAndSettle();

    // The picker arrives pre-matched over this recipe's own lines: "buns"
    // hits exactly one, so the whole act is two taps.
    expect(find.text('Chip as “Pretzel Buns”'), findsOneWidget);
    await tester.tap(find.text('Chip as “Pretzel Buns”'));
    await tester.pumpAndSettle();

    expect(methodFieldText(tester, 1), 'Then slice the buns.');
    await tapSave(tester);

    final step = repo.saved.single.methodSteps![1];
    final ref = step.tokens.whereType<MethodRef>().single;
    expect(ref.label, 'buns', reason: 'the selection is the word, verbatim');
    expect(ref.refs, ['l2']);
    // Nothing else in the sentence moved.
    expect((step.tokens.first as MethodText).s, 'Then slice the ');
    expect((step.tokens.last as MethodText).s, '.');
  });

  testWidgets('a second mention of the same line hides its amount (D9)', (
    tester,
  ) async {
    final repo = await openEditor(tester);
    // Chip "fennel" in step 2's sentence… there is none, so use step 1's
    // existing fennel chip plus a new chip on the same line in step 2.
    await selectAndShowToolbar(tester, 1, 5, 10); // "slice"
    await tester.tap(find.text('To ingredient'));
    await tester.pumpAndSettle();
    await tester.tap(
      find.descendant(
        of: find.byType(PickerShell),
        matching: find.text('Fennel bulb'),
      ),
    );
    await tester.pumpAndSettle();
    await tapSave(tester);

    final ref = repo.saved.single.methodSteps![1].tokens
        .whereType<MethodRef>()
        .single;
    expect(ref.amountRule, ChipAmountRule.hideAmount);
  });

  testWidgets('To timer parses ONLY the selection, and writes the format', (
    tester,
  ) async {
    final repo = await openEditor(tester);
    // Retype step 2 so it prints a duration in words.
    final field = tester.widget<EditableText>(methodFields().at(1));
    field.controller.value = const TextEditingValue(
      text: 'Bake for 25 to 30 minutes.',
      selection: TextSelection.collapsed(offset: 26),
    );
    await tester.pumpAndSettle();

    await selectAndShowToolbar(tester, 1, 9, 25); // "25 to 30 minutes"
    await tester.tap(find.text('To timer'));
    await tester.pumpAndSettle();

    // Seeded from the selection alone.
    expect(find.text('25'), findsOneWidget);
    expect(find.text('30'), findsOneWidget);
    await tester.tap(find.text('Insert'));
    await tester.pumpAndSettle();

    // The words become formatTimerRange's own output, so the round-trip never
    // re-parses the string it printed.
    expect(methodFieldText(tester, 1), 'Bake for 25–30 min.');
    await tapSave(tester);
    final timer = repo.saved.single.methodSteps![1].tokens
        .whereType<MethodTimer>()
        .single;
    expect(timer.lowSeconds, 1500);
    expect(timer.highSeconds, 1800);
  });

  testWidgets('To timer over prose it cannot read opens the stepper empty', (
    tester,
  ) async {
    await openEditor(tester);
    await selectAndShowToolbar(tester, 1, 5, 10); // "slice"
    await tester.tap(find.text('To timer'));
    await tester.pumpAndSettle();

    expect(find.text('FROM'), findsOneWidget);
    // The default, not a guess pulled out of the words.
    expect(find.text('10'), findsOneWidget);
    expect(find.text('Add an end'), findsOneWidget);
  });
}
