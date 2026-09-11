/// Tap-to-edit (0022 D2a · D4, design board frames c and d): a tap inside a
/// chip opens its sheet, a tap inside a timer opens the stepper, and a tap on
/// ordinary prose opens nothing at all.
library;

import 'package:ansi/features/books/data/book_providers.dart';
import 'package:ansi/features/ingredients/data/ingredient_providers.dart';
import 'package:ansi/features/recipes/data/recipe_providers.dart';
import 'package:ansi/features/recipes/domain/method_step.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:forui/forui.dart';

import '../../helpers/editor_harness.dart';
import '../../helpers/forui_semantics.dart';

/// Puts the caret at [offset] of the first step card and fires the field's
/// own `onTap` — which is what a real tap does, after the tap has set the
/// selection.
Future<void> tapAt(WidgetTester tester, int offset) async {
  final field = tester.widgetList<EditableText>(methodFields()).first;
  field.controller.selection = TextSelection.collapsed(offset: offset);
  final card = tester.widget<FTextField>(
    find
        .ancestor(of: methodFields().first, matching: find.byType(FTextField))
        .first,
  );
  card.onTap!();
  await tester.pumpAndSettle();
}

/// The centre of the caret at [offset] of the first step's sentence, in
/// global coordinates — so a tap can land inside a chip rather than at the
/// field's midpoint.
Offset caretCentre(WidgetTester tester, int offset) {
  final field = methodFields().first;
  final editable = tester.state<EditableTextState>(field).renderEditable;
  return tester.getTopLeft(field) +
      editable.getLocalRectForCaret(TextPosition(offset: offset)).center;
}

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

void main() {
  testWidgets('tapping ordinary prose opens nothing', (tester) async {
    await openEditor(tester);
    await tapAt(tester, 2); // inside "Halve"
    expect(find.text('POINTS AT'), findsNothing);
    expect(find.text('GOES IN AS'), findsNothing);
  });

  testWidgets('tapping a chip opens the chip sheet, seeded', (tester) async {
    await openEditor(tester);
    await tapAt(tester, 13); // inside "fennel bulb", [10, 21)

    expect(find.text('POINTS AT'), findsOneWidget);
    // Points at the line, with its live amount.
    expect(find.text('Fennel bulb · 1 piece'), findsOneWidget);
    expect(find.text('WORD'), findsOneWidget);
    expect(find.text('Show the amount here'), findsOneWidget);
    expect(find.text('Remove chip · keeps the word'), findsOneWidget);
  });

  testWidgets('the Word field renames the chip in place, keeping the ref', (
    tester,
  ) async {
    final repo = await openEditor(tester);
    await tapAt(tester, 13);

    await tester.enterText(find.byType(EditableText).last, 'fennel');
    await tester.pumpAndSettle();
    await tester.tap(find.byIcon(FLucideIcons.x).first);
    await tester.pumpAndSettle();

    expect(
      methodFieldText(tester, 0),
      'Halve the fennel and roast for 25–30 min.',
    );
    await tapSave(tester);
    final ref = repo.saved.single.methodSteps!.first.tokens
        .whereType<MethodRef>()
        .single;
    expect(ref.label, 'fennel');
    expect(ref.refs, ['l1']);
  });

  testWidgets('the switch writes the amount rule and nothing '
      'else', (tester) async {
    final repo = await openEditor(tester);
    await tapAt(tester, 13);

    await tester.tap(
      find.ancestor(
        of: find.text('Show the amount here'),
        matching: find.byType(FSwitch),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byIcon(FLucideIcons.x).first);
    await tester.pumpAndSettle();

    // The sentence is byte-identical; only the rule moved.
    expect(
      methodFieldText(tester, 0),
      'Halve the fennel bulb and roast for 25–30 min.',
    );
    await tapSave(tester);
    final ref = repo.saved.single.methodSteps!.first.tokens
        .whereType<MethodRef>()
        .single;
    expect(ref.amountRule, ChipAmountRule.hideAmount);
    expect(ref.label, 'fennel bulb');
  });

  testWidgets('Remove chip keeps the word', (tester) async {
    final repo = await openEditor(tester);
    await tapAt(tester, 13);

    await tester.tap(find.text('Remove chip · keeps the word'));
    await tester.pumpAndSettle();

    expect(
      methodFieldText(tester, 0),
      'Halve the fennel bulb and roast for 25–30 min.',
    );
    await tapSave(tester);
    final step = repo.saved.single.methodSteps!.first;
    expect(step.tokens.whereType<MethodRef>(), isEmpty);
    expect((step.tokens.first as MethodText).s, startsWith('Halve the fennel'));
  });

  testWidgets('tapping a timer opens the stepper, seeded', (tester) async {
    await openEditor(tester);
    // "25–30 min" sits at [36, 45) of the step's sentence.
    await tapAt(tester, 39);

    expect(find.text('FROM'), findsOneWidget);
    expect(find.text('GOES IN AS'), findsOneWidget);
    expect(find.text('Remove timer · keeps the words'), findsOneWidget);
    // Seeded from the token's own seconds — 1500..1800.
    expect(find.text('25'), findsOneWidget);
    expect(find.text('30'), findsOneWidget);
  });

  testWidgets('Remove timer keeps the words', (tester) async {
    final repo = await openEditor(tester);
    await tapAt(tester, 39);

    await tester.tap(find.text('Remove timer · keeps the words'));
    await tester.pumpAndSettle();

    expect(
      methodFieldText(tester, 0),
      'Halve the fennel bulb and roast for 25–30 min.',
    );
    await tapSave(tester);
    final step = repo.saved.single.methodSteps!.first;
    expect(step.tokens.whereType<MethodTimer>(), isEmpty);
    expect(step.tokens.whereType<MethodRef>(), hasLength(1));
  });

  testWidgets('dismissing a chip sheet leaves the sentence unfocused', (
    tester,
  ) async {
    await openEditor(tester);
    final node = tester.widget<EditableText>(methodFields().first).focusNode;

    // A REAL tap, landing inside the chip: the gesture asks for focus first
    // and calls onTap second, so the field is still coming into focus as the
    // sheet opens over it — which is how it was holding focus behind the
    // sheet and taking it back on the way out.
    await tester.tapAt(caretCentre(tester, 13));
    await tester.pumpAndSettle();
    expect(find.text('POINTS AT'), findsOneWidget);

    await tester.tap(find.byIcon(FLucideIcons.x).first);
    await tester.pumpAndSettle();

    expect(find.text('POINTS AT'), findsNothing, reason: 'the sheet closed');
    expect(node.hasFocus, isFalse);
    expect(find.text('READS AS'), findsNothing, reason: 'the card collapses');
  });
}
