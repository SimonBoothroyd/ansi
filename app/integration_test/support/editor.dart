/// Driving the recipe editor: opening it from the Library or a saved
/// recipe's page, adding lines through the 7.7 picker → quantity-sheet
/// chain, working a method step card (select → toolbar, tap-a-chip), saving,
/// and backing out of the pages a save leaves on the stack.
library;

import 'package:ansi/features/ingredients/presentation/quantity_unit_sheet.dart'
    show QuantityUnitEditor;
import 'package:ansi/features/recipes/presentation/component_quantity_sheet.dart'
    show ComponentQuantityEditor;
import 'package:ansi/features/recipes/presentation/method_span_controller.dart'
    show MethodSpanController;
import 'package:ansi/features/recipes/presentation/recipe_editor_view.dart'
    show RecipeEditorView;
import 'package:ansi/shared/picker_shell.dart' show PickerShell;
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:forui/forui.dart';

import 'drive.dart';

/// The +1 button of the labelled `_StepperRow` in the recipe editor.
Finder stepperPlus(String label) => find.descendant(
  of: find.ancestor(of: find.text(label), matching: find.byType(Row)).first,
  matching: find.byIcon(FLucideIcons.plus),
);

/// Opens the Library ▸ ＋ ▸ New recipe editor with [title] typed in.
Future<void> startRecipe(WidgetTester tester, String title) async {
  await tester.tap(
    find
        .descendant(
          of: find.byType(FHeaderAction),
          matching: find.byIcon(FLucideIcons.plus),
        )
        .first,
  );
  await tester.pumpAndSettle();
  await tester.tap(find.text('New recipe'));
  await pumpUntilFound(tester, find.text('New recipe'));
  await tester.pumpAndSettle();
  await tester.enterText(fieldIn(find.byType(RecipeEditorView)), title);
  await tester.pumpAndSettle();
}

/// Adds one vocab ingredient through the 7.7 two-step chain: picker v2
/// (search the synced vocab) → the quantity + unit-chip sheet (type the
/// quantity, optionally tap a measure/unit [chip], Done). Asserts the
/// picker actually searched the synced vocab.
Future<void> addIngredient(
  WidgetTester tester,
  String name,
  String qty, {
  String? chip,
}) async {
  await scrollTo(tester, find.text('Add ingredient'));
  await tester.tap(find.text('Add ingredient'));
  await tester.pumpAndSettle();
  // The picker sheet's search field is the last EditableText (overlay).
  await tester.enterText(find.byType(EditableText).last, name.toLowerCase());
  await tester.pumpAndSettle();
  await tester.tap(find.text(name).last);
  await tester.pumpAndSettle();
  // The quantity sheet: its qty field is the overlay's last EditableText.
  await tester.enterText(find.byType(EditableText).last, qty);
  await tester.pump();
  if (chip != null) {
    await tester.tap(find.text(chip).last);
    await tester.pump();
  }
  await tester.tap(find.text('Done'));
  await tester.pumpAndSettle();
}

/// [addIngredient]'s shape, on anchors rather than settles, and with the
/// search [query] stated apart from the row's rendered [name].
///
/// The picker matches each query token as a word PREFIX of a vocab row's
/// `match_text`, raw OR singularized — the seed singularizes ("Almonds" is
/// stored as `almond`), so both spellings find the row. Naming the query and
/// the rendered row separately is still what makes a miss fail loudly with
/// the query rather than staring at a spinner. These queries are all spelled
/// right on purpose: the typo tier runs only when nothing is, and a scenario
/// should exercise the ordinary path, not the band.
Future<void> addVocabLine(
  WidgetTester tester,
  String query,
  String name,
  String qty,
) async {
  await scrollTo(tester, find.text('Add ingredient'));
  await tester.tap(find.text('Add ingredient'));
  await pumpUntilFound(tester, find.text('Add an ingredient'));
  await tester.enterText(
    find.descendant(
      of: find.byType(PickerShell),
      matching: find.byType(EditableText),
    ),
    query,
  );
  try {
    await pumpUntilFound(
      tester,
      find.text(name),
      timeout: const Duration(seconds: 15),
    );
    // `TestFailure` is an Error, and catching this one is the point: it
    // carries only the finder, and the QUERY is what a reader needs.
    // ignore: avoid_catching_errors
  } on TestFailure {
    fail(
      'the picker never surfaced "$name" for the query "$query" — the '
      'seeded vocab row (or its match_text) moved. The search matches each '
      'query token as a word PREFIX of match_text, so a plural query for '
      'a singularized row finds nothing.',
    );
  }
  await tester.tap(find.text(name).last);
  await pumpUntilFound(tester, find.byType(QuantityUnitEditor));
  await tester.enterText(find.byType(EditableText).last, qty);
  await tester.pump();
  await tester.tap(find.text('Done'));
  await tester.pumpAndSettle();
}

/// Opens the editor's picker, searches [query], and takes the "Your recipes"
/// row for [title] — the one door D7 gives both kinds of line.
Future<void> addComponentLine(
  WidgetTester tester,
  String query,
  String title, {
  required String hint,
}) async {
  await scrollTo(tester, find.text('Add ingredient'));
  await tester.tap(find.text('Add ingredient'));
  await pumpUntilFound(tester, find.text('Add an ingredient'));
  await tester.enterText(
    find.descendant(
      of: find.byType(PickerShell),
      matching: find.byType(EditableText),
    ),
    query,
  );
  await pumpUntilFound(tester, find.text('YOUR RECIPES'));
  // The row's hint is the target's own yield. It reads off the library tree,
  // so a summary that dropped the yield columns says "no yield yet" here —
  // and hands the sheet below a target with no batch math to do.
  expect(find.text(hint), findsOneWidget, reason: "the row's yield hint");
  await tester.tap(find.text(title).last);
  await pumpUntilFound(tester, find.byType(ComponentQuantityEditor));
}

/// Opens a saved recipe's editor from its page: the header's ⋯ ▸ Edit.
Future<void> editRecipeFromPage(WidgetTester tester) async {
  await tester.tap(
    find.descendant(
      of: find.byType(FHeaderAction),
      matching: find.byIcon(FLucideIcons.ellipsis),
    ),
  );
  await tester.pumpAndSettle();
  await tester.tap(find.text('Edit'));
  await pumpUntilFound(tester, find.text('Edit recipe'));
}

/// Every method step card's editable, in card order — told apart from the
/// form's other fields by the controller that paints the chips.
Finder stepFields() => find.byWidgetPredicate(
  (w) => w is EditableText && w.controller is MethodSpanController,
);

/// The text the step card [field] is showing.
String stepText(WidgetTester tester, Finder field) =>
    tester.widget<EditableText>(field).controller.text;

/// A real tap inside the step card [field], on the character at [offset] —
/// the tap-to-edit door (0022 D2a): the field's own `onTap` fires after the
/// tap has placed the caret, so a tap inside a chip opens its sheet and a
/// tap on prose (or at the very end) only moves the caret and focuses.
Future<void> tapStepAt(WidgetTester tester, Finder field, int offset) async {
  final editable = tester.state<EditableTextState>(field).renderEditable;
  final caret = editable.getLocalRectForCaret(TextPosition(offset: offset));
  await tester.tapAt(editable.localToGlobal(caret.center));
  await tester.pumpAndSettle();
}

/// Selects `[start, end)` of the step card [field] and raises the platform
/// selection toolbar over it — the D2b writing door.
///
/// Focus is taken with a tap at the END of the text rather than the field's
/// centre, which can land inside a chip and open its sheet instead. The
/// selection itself is set through the controller: a drag-select is the one
/// gesture the test driver cannot make reliably on a device (it lands on a
/// word boundary of the platform's choosing), and the toolbar reads the
/// controller's selection, so this is the same range a real drag produces.
Future<void> selectInStep(
  WidgetTester tester,
  Finder field,
  int start,
  int end,
) async {
  await tapStepAt(tester, field, stepText(tester, field).length);
  tester.widget<EditableText>(field).controller.selection = TextSelection(
    baseOffset: start,
    extentOffset: end,
  );
  await tester.pumpAndSettle();
  tester.state<EditableTextState>(field).showToolbar();
  await tester.pumpAndSettle();
}

/// Takes [item] from the raised selection toolbar. On iOS the Cupertino
/// toolbar paginates; the editor's two items sit right after Copy so they
/// fit the first page on a phone, but page forward if they did not.
Future<void> tapToolbarItem(WidgetTester tester, String item) async {
  if (find.text(item).evaluate().isEmpty) {
    await tester.tap(find.text('▶'));
    await tester.pumpAndSettle();
  }
  await tester.tap(find.text(item));
  await tester.pumpAndSettle();
}

/// The recipe editor's Save, then the saved recipe's page.
///
/// The save REPLACES the editor rather than flattening the stack, so the
/// recipe lands with whatever the editor was opened from still under it —
/// which is why [backFromRecipe] below is a real pop now.
Future<void> saveRecipe(WidgetTester tester) async {
  await tester.tap(find.text('Save'));
  await pumpUntilFound(tester, find.text('OUR COOKBOOK'));
  await tester.pumpAndSettle();
}

/// Back out of a pushed page, one step: the header's back action pops to the
/// page underneath. (It used to be a fallback to the Library on a page a save
/// had landed on, because the save's `context.go` had flattened the stack.)
Future<void> backFromRecipe(WidgetTester tester) async {
  await tester.tap(find.byType(FHeaderAction).first);
  await tester.pumpAndSettle();
}

/// Backs out of pushed pages until the tab shell is under us again.
///
/// The predicate is "the nav bar is in the tree". It holds because pushed
/// pages are siblings of the shell and cover it (D2-a), and a route under an
/// opaque one is offstage — which the default finder skips. The moment a
/// pushed page sat INSIDE a branch instead, this would silently pass on the
/// first check and stop backing out at all.
///
/// Six steps, not four: a save now leaves the page it was opened from on the
/// stack, so the real depths are one or two greater than they used to be.
Future<void> backToShell(WidgetTester tester) async {
  for (var i = 0; i < 6; i++) {
    if (find.byIcon(FLucideIcons.library).evaluate().isNotEmpty) return;
    await backFromRecipe(tester);
  }
  fail('never got back to the tab shell — the nav bar never rendered');
}
