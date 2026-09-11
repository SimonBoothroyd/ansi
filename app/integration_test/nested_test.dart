/// Sim smoke — NESTED RECIPES: a recipe as an ingredient (step 8.6): a
/// sub-recipe with a two-denomination yield set through the editor's MAKES
/// row → a component line taken from the picker's "Your recipes" section and
/// quantified in the batch-math sheet → the parent's recipe chip, the
/// target's "Used in · N" tab and the delete refusal that speaks the same
/// count → planned, so the Cook tab derives the component session and the
/// Shop tab picks up its ingredients with two-level provenance → then the
/// yield is un-stated and every derived number becomes the named gap, never
/// a `×1`.
///
/// Local gate only (`make test-sim FILE=nested`), never CI. Needs the local
/// backend running (`make db-up`) and the usual `--dart-define`s.
library;

import 'package:ansi/core/units/units.dart';
import 'package:ansi/features/recipes/presentation/component_quantity_sheet.dart'
    show ComponentQuantityEditor;
import 'package:ansi/features/recipes/presentation/recipe_chip.dart'
    show RecipeChip;
import 'package:ansi/features/shopping/presentation/shopping_view.dart'
    show ShoppingView;
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:forui/forui.dart';
import 'package:integration_test/integration_test.dart';

import 'support/drive.dart';
import 'support/editor.dart';
import 'support/stack.dart';
import 'support/week.dart';

/// One MAKES slot's row in the editor (board frame h): `yield-1`/`yield-2`.
Finder yieldSlot(String slot) => find.byKey(ValueKey(slot));

/// Types [amount] into a MAKES slot's amount field. An empty string clears
/// the slot — which is how the yield is un-stated (D2).
Future<void> enterYieldAmount(
  WidgetTester tester,
  String slot,
  String amount,
) async {
  await scrollTo(tester, yieldSlot(slot));
  // `.first`: the row's OTHER editable is the unit `FSelect`'s own (forui
  // builds the select on a read-only text field), and it trails the amount.
  await tester.enterText(
    find
        .descendant(of: yieldSlot(slot), matching: find.byType(EditableText))
        .first,
    amount,
  );
  await tester.pumpAndSettle();
}

/// Opens a MAKES slot's unit select and leaves it open for inspection. The
/// popover builds every item eagerly (forui's select content is a
/// `SingleChildScrollView`, not a lazy list), so an item below its fold is
/// findable — it just has to be scrolled to before it can be tapped.
Future<void> openYieldUnits(WidgetTester tester, String slot) async {
  await scrollTo(tester, yieldSlot(slot));
  // `byWidgetPredicate`, not `byType`: forui's `FSelect.rich` builds a
  // private subclass, which an exact runtime-type finder never matches.
  await tester.tap(
    find.descendant(
      of: yieldSlot(slot),
      matching: find.byWidgetPredicate((w) => w is FSelect<Unit>),
    ),
  );
  await tester.pumpAndSettle();
}

/// Picks [label] in a MAKES slot's unit select. `.last`: the popover's item
/// is later in the tree than the closed select showing its current value.
Future<void> pickYieldUnit(
  WidgetTester tester,
  String slot,
  String label,
) async {
  await openYieldUnits(tester, slot);
  final item = find.text(label).last;
  await tester.ensureVisible(item);
  await tester.pumpAndSettle();
  await tester.tap(item);
  await tester.pumpAndSettle();
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  late SmokeStack stack;

  setUpAll(() async => stack = await SmokeStack.start());
  tearDownAll(() => stack.dispose());

  testWidgets('nested recipes: yield → component line → plan → cook + shop', (
    tester,
  ) async {
    ignoreForuiSemanticsAssertion();
    final db = stack.db;
    await stack.openLibrary(tester);

    // ------------------------------------------------------------------------
    // 6a · THE SUB-RECIPE — what one batch makes, in two denominations.
    // ------------------------------------------------------------------------
    await startRecipe(tester, 'Romesco Aioli');

    // The MAKES row (board frame h): "makes 1 cup". The unit select starts on
    // `g`, so the amount and the unit are both set by hand — which is exactly
    // what an import leaves for a human when `yield_raw` isn't a plain
    // amount + unit (D9).
    await enterYieldAmount(tester, 'yield-1', '1');
    await pickYieldUnit(tester, 'yield-1', 'cup');

    // The second denomination, and the other-family lock on its selector: two
    // ways of saying ONE batch, never two numbers in one family (D2).
    await scrollTo(tester, find.text('Another denomination'));
    await tester.tap(find.text('Another denomination'));
    await tester.pumpAndSettle();
    expect(
      find.textContaining('never two numbers in one family'),
      findsOneWidget,
    );
    await openYieldUnits(tester, 'yield-2');
    expect(
      find.text('ml'),
      findsNothing,
      reason: 'the first slot is a volume — the second must not offer volumes',
    );
    expect(find.text('tbsp'), findsNothing);
    expect(
      find.text('kg'),
      findsWidgets,
      reason: 'the other families are open',
    );
    await tester.tap(find.text('g').last); // keep `g`, close the popover
    await tester.pumpAndSettle();
    await enterYieldAmount(tester, 'yield-2', '250');

    // A few real lines off the synced vocab. Olive Oil is deliberately shared
    // with the parent below: one shopping item, two levels of provenance.
    await addVocabLine(tester, 'almond', 'Almonds', '100');
    await addVocabLine(tester, 'red bell', 'Red Bell Pepper', '2');
    await addVocabLine(tester, 'olive oil', 'Olive Oil', '60');

    await saveRecipe(tester);
    // The hero meta row reads as one sentence in two pills (board frame b).
    expect(find.text('makes 1 cup'), findsOneWidget);
    expect(find.text('· 250 g'), findsOneWidget);

    // Both denominations survive the server round-trip — the migration's
    // "different family" CHECK accepts the pair, so the upload queue drains.
    await stack.waitForSyncRoundTrip(tester);
    final aioli = await db.get(
      'SELECT id, yield_qty, yield_unit, yield_qty_2, yield_unit_2 '
      "FROM recipe WHERE title = 'Romesco Aioli' AND deleted_at IS NULL",
    );
    expect(aioli['yield_qty'], 1);
    expect(aioli['yield_unit'], 'cup');
    expect(aioli['yield_qty_2'], 250);
    expect(aioli['yield_unit_2'], 'g');

    // ------------------------------------------------------------------------
    // 6b · THE PARENT — a component line through the picker's "Your recipes".
    // ------------------------------------------------------------------------
    await backFromRecipe(tester);
    await startRecipe(tester, 'Sausage Sliders');
    await addVocabLine(tester, 'olive oil', 'Olive Oil', '2');

    await addComponentLine(
      tester,
      'romesco',
      'Romesco Aioli',
      hint: 'makes 1 cup',
    );
    // The picker row carried the yield as its hint, and the sheet that opened
    // is the batch-math one: the target's chip, its yields, and the live
    // conversion line (board frame d).
    expect(find.textContaining('your recipe'), findsOneWidget);
    await tester.enterText(
      find.descendant(
        of: find.byType(ComponentQuantityEditor),
        matching: find.byType(EditableText),
      ),
      '0.25',
    );
    await tester.pumpAndSettle();
    expect(
      find.text('1/4 cup = 1/4 of a batch · makes 1 cup'),
      findsOneWidget,
      reason: 'the conversion line must read the batch math, live',
    );
    await tester.tap(find.text('Done'));
    await tester.pumpAndSettle();

    await saveRecipe(tester);

    // The saved line is a component in the D1 sense: the sub-recipe identity,
    // no ingredient, no measure — and it stays that way after the round trip
    // (the server's XOR + measure CHECKs accepted the write).
    final sliders = await db.get(
      "SELECT id FROM recipe WHERE title = 'Sausage Sliders' "
      'AND deleted_at IS NULL',
    );
    await stack.waitForSyncRoundTrip(tester);
    final component = await db.get(
      'SELECT li.quantity, li.unit, li.ingredient_id, li.sub_recipe_id, '
      'li.measure_id FROM recipe_line_item li '
      'JOIN ingredient_group g ON g.id = li.group_id '
      'WHERE g.recipe_id = ? AND li.sub_recipe_id IS NOT NULL '
      'AND li.deleted_at IS NULL',
      [sliders['id']],
    );
    expect(component['sub_recipe_id'], aioli['id']);
    expect(component['ingredient_id'], isNull);
    expect(component['measure_id'], isNull, reason: 'measures are ingredients');
    expect(component['quantity'], 0.25);
    expect(component['unit'], 'cup');

    // ------------------------------------------------------------------------
    // 6c · THE TWO FACES — the parent's chip, the target's "Used in" tab, and
    //      the delete refusal that speaks the same count (D5 · D7 · D9).
    // ------------------------------------------------------------------------
    // The v3 grammar is untouched; only the identity cell changed.
    expect(find.text('1/4 cup'), findsOneWidget);
    expect(find.byType(RecipeChip), findsOneWidget);
    await tester.tap(find.byType(RecipeChip));
    await pumpUntilFound(tester, find.text('makes 1 cup'));

    // The aioli's own page, with the conditional third tab carrying its count.
    await tester.tap(find.text('Used in · 1'));
    await tester.pumpAndSettle();
    expect(find.text('Sausage Sliders'), findsOneWidget);
    expect(
      find.text('1/4 cup · 1/4 of a batch'),
      findsOneWidget,
      reason: 'a "used in" row states the printed amount AND its share',
    );
    // The rows are real: this one pushes the parent.
    await tester.tap(find.text('Sausage Sliders'));
    await pumpUntilFound(tester, find.byType(RecipeChip));
    await backFromRecipe(tester);
    await pumpUntilFound(tester, find.text('makes 1 cup'));

    // Deleting a recipe something points at is refused, with the count (D5).
    await tester.tap(
      find.descendant(
        of: find.byType(FHeaderAction),
        matching: find.byIcon(FLucideIcons.ellipsis),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Delete'));
    await pumpUntilFound(tester, find.text('Can’t delete this recipe'));
    expect(
      find.text('Used in 1 recipe (1 line). Change those lines first.'),
      findsOneWidget,
    );
    await tester.tap(find.text('OK'));
    await tester.pumpAndSettle();
    await tester.tapAt(const Offset(40, 300)); // dismiss the popover
    await tester.pumpAndSettle();
    final stillThere = await db.get(
      'SELECT deleted_at FROM recipe WHERE id = ?',
      [aioli['id']],
    );
    expect(stillThere['deleted_at'], isNull, reason: 'the refusal must hold');

    // ------------------------------------------------------------------------
    // 6d · THE PLAN — a component is a real derived session, and its
    //      ingredients flow into the list with two-level provenance (D3 · D4).
    // ------------------------------------------------------------------------
    await backToShell(tester);
    await tapTab(tester, FLucideIcons.calendarDays);
    // The lens's `Shared` became `Everyone` (D8); now there is no
    // mode to enter — `addMealOn` taps the day card's own add line (E5).
    await pumpUntilFound(tester, find.text('Everyone'));
    await addMealOn(tester, 'Friday', 'Sausage Sliders');

    await tapTab(tester, FLucideIcons.cookingPot);
    await pumpUntilFound(
      tester,
      find.text('Romesco Aioli · for Sausage Sliders'),
    );
    await scrollTo(tester, find.text('Romesco Aioli · for Sausage Sliders'));
    expect(find.text('derived from a component line'), findsOneWidget);
    // Ready BY the demanding parent's cook day, denominated in batches.
    expect(find.text('Cook by Fri'), findsOneWidget);
    expect(find.text('×1/4 batch'), findsOneWidget);
    expect(
      find.text(
        'covers Sausage Sliders · cook Fri — makes 1 cup, you need '
        '1/4',
      ),
      findsOneWidget,
    );
    expect(
      find.textContaining('Nothing here tracks the leftover'),
      findsOneWidget,
      reason: 'a fractional batch says so out loud (an 8.6 non-goal)',
    );

    await tapTab(tester, FLucideIcons.shoppingBasket);
    await pumpUntilFound(tester, find.byKey(ShoppingView.rootKey));
    // The component LINE never becomes an item (you buy almonds, not aioli) —
    // the aioli's own lines do, through the derived session.
    await scrollTo(tester, find.text('Almonds'));
    expect(find.text('Romesco Aioli'), findsNothing);
    expect(
      find.text('Romesco Aioli · for Sausage Sliders · cook Fri'),
      findsWidgets,
      reason: 'the nested contribution names both levels',
    );
    // Olive Oil is on both levels, so its breakdown carries both segments.
    await scrollTo(tester, find.text('Olive Oil'));
    final oilRow = find
        .ancestor(of: find.text('Olive Oil'), matching: find.byType(Column))
        .first;
    expect(
      find.descendant(of: oilRow, matching: find.text('Sausage Sliders')),
      findsOneWidget,
      reason: "the parent's own line reads as it always has",
    );
    expect(
      find.descendant(
        of: oilRow,
        matching: find.text('Romesco Aioli · for Sausage Sliders · cook Fri'),
      ),
      findsOneWidget,
    );

    // ------------------------------------------------------------------------
    // 6e · THE HONEST GAP — un-state the yield and the derived numbers go away
    //      rather than turning into a ×1 (D2 · D3 · D4).
    // ------------------------------------------------------------------------
    await tapTab(tester, FLucideIcons.library);
    await pumpUntilFound(tester, find.text('Our Cookbook'));
    await scrollTo(tester, find.text('Romesco Aioli'));
    await tester.tap(find.text('Romesco Aioli'));
    await pumpUntilFound(tester, find.text('makes 1 cup'));
    await tester.tap(
      find.descendant(
        of: find.byType(FHeaderAction),
        matching: find.byIcon(FLucideIcons.ellipsis),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Edit'));
    await pumpUntilFound(tester, find.text('Edit recipe'));
    await enterYieldAmount(tester, 'yield-1', '');
    await saveRecipe(tester);

    // Clearing the first denomination drops the second with it — the pair the
    // migration's CHECK pins can never be half-stated.
    expect(find.text('makes 1 cup'), findsNothing);
    expect(find.text('· 250 g'), findsNothing);
    await stack.waitForSyncRoundTrip(tester);
    final cleared = await db.get(
      'SELECT yield_qty, yield_unit, yield_qty_2, yield_unit_2 FROM recipe '
      'WHERE id = ?',
      [aioli['id']],
    );
    expect(cleared['yield_qty'], isNull);
    expect(cleared['yield_unit'], isNull);
    expect(cleared['yield_qty_2'], isNull);
    expect(cleared['yield_unit_2'], isNull);

    // The Cook tab: the session becomes a NAMED GAP. Never a ×1 — assuming one
    // batch is exactly the invented number this app refuses.
    await backToShell(tester);
    await tapTab(tester, FLucideIcons.cookingPot);
    await pumpUntilFound(
      tester,
      find.text('Romesco Aioli doesn’t say how much it makes'),
    );
    await scrollTo(tester, find.text('Romesco Aioli · for Sausage Sliders'));
    expect(
      find.text('derived from a component line · yield not set'),
      findsOneWidget,
    );
    expect(find.text('no scale'), findsOneWidget);
    expect(find.text('Set the yield'), findsOneWidget);
    // The one number a gap CAN state is what the demanding line printed —
    // unscaled, unconverted, quoted from the page (frame f).
    expect(
      find.text(
        'covers Sausage Sliders · cook Fri — the line asks for '
        '1/4 cup',
      ),
      findsOneWidget,
    );
    expect(find.text('×1/4 batch'), findsNothing);
    expect(find.text('×1 batch'), findsNothing);

    // The Shop tab: the unresolved component contributes NOTHING, and the
    // parent says so rather than leaving the list quietly short (D4).
    await tapTab(tester, FLucideIcons.shoppingBasket);
    await pumpUntilFound(tester, find.byKey(ShoppingView.rootKey));
    await scrollTo(tester, find.text('1 component unresolved — see Cook'));
    expect(find.text('SAUSAGE SLIDERS'), findsOneWidget);
    expect(
      find.text('Romesco Aioli · for Sausage Sliders · cook Fri'),
      findsNothing,
      reason: 'an unresolved component contributes nothing — never a guess',
    );
    expect(find.text('Almonds'), findsNothing);
  });
}
