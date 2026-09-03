/// Sim smoke — RECIPE EDITOR: new section → new recipe through the 7.7
/// pickers (picker v2 search → quantity + unit-chip sheet; a manual measure
/// authored in the manage state, the seeded clove chip on the line; shelf
/// life, method steps, filed under book + section) → breadcrumb + rendered
/// title + local-db rows; favorite via the header menu; then re-open and edit
/// the saved recipe and assert its children survive the server round-trip
/// (the connector jsonb + diffing-save fixes).
///
/// Local gate only (`make test-sim FILE=recipe_editor`), never CI. Needs the
/// local backend running (`make db-up`) and the usual `--dart-define`s.
library;

import 'dart:convert';

import 'package:ansi/features/ingredients/presentation/quantity_unit_sheet.dart'
    show QuantityUnitEditor, UnitChipRow;
import 'package:ansi/features/recipes/presentation/recipe_editor_view.dart'
    show RecipeEditorView;
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:forui/forui.dart';
import 'package:integration_test/integration_test.dart';

import 'support/drive.dart';
import 'support/editor.dart';
import 'support/stack.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  late SmokeStack stack;

  setUpAll(() async => stack = await SmokeStack.start());
  tearDownAll(() => stack.dispose());

  testWidgets('recipe editor: files a new recipe under a new section', (
    tester,
  ) async {
    ignoreForuiSemanticsAssertion();
    final db = stack.db;
    await stack.openLibrary(tester);

    await tester.tap(find.textContaining('new section'));
    await tester.pumpAndSettle();
    await tester.enterText(fieldIn(find.byType(FDialog)), 'Weeknight');
    await tester.tap(find.text('Add'));
    await tester.pumpAndSettle();
    expect(find.text('Weeknight'), findsOneWidget);

    // The app-bar + (an FHeaderAction); the "+ new section" affordance now
    // carries the same icon, so scope to the header action.
    await tester.tap(
      find.descendant(
        of: find.byType(FHeaderAction),
        matching: find.byIcon(FLucideIcons.plus),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('New recipe'));
    await tester.pumpAndSettle();

    await tester.enterText(
      fieldIn(find.byType(RecipeEditorView)),
      'Chicken Curry',
    );
    await tester.pump();

    // Shelf life: keeps 2 days in the fridge (the same recipe the week file
    // seeds, whose far Saturday meal splits into its own cook session).
    await tester.tap(stepperPlus('Keeps in the fridge'));
    await tester.pump();
    await tester.tap(stepperPlus('Keeps in the fridge'));
    await tester.pumpAndSettle();
    expect(find.text('2 days'), findsOneWidget);

    // File under Our Cookbook · Weeknight (the section select starts on the
    // Unsectioned bucket).
    await tester.tap(find.text('Unsectioned'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Weeknight').last);
    await tester.pumpAndSettle();

    // Garlic through the 7.7 chain, quantified in its synced measure: the
    // chip row offers the vocab measures cloned at onboarding — but first,
    // author a manual measure through the sheet's manage state (the 7.7
    // measure editor) and prove it lands with source 'manual'.
    await scrollTo(tester, find.text('Add ingredient'));
    await tester.tap(find.text('Add ingredient'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(EditableText).last, 'garlic');
    await tester.pumpAndSettle();
    await tester.tap(find.text('Garlic').last);
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(EditableText).last, '3');
    await tester.pump();
    // Manage measures: add "big clove = 5 g" (saved as yours), which lands
    // selected as the line's chip. The manage chip (a plus ICON — the glyph
    // rule bans raw ＋ text) trails the row, so scroll the (horizontal,
    // lazy) chip row until it builds.
    final manageChip = find.descendant(
      of: find.byType(UnitChipRow),
      matching: find.byIcon(FLucideIcons.plus),
    );
    await tester.dragUntilVisible(
      manageChip,
      find.descendant(
        of: find.byType(UnitChipRow),
        matching: find.byType(Scrollable),
      ),
      const Offset(-80, 0),
    );
    await tester.pumpAndSettle();
    await tester.tap(manageChip);
    await tester.pumpAndSettle();
    // The manage state holds the add form (label + amount) and the density
    // entry's field (7.8). Scope everything to the sheet: the editor behind
    // it still holds its own fields and Save button — within the sheet the
    // add form's fields lead and its Save comes before the density one.
    final sheetFields = find.descendant(
      of: find.byType(QuantityUnitEditor),
      matching: find.byType(EditableText),
    );
    await tester.enterText(sheetFields.at(0), 'big clove');
    await tester.enterText(sheetFields.at(1), '5');
    await tester.pump();
    await tester.tap(
      find
          .descendant(
            of: find.byType(QuantityUnitEditor),
            matching: find.text('Save'),
          )
          .first,
    );
    await tester.pumpAndSettle();
    final manualMeasure = await db.getOptional(
      'SELECT source, basis_amount FROM ingredient_measure '
      "WHERE label = 'big clove' AND deleted_at IS NULL",
    );
    expect(manualMeasure, isNotNull, reason: 'the manual measure synced row');
    expect(manualMeasure!['source'], 'manual');
    expect(manualMeasure['basis_amount'], 5);
    // …then pick the seeded "clove" chip for the recipe's own line.
    await tester.tap(find.text('clove').last);
    await tester.pump();
    await tester.tap(find.text('Done'));
    await tester.pumpAndSettle();

    await addIngredient(tester, 'Onion', '1');

    // Two method steps — `recipe.steps` is a jsonb column, so these must
    // survive the upload round-trip as a real array (the sweep's connector
    // fix; the old double-encoding crashed the recipe view within a second).
    // The v2 editor (plan 0022) is one card per step: a fresh recipe has no
    // step field until "Add a step" makes one, and each card is its own field.
    await scrollTo(tester, find.text('METHOD'));
    for (final step in ['Brown the aromatics.', 'Simmer until thick.']) {
      await scrollTo(tester, find.text('Add a step'), delta: -150);
      await tester.tap(find.text('Add a step'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(EditableText).last, step);
      await tester.pump();
    }

    await scrollTo(tester, find.text('Save'), delta: -150);
    await tester.tap(find.text('Save'));
    await pumpUntilFound(tester, find.text('OUR COOKBOOK · WEEKNIGHT'));
    expect(find.text('Chicken Curry'), findsOneWidget); // the rendered title

    // The write reached the local database, fully filed.
    final recipe = await db.get(
      'SELECT id, keeps_for_days, book_id, section_id FROM recipe '
      "WHERE title = 'Chicken Curry' AND deleted_at IS NULL",
    );
    expect(recipe['keeps_for_days'], 2);
    expect(recipe['book_id'], isNotNull);
    expect(recipe['section_id'], isNotNull);
    final items = await db.getAll(
      'SELECT li.quantity, li.unit, li.measure_id FROM recipe_line_item li '
      'JOIN ingredient_group g ON g.id = li.group_id '
      'WHERE g.recipe_id = ? AND li.deleted_at IS NULL '
      'ORDER BY li.sort_order',
      [recipe['id']],
    );
    expect(items, hasLength(2));
    expect(items.first['quantity'], 3);
    // The Garlic line persisted its measure FK, with the honest count unit as
    // the stored fallback ("3 clove" degrades to "3 piece", never invented
    // grams — step 7.6).
    expect(items.first['measure_id'], isNotNull);
    expect(items.first['unit'], 'piece');
    expect(items.last['quantity'], 1);
    expect(items.last['measure_id'], isNull);

    // After the server round-trip the view still stands and the steps are
    // still a real JSON array (not a double-encoded string).
    await stack.waitForSyncRoundTrip(tester);
    expect(find.text('Chicken Curry'), findsOneWidget);
    final steps =
        jsonDecode(
              (await db.get('SELECT steps FROM recipe WHERE id = ?', [
                    recipe['id'],
                  ]))['steps']!
                  as String,
            )
            as List<dynamic>;
    // The v2 editor writes the tokenized shape for every recipe — a chip-less
    // step is one text token — so assert the prose survived inside it rather
    // than pinning the token keys here (the domain tests own the shape).
    expect(steps, hasLength(2));
    expect(jsonEncode(steps.first), contains('Brown the aromatics.'));
    expect(jsonEncode(steps.last), contains('Simmer until thick.'));
    await tester.tap(find.text('Method'));
    await tester.pumpAndSettle();
    // Rendered through MethodStepText (rich text), so plain find.text misses.
    expect(
      find.textContaining('Brown the aromatics.', findRichText: true),
      findsOneWidget,
    );
    expect(
      find.textContaining('Simmer until thick.', findRichText: true),
      findsOneWidget,
    );

    // Favorite the recipe from its header menu (the 7.7 Favorites
    // affordance) — the flag the week picker's Favorites tab reads.
    await tester.tap(
      find.descendant(
        of: find.byType(FHeaderAction),
        matching: find.byIcon(FLucideIcons.ellipsis),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Favorite'));
    await tester.pumpAndSettle();
    await waitForDb(tester, () async {
      final row = await db.get('SELECT favorite FROM recipe WHERE id = ?', [
        recipe['id'],
      ]);
      return row['favorite'] == 1;
    }, 'the favorite flag to persist');
    // Dismiss the still-open popover with an outside tap.
    await tester.tapAt(const Offset(40, 300));
    await tester.pumpAndSettle();

    // Re-open and edit the saved recipe (tweak Garlic 3 → 4). The diffing
    // `saveRecipe` must leave every kept child live — the old delete-reinsert
    // tombstoned the children server-side on any edit.
    await tester.tap(
      find.descendant(
        of: find.byType(FHeaderAction),
        matching: find.byIcon(FLucideIcons.ellipsis),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Edit'));
    await pumpUntilFound(tester, find.text('Edit recipe'));
    await scrollTo(tester, find.text('Garlic'));
    // The line's quantity control ("3 clove") re-opens the quantity sheet.
    await tester.tap(find.text('3 clove'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(EditableText).last, '4');
    await tester.pump();
    await tester.tap(find.text('Done'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Save'));
    await pumpUntilFound(tester, find.text('OUR COOKBOOK · WEEKNIGHT'));

    // Ingredients survive the edit's server round-trip: rendered and live in
    // the local db, with the one tweaked quantity. (The Ingredients tab first:
    // the save replaces the editor with a FRESH recipe page, so the in-page
    // tab starts at Ingredients rather than carrying the Method tab chosen
    // above — the tap is a no-op either way and pins where we are.)
    await stack.waitForSyncRoundTrip(tester);
    await tester.tap(find.text('Ingredients'));
    await tester.pumpAndSettle();
    expect(find.text('Garlic'), findsOneWidget);
    expect(find.text('Onion'), findsOneWidget);
    final editedItems = await db.getAll(
      'SELECT li.quantity FROM recipe_line_item li '
      'JOIN ingredient_group g ON g.id = li.group_id '
      'WHERE g.recipe_id = ? AND li.deleted_at IS NULL '
      'ORDER BY li.sort_order',
      [recipe['id']],
    );
    expect(editedItems.map((r) => r['quantity']).toList(), [4, 1]);
  });
}
