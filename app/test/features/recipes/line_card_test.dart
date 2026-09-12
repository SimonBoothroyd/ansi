/// The recipe editor's line as the review's expanding card: one gesture opens
/// it, and every fact the line carries has exactly one door inside.
///
/// The gap this closes, in the owner's words: *"How do I set a note on an
/// ingredient through the ingredient editor? It just opens the ingredient
/// picker."* The note had no door at all — the column was live, the import
/// review wrote it, and the editor's notifier had no setter.
library;

import 'package:ansi/core/units/units.dart';
import 'package:ansi/features/books/data/book_providers.dart';
import 'package:ansi/features/ingredients/data/ingredient_providers.dart';
import 'package:ansi/features/ingredients/presentation/quantity_unit_sheet.dart';
import 'package:ansi/features/recipes/data/recipe_providers.dart';
import 'package:ansi/features/recipes/domain/recipe.dart';
import 'package:ansi/features/recipes/presentation/ingredient_line.dart';
import 'package:ansi/features/recipes/presentation/line_card.dart';
import 'package:ansi/shared/reorder_grip.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/editor_harness.dart';
import '../../helpers/fake_measure_repository.dart';
import '../../helpers/forui_semantics.dart';

/// Two plain lines, one of them already carrying a note.
const _recipe = Recipe(
  id: '1',
  title: 'Weeknight Curry',
  servingsBase: 2,
  groups: [
    IngredientGroup(
      id: 'g1',
      items: [
        LineItem(
          id: 'l1',
          ingredientId: 'ing-garlic',
          ingredientName: 'Garlic',
          unit: pieces,
          quantity: 2,
          note: 'peeled and crushed',
        ),
        LineItem(
          id: 'l2',
          ingredientId: 'ing-cumin',
          ingredientName: 'Ground cumin',
          unit: tsp,
          quantity: 1,
        ),
      ],
    ),
  ],
);

Future<FakeRecipeRepo> openEditor(WidgetTester tester) async {
  filterForuiSemanticsAssertions();
  tallSurface(tester);
  final repo = FakeRecipeRepo(_recipe);
  await tester.pumpWidget(
    hostEditor('1', [
      recipeRepositoryProvider.overrideWithValue(repo),
      ingredientRepositoryProvider.overrideWithValue(
        const FakeIngredientRepo(),
      ),
      // The amount sheet reads an ingredient's measures before it can draw.
      measureRepositoryProvider.overrideWithValue(FakeMeasureRepo()),
      bookRepositoryProvider.overrideWithValue(FakeBookRepo()),
    ]),
  );
  await tester.pumpAndSettle();
  return repo;
}

/// The card's notes field — the only text field on an open line.
Finder notesField() =>
    find.widgetWithText(TextField, 'e.g. finely chopped, to serve');

void main() {
  testWidgets('the row prints the note in the one grammar, and opening it '
      'shows every fact the line carries', (tester) async {
    await openEditor(tester);

    // The row, at rest: the page's own line, the note as the name's modifier.
    expect(
      find.text('Garlic  ·  peeled and crushed', findRichText: true),
      findsOneWidget,
    );
    expect(find.text('NOTES'), findsNothing);
    expect(find.text('AMOUNT'), findsNothing);

    // One gesture: anywhere on the row.
    await openLine(tester, 'Garlic');

    expect(changeIdentity(), findsOneWidget);
    expect(removeLine(), findsOneWidget);
    expect(find.text('AMOUNT'), findsOneWidget);
    expect(find.byType(LineCardAmountChip), findsOneWidget);
    expect(find.text('NOTES'), findsOneWidget);
    expect(find.text('optional'), findsOneWidget);
    // The note is the field's now, not a second copy after the name.
    expect(
      find.text('Garlic  ·  peeled and crushed', findRichText: true),
      findsNothing,
    );
  });

  testWidgets('the notes field writes the note onto the line, and Save stores '
      'it', (tester) async {
    final repo = await openEditor(tester);
    await openLine(tester, 'Ground cumin');

    await tester.enterText(notesField(), '  toasted  ');
    await tester.pumpAndSettle();
    await tapSave(tester);

    final lines = repo.saved.single.groups.single.items;
    // Trimmed on the way in — a note is a word, not the spacing around it.
    expect(lines[1].note, 'toasted');
    // And the line it belongs to is the one that was edited.
    expect(lines[0].note, 'peeled and crushed');
  });

  testWidgets('blank clears the note — the field and the absence of a note '
      'are one gesture', (tester) async {
    final repo = await openEditor(tester);
    await openLine(tester, 'Garlic');

    await tester.enterText(notesField(), '');
    await tester.pumpAndSettle();
    await tapSave(tester);

    expect(repo.saved.single.groups.single.items.first.note, isNull);
  });

  testWidgets('a note edit relabels nothing: it says what the line is LIKE, '
      'not what it IS', (tester) async {
    await openEditor(tester);
    await openLine(tester, 'Garlic');

    await tester.enterText(notesField(), 'finely chopped');
    await tester.pumpAndSettle();

    // The substitution notice belongs to an identity change alone.
    expect(find.textContaining('mentioned'), findsNothing);
    expect(find.text('Garlic'), findsWidgets);
  });

  testWidgets('the card’s flag row is what marks a line optional', (
    tester,
  ) async {
    final repo = await openEditor(tester);
    await openLine(tester, 'Garlic');

    await tester.tap(find.text('optional'));
    await tester.pumpAndSettle();

    // Closed again, the row states the fact the card just recorded — the tag
    // is a statement there, and the control is here.
    await tester.tap(closeLine());
    await tester.pumpAndSettle();
    expect(find.byType(OptionalTag), findsOneWidget);

    await tapSave(tester);
    expect(repo.saved.single.groups.single.items.first.optional, isTrue);
  });

  testWidgets('one fact, one door: the amount sheet no longer carries the '
      'Optional switch', (tester) async {
    await openEditor(tester);
    await openLine(tester, 'Garlic');

    await tester.tap(find.byType(LineCardAmountChip));
    await tester.pumpAndSettle();

    // The sheet is open on the line's amount…
    expect(find.byType(QuantityUnitEditor), findsOneWidget);
    expect(find.text('Done'), findsOneWidget);
    // …and the flag is not its business any more.
    expect(find.text('Optional'), findsNothing);
  });

  testWidgets('several cards stand open at once, and each survives a '
      'keystroke in another', (tester) async {
    await openEditor(tester);
    await openLine(tester, 'Garlic');
    await openLine(tester, 'Ground cumin');

    expect(find.text('NOTES'), findsNWidgets(2));
    await tester.enterText(notesField().last, 'toasted');
    await tester.pumpAndSettle();
    expect(find.text('NOTES'), findsNWidgets(2));
  });

  testWidgets('starting a drag closes every open card — what crosses the list '
      'is a row like every other row', (tester) async {
    await openEditor(tester);
    await openLine(tester, 'Garlic');
    expect(find.text('NOTES'), findsOneWidget);

    // Take hold of another row's grip and move it.
    final grip = tester.getCenter(find.byType(DragGrip).last);
    final drag = await tester.startGesture(grip);
    await tester.pump(const Duration(milliseconds: 200));
    await drag.moveTo(Offset(grip.dx, grip.dy - 60));
    await tester.pump();

    expect(find.text('NOTES'), findsNothing);

    await drag.up();
    await tester.pumpAndSettle();
  });

  testWidgets('dragging the list dismisses the keyboard — the same rule the '
      'review already paid for', (tester) async {
    await openEditor(tester);
    expect(
      tester
          .widget<CustomScrollView>(find.byType(CustomScrollView).first)
          .keyboardDismissBehavior,
      ScrollViewKeyboardDismissBehavior.onDrag,
    );
  });
}
