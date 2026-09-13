/// Sim smoke — RECIPE EDITOR, in two scenarios.
///
/// The first authors a recipe end to end: new section → new recipe through the
/// picker → quantity + unit-chip sheet (with a manual measure authored in the
/// manage state and the seeded clove chip on the line) → shelf life, method
/// steps, filed under book + section → the breadcrumb, the rendered title and
/// the local-db rows. Then favorite from the header menu, and re-open and edit
/// the saved recipe, asserting its children survive the server round trip.
///
/// The second drives the editor legs that are otherwise host-tested over fakes
/// only, on a recipe SEEDED through the repository: the method step card's
/// select → **To ingredient** / **To timer** toolbar and tap-a-chip → the chip
/// sheet's rename; the line card's **optional** toggle; and create-new
/// from inside the editor — the picker footer pushes the ingredient form over
/// the picker, and back on it the quantity sheet opens on the units that form
/// set. Each leg is asserted in the local db after the sync round trip.
///
/// Local gate only (`make test-sim FILE=recipe_editor`), never CI. Needs the
/// local backend running (`make db-up`) and the usual `--dart-define`s.
library;

import 'dart:convert';

import 'package:ansi/core/units/units.dart' show pieces;
import 'package:ansi/features/ingredients/domain/normalize.dart'
    show normalizeMatchText;
import 'package:ansi/features/ingredients/presentation/density_entry.dart'
    show AnsiModeChip;
import 'package:ansi/features/ingredients/presentation/ingredient_detail_view.dart'
    show IngredientDetailView, kFormSaveKey;
import 'package:ansi/features/ingredients/presentation/quantity_unit_sheet.dart'
    show QuantityUnitEditor;
import 'package:ansi/features/ingredients/presentation/unit_chips.dart'
    show UnitChipRow;
import 'package:ansi/features/recipes/data/recipe_repository_impl.dart';
import 'package:ansi/features/recipes/domain/recipe.dart';
import 'package:ansi/features/recipes/presentation/ingredient_line.dart'
    show OptionalTag;
import 'package:ansi/features/recipes/presentation/line_card.dart'
    show LineCardAmountChip;
import 'package:ansi/features/recipes/presentation/recipe_editor_view.dart'
    show RecipeEditorView;
import 'package:ansi/shared/method_step_text.dart' show MethodChip;
import 'package:ansi/shared/picker_shell.dart' show PickerShell;
import 'package:ansi/shared/unit_chip.dart' show UnitChip;
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:forui/forui.dart';
import 'package:integration_test/integration_test.dart';
import 'package:powersync/powersync.dart' hide Column;
import 'package:uuid/uuid.dart';

import 'support/drive.dart';
import 'support/editor.dart';
import 'support/library.dart';
import 'support/stack.dart';

const _uuid = Uuid();

/// The step the chip scenario works: one ingredient word to chip, one
/// duration in words for the timer door to read.
const _step = 'Crush the garlic and simmer for 10 minutes.';

/// Writes the recipe the chip scenario edits — Garlic 3 clove, Onion 1, one
/// plain-text step — through the real repository, filed under the
/// household's default book. Returns the ids the assertions need.
Future<({String recipeId, String garlicLineId, String onionLineId})>
_seedChipCurry(PowerSyncDatabase db, {required String householdId}) async {
  final garlic = await db.get(
    "SELECT id FROM ingredient WHERE canonical_name = 'Garlic' "
    'AND deleted_at IS NULL',
  );
  final onion = await db.get(
    "SELECT id FROM ingredient WHERE canonical_name = 'Onion' "
    'AND deleted_at IS NULL',
  );
  final clove = await db.getOptional(
    'SELECT id FROM ingredient_measure WHERE ingredient_id = ? '
    "AND label = 'clove' AND deleted_at IS NULL",
    [garlic['id']],
  );
  expect(clove, isNotNull, reason: "Garlic's seeded 'clove' measure");
  final book = await db.get(
    'SELECT id FROM book WHERE deleted_at IS NULL '
    'ORDER BY sort_order, created_at LIMIT 1',
  );
  final ids = (
    recipeId: _uuid.v4(),
    garlicLineId: _uuid.v4(),
    onionLineId: _uuid.v4(),
  );
  await SqliteRecipeRepository(db, householdId: householdId).saveRecipe(
    Recipe(
      id: ids.recipeId,
      title: 'Chip Curry',
      servingsBase: 2,
      bookId: book['id'] as String,
      steps: const [_step],
      groups: [
        IngredientGroup(
          id: _uuid.v4(),
          items: [
            LineItem(
              id: ids.garlicLineId,
              ingredientId: garlic['id'] as String,
              ingredientName: 'Garlic',
              unit: pieces,
              quantity: 3,
              measureId: clove!['id'] as String,
            ),
            LineItem(
              id: ids.onionLineId,
              ingredientId: onion['id'] as String,
              ingredientName: 'Onion',
              unit: pieces,
              quantity: 1,
            ),
          ],
        ),
      ],
    ),
  );
  return ids;
}

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

    // 0028 E3: the section is made from the book's own `⋯` — the dashed row
    // that used to sit in the card was a second door to this same item.
    await openBookMenu(tester, 'Our Cookbook');
    await tester.tap(find.text('New section'));
    await tester.pumpAndSettle();
    await tester.enterText(fieldIn(find.byType(FDialog)), 'Weeknight');
    await tester.tap(find.text('Add'));
    await tester.pumpAndSettle();
    expect(find.text('Weeknight'), findsOneWidget);

    // 0028 E2: and the recipe is made from that section's own `＋`, which is
    // the whole point — the door knows the shelf, so nothing below has to ask.
    await tester.tap(sectionAdd('Weeknight'));
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

    // FILE UNDER is already Our Cookbook · Weeknight: the `＋` carried
    // `?book=&section=` (0028 E3), and E9 states it as one line instead of
    // asking. What used to be two taps on a form is a fact the screen opened
    // with — assert it rather than perform it.
    expect(find.text('OUR COOKBOOK · WEEKNIGHT'), findsOneWidget);

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
    // …then pick the seeded "clove" chip for the recipe's own line. The chip
    // row scrolls sideways and the measures lead it, so bring the chip into
    // view rather than tapping wherever it happens to sit.
    final cloveChip = find.widgetWithText(UnitChip, 'clove');
    await tester.ensureVisible(cloveChip);
    await tester.pump();
    await tester.tap(cloveChip);
    await tester.pump();
    await tester.tap(find.text('Done'));
    await tester.pumpAndSettle();

    await addIngredient(tester, 'Onion', '1');

    // Two method steps — `recipe.steps` is a jsonb column, so these must
    // survive the upload round-trip as a real array (the sweep's connector
    // fix; the old double-encoding crashed the recipe view within a second).
    // The v2 editor is one card per step: a fresh recipe has no
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
      'SELECT li.quantity, li.unit, li.measure_id, li.ingredient_id '
      'FROM recipe_line_item li '
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
    // The Onion line was added WITHOUT touching a chip, so it lands on the
    // row's WHOLE MEASURE: `onion, medium` weighs what the row says one onion
    // weighs, which makes it this household's word for one (ADR-0016), and the
    // sheet a caller opens with no choice named opens on it. Done therefore
    // writes the measure's FK, exactly as if the chip had been tapped.
    //
    // The stored `unit` is still `piece` — a measure line always carries the
    // honest count fallback beside its FK, so a vanished measure degrades to a
    // count and never to invented grams (the Garlic line above, step 7.6) —
    // so `measure_id` is the assertion that says which word the line got.
    expect(items.last['unit'], 'piece');
    expect(items.last['measure_id'], isNotNull);
    final onionMeasure = await db.get(
      'SELECT label, basis_amount FROM ingredient_measure WHERE id = ?',
      [items.last['measure_id']],
    );
    expect(onionMeasure['label'], 'onion, medium');
    final onion = await db.get(
      'SELECT piece_basis_amount, piece_source FROM ingredient WHERE id = ?',
      [items.last['ingredient_id']],
    );
    expect(onion['piece_basis_amount'], greaterThan(0));
    // Nothing is stored to say which measure is the row's word: the reading is
    // these two numbers agreeing (ADR-0016 §1, `wholeMeasureOf`).
    expect(
      (onionMeasure['basis_amount']! as num).toDouble(),
      (onion['piece_basis_amount']! as num).toDouble(),
    );
    expect(onion['piece_source'], 'borrowed from onion, medium');

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
    await editRecipeFromPage(tester);
    await scrollTo(tester, find.text('Garlic'));
    // The line's amount ("3 clove") is what the row prints — but only once the
    // MEASURE row has synced back. Until it lands, the cell honestly reads
    // "3 piece · measure pending sync" (the editor's own `_label` branch), so
    // tapping the first frame after re-opening raced the sync and found
    // nothing. This is the flake the tracker recorded at this exact finder;
    // the cause is a race in the harness, not in the watch.
    await pumpUntilFound(tester, find.text('3 clove'));
    // One gesture opens the line's card; the AMOUNT chip inside it opens the
    // quantity sheet. The chip prints the same words as the row it replaced,
    // so it is found by TYPE — a text finder would answer for either, and
    // which one it meant would depend on the order they were built in.
    await tester.tap(find.text('3 clove'));
    await tester.pumpAndSettle();
    await tester.tap(find.byType(LineCardAmountChip));
    await pumpUntilFound(tester, find.byType(QuantityUnitEditor));
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

  testWidgets(
    'recipe editor: method chips, the optional switch, and create-new from '
    'inside the editor — on the real stack',
    (tester) async {
      ignoreForuiSemanticsAssertion();
      final db = stack.db;
      await stack.openLibrary(tester);
      final seeded = await _seedChipCurry(db, householdId: stack.householdId);
      await stack.waitForSyncRoundTrip(tester);

      await scrollTo(tester, find.text('Chip Curry'));
      await tester.tap(find.text('Chip Curry'));
      await pumpUntilFound(tester, find.text('OUR COOKBOOK'));

      // ----------------------------------------------------------------------
      // Method chips (0022 D2a/D2b) — select → To ingredient, tap → rename,
      // select → To timer; then the refs survive the round trip.
      // ----------------------------------------------------------------------
      await editRecipeFromPage(tester);
      await scrollTo(tester, find.text('Step 1'));
      final field = stepFields().first;
      expect(stepText(tester, field), _step);

      // "garlic" → a chip pointing at the Garlic line. The picker arrives
      // pre-matched over this recipe's own lines, so it is one more tap.
      final garlic = _step.indexOf('garlic');
      await selectInStep(tester, field, garlic, garlic + 'garlic'.length);
      await tapToolbarItem(tester, 'To ingredient');
      await pumpUntilFound(tester, find.text('Chip as “Garlic”'));
      await tester.tap(find.text('Chip as “Garlic”'));
      await tester.pumpAndSettle();
      expect(
        stepText(tester, field),
        _step,
        reason: 'To ingredient annotates the words; it changes no text',
      );

      // A tap inside the chip opens its sheet, seeded with the line and its
      // live amount; the Word field renames the chip in place.
      await tapStepAt(tester, field, garlic + 2);
      await pumpUntilFound(tester, find.text('POINTS AT'));
      expect(find.textContaining('Garlic · 3'), findsOneWidget);
      await tester.enterText(find.byType(EditableText).last, 'garlic cloves');
      await tester.pumpAndSettle();
      await tester.tap(find.byIcon(FLucideIcons.x).last);
      await tester.pumpAndSettle();
      const renamed = 'Crush the garlic cloves and simmer for 10 minutes.';
      expect(stepText(tester, field), renamed);

      // "10 minutes" → the timer stepper, seeded from the selection alone,
      // and the words become formatTimerRange's own output.
      final minutes = renamed.indexOf('10 minutes');
      await selectInStep(tester, field, minutes, minutes + '10 minutes'.length);
      await tapToolbarItem(tester, 'To timer');
      await pumpUntilFound(tester, find.text('GOES IN AS'));
      expect(
        find.text('Crush the garlic cloves and simmer for 10 min.'),
        findsOneWidget,
        reason: 'the stepper is seeded from the selected words',
      );
      await tester.tap(find.text('Insert'));
      await tester.pumpAndSettle();
      const timed = 'Crush the garlic cloves and simmer for 10 min.';
      expect(stepText(tester, field), timed);

      // The focused card's "Reads as" preview is the shipped renderer: both
      // chips render, the ingredient one with the line's live amount.
      await tapStepAt(tester, field, timed.length);
      await pumpUntilFound(tester, find.text('READS AS'));
      expect(find.widgetWithText(MethodChip, 'garlic cloves'), findsOneWidget);
      expect(find.widgetWithText(MethodChip, '10 min'), findsOneWidget);

      await scrollTo(tester, find.text('Save'), delta: -150);
      await saveRecipe(tester);
      await stack.waitForSyncRoundTrip(tester);
      final steps =
          jsonDecode(
                (await db.get('SELECT steps FROM recipe WHERE id = ?', [
                      seeded.recipeId,
                    ]))['steps']!
                    as String,
              )
              as List<dynamic>;
      expect(steps, hasLength(1));
      final tokens = (steps.single as Map)['tokens'] as List<dynamic>;
      final byType = {
        for (final t in tokens.cast<Map<String, dynamic>>()) t['t']: t,
      };
      final ref = byType['ref']!;
      expect(ref['refs'], [seeded.garlicLineId]);
      expect(ref['label'], 'garlic cloves');
      final timer = byType['timer']!;
      // The stored keys are the frozen snake_case contract, not the Dart names.
      expect(timer['low_seconds'], 600);
      expect(timer['high_seconds'], 600);
      // …and the recipe page renders them.
      await tester.tap(find.text('Method'));
      await tester.pumpAndSettle();
      expect(find.widgetWithText(MethodChip, 'garlic cloves'), findsOneWidget);
      expect(find.widgetWithText(MethodChip, '10 min'), findsOneWidget);

      // ----------------------------------------------------------------------
      // Optional — the flag row of the line's own card, which is the one door
      // that sets it on a recipe line; the flag lands on the row and the page
      // tags the line.
      // ----------------------------------------------------------------------
      await editRecipeFromPage(tester);
      // The row is the door, anywhere on it — and its identity is rich text
      // (name, note, tags in one run), so it is found by what it contains
      // rather than by an exact string.
      final onionRow = find.textContaining('Onion');
      await scrollTo(tester, onionRow);
      expect(onionRow, findsOneWidget, reason: 'the Onion line');
      await tester.tap(onionRow);
      await tester.pumpAndSettle();
      // The card's toggle, not the amount sheet's switch: the editor stopped
      // passing `initialOptional`, so that switch is gone from this screen.
      expect(find.text('optional'), findsOneWidget);
      await tester.tap(find.text('optional'));
      await tester.pumpAndSettle();
      await scrollTo(tester, find.text('Save'), delta: -150);
      await saveRecipe(tester);
      await stack.waitForSyncRoundTrip(tester);
      final onion = await db.get(
        'SELECT optional FROM recipe_line_item WHERE id = ?',
        [seeded.onionLineId],
      );
      expect(onion['optional'], 1);
      await tester.tap(find.text('Ingredients'));
      await tester.pumpAndSettle();
      expect(find.byType(OptionalTag), findsOneWidget);

      // ----------------------------------------------------------------------
      // Create-new from inside the editor: the one add chain —
      // picker footer → the form OVER the picker → its one Save → the
      // quantity sheet on the units the form set.
      // ----------------------------------------------------------------------
      await editRecipeFromPage(tester);
      await scrollTo(tester, find.text('Add ingredient'));
      await tester.tap(find.text('Add ingredient'));
      await pumpUntilFound(tester, find.text('Add an ingredient'));
      // A name nothing in the vocab (or USDA's trigram floor of 0.5) can
      // match, so the row is born bare and stays `manual`.
      const name = 'Zorblat';
      await tester.enterText(
        find.descendant(
          of: find.byType(PickerShell),
          matching: find.byType(EditableText),
        ),
        name,
      );
      await pumpUntilFound(tester, find.textContaining('add "$name"'));
      await tester.tap(find.textContaining('add "$name"'));
      // ONE push: the form IS the create surface, and it lands over the
      // still-open picker with the typed name already in it.
      await pumpUntilFound(tester, find.text('CANONICAL NAME'));
      expect(find.byType(IngredientDetailView), findsOneWidget);
      expect(
        await db.getOptional(
          'SELECT id FROM ingredient WHERE canonical_name = ? '
          'AND deleted_at IS NULL',
          [name],
        ),
        isNull,
        reason:
            'the form writes nothing until its Save — back out and '
            'nothing exists',
      );

      // Set the default unit to kg — which also admits it — and Save the
      // form; the picker is awaiting the form's pop underneath.
      await scrollTo(tester, find.text('CATEGORY'));
      final kg = find.descendant(
        of: find.byKey(const ValueKey('default-unit-row')),
        matching: find.widgetWithText(AnsiModeChip, 'kg'),
      );
      await tester.ensureVisible(kg);
      await tester.pumpAndSettle();
      await tester.tap(kg);
      await tester.pump();
      // A new row saves complete or not at all, so give it a label first.
      await completeNewIngredientForm(tester);
      // The form's own Save, by key: the density entry and the measures
      // editor each carry their own small green Save, and the dock is pinned
      // so it needs no scrolling to reach.
      await tester.tap(find.byKey(kFormSaveKey));
      await tester.pumpAndSettle();
      await waitForDb(
        tester,
        () async =>
            (await db.getOptional(
              'SELECT default_unit FROM ingredient '
              'WHERE canonical_name = ? AND deleted_at IS NULL',
              [name],
            ))?['default_unit'] ==
            'kg',
        'the form save to make the row in the local database',
      );
      final created = await db.get(
        'SELECT id, status FROM ingredient '
        'WHERE canonical_name = ? AND deleted_at IS NULL',
        [name],
      );
      expect(
        created['status'],
        'complete',
        reason: 'a new row is saved complete, or not at all',
      );
      // The save POPS the form, the picker resolves with the row it made and
      // the editor opens the quantity sheet on it — chips for the units the
      // form set, kg (the default) among them.
      await pumpUntilFound(tester, find.byType(QuantityUnitEditor));
      final chip = find.descendant(
        of: find.byType(UnitChipRow),
        matching: find.text('kg'),
      );
      expect(chip, findsOneWidget, reason: "the form's default unit chip");
      expect(
        find.descendant(of: find.byType(UnitChipRow), matching: find.text('g')),
        findsOneWidget,
      );
      await tester.enterText(find.byType(EditableText).last, '2');
      await tester.pump();
      await tester.tap(find.text('Done'));
      await tester.pumpAndSettle();
      expect(find.text('2 kg'), findsOneWidget); // the line's quantity pill
      await scrollTo(tester, find.text('Save'), delta: -150);
      await saveRecipe(tester);

      // After the round trip: the row survives as written — complete, since
      // a new row saves no other way, with a match_text that is the
      // normalizer's — `allowed_units` is a REAL json array (the connector
      // fix, not a jsonb string), and the line points at it.
      await stack.waitForSyncRoundTrip(tester);
      final row = await db.get(
        'SELECT status, source, match_text, '
        'json_type(allowed_units) AS shape FROM ingredient WHERE id = ?',
        [created['id']],
      );
      expect(row['status'], 'complete');
      // Nothing matched it, so nothing stamped it: the server stopped
      // guessing a source, and a row with none reads as manual.
      expect(row['source'], isNull);
      expect(row['match_text'], normalizeMatchText(name));
      expect(row['shape'], 'array');
      final line = await db.get(
        'SELECT li.quantity, li.unit FROM recipe_line_item li '
        'JOIN ingredient_group g ON g.id = li.group_id '
        'WHERE g.recipe_id = ? AND li.ingredient_id = ? '
        'AND li.deleted_at IS NULL',
        [seeded.recipeId, created['id']],
      );
      expect(line['quantity'], 2);
      expect(line['unit'], 'kg');
      await tester.tap(find.text('Ingredients'));
      await tester.pumpAndSettle();
      expect(find.text(name), findsOneWidget);
    },
  );
}
