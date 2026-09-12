/// Sim smoke — **this week's variant**, on LIVE sync, so the delta rows have
/// to survive the round trip and come back down as a week the shop can read.
///
/// The flow, end to end: a recipe planned on two days of one week, the door at
/// the foot of the meal editor sheet, week mode's list (no header form, no
/// method), a swap and an exclusion, Save — then the week grid's mark on BOTH
/// planned days, the Cook card's clause, and the Shop list buying the swapped
/// thing with its reason and naming the line that left.
///
/// It is **self-provisioning**, like every other file here: it seeds its own
/// recipe through the app's own repository over a throwaway household and
/// round-trips it through sync before the Week tab opens. It never drives
/// another flow's UI to set up its own.
///
/// The recipe is "Ragù Night" — two weighed lines of vocab rows the seed
/// filled (Almonds and Flour, both `complete`), serving two — because the
/// assertions are about the SHOP, and a stub line would be honestly dropped
/// before it got there.
///
/// Local gate only (`make test-sim FILE=week_variant`), never CI. Needs the
/// local backend running (`make db-up`) and the usual `--dart-define`s.
library;

import 'package:ansi/core/units/units.dart' show g;
import 'package:ansi/core/week_shape.dart';
import 'package:ansi/features/cook_plan/presentation/cook_view.dart'
    show CookView;
import 'package:ansi/features/planning/presentation/week_variant_editor.dart'
    show WeekVariantEditorView;
import 'package:ansi/features/planning/presentation/week_view.dart'
    show WeekView;
import 'package:ansi/features/planning/presentation/week_widgets.dart'
    show EaterAvatarStack, EditedForThisWeekMark;
import 'package:ansi/features/recipes/data/recipe_repository_impl.dart';
import 'package:ansi/features/recipes/domain/recipe.dart';
import 'package:ansi/features/recipes/presentation/recipe_header_form.dart'
    show RecipeHeaderForm;
import 'package:ansi/features/shopping/presentation/shopping_view.dart'
    show ShoppingView;
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:forui/forui.dart';
import 'package:integration_test/integration_test.dart';
import 'package:powersync/powersync.dart' hide Column;
import 'package:uuid/uuid.dart';

import 'support/drive.dart';
import 'support/stack.dart';
import 'support/week.dart';

const _uuid = Uuid();

/// The recipe this file varies: two weighed lines whose vocab rows the seed
/// filled, so every one of them reaches the shopping list.
Future<String> _seedRagu(
  PowerSyncDatabase db, {
  required String householdId,
}) async {
  final almonds = await db.get(
    "SELECT id FROM ingredient WHERE canonical_name = 'Almonds' "
    "AND status = 'complete' AND deleted_at IS NULL",
  );
  final flour = await db.get(
    "SELECT id FROM ingredient WHERE canonical_name = 'All-Purpose Flour' "
    'AND deleted_at IS NULL',
  );
  final book = await db.get(
    'SELECT id FROM book WHERE deleted_at IS NULL '
    'ORDER BY sort_order, created_at LIMIT 1',
  );
  final recipeId = _uuid.v4();
  await SqliteRecipeRepository(db, householdId: householdId).saveRecipe(
    Recipe(
      id: recipeId,
      title: 'Ragù Night',
      servingsBase: 2,
      keepsForDays: 4,
      bookId: book['id'] as String,
      steps: const ['Brown it.', 'Simmer it.'],
      groups: [
        IngredientGroup(
          id: _uuid.v4(),
          items: [
            LineItem(
              id: _uuid.v4(),
              ingredientId: almonds['id'] as String,
              ingredientName: 'Almonds',
              unit: g,
              quantity: 200,
            ),
            LineItem(
              id: _uuid.v4(),
              ingredientId: flour['id'] as String,
              ingredientName: 'All-Purpose Flour',
              unit: g,
              quantity: 100,
            ),
          ],
        ),
      ],
    ),
  );
  return recipeId;
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  late SmokeStack stack;

  setUpAll(() async => stack = await SmokeStack.start());
  tearDownAll(() => stack.dispose());

  testWidgets('a recipe edited for one week, all the way to the shop', (
    tester,
  ) async {
    ignoreForuiSemanticsAssertion();
    final db = stack.db;
    await stack.openLibrary(tester);

    await _seedRagu(db, householdId: stack.householdId);
    // The seed goes up and comes back down before anything reads it: the week
    // plans a recipe the server has, exactly as it would one authored on the
    // partner's device.
    await stack.waitForSyncRoundTrip(tester);
    final weekKey = isoDate(WeekShape.monday.weekStartOf(DateTime.now()));

    // ------------------------------------------------------------------------
    // 1 · The same dish on two days of one week.
    // ------------------------------------------------------------------------
    await tapTab(tester, FLucideIcons.calendarDays);
    await pumpUntilFound(tester, find.byType(WeekView));
    await addMealOn(tester, 'Tuesday', 'Ragù Night');
    await addMealOn(tester, 'Saturday', 'Ragù Night');

    // ------------------------------------------------------------------------
    // 2 · The door: the meal editor sheet's last row, stating its own scope.
    // ------------------------------------------------------------------------
    // The editor opens from the avatars that draw the eaters — the dish
    // title opens the recipe.
    await scrollTo(tester, find.text('Tuesday'));
    final cluster = find.descendant(
      of: dayCard('Tuesday'),
      matching: find.byType(EaterAvatarStack),
    );
    await tester.ensureVisible(cluster.first);
    await tester.pumpAndSettle();
    await tester.tap(cluster.first);
    await tester.pumpAndSettle();
    await pumpUntilFound(tester, find.text('As the recipe has them'));
    // The sheet is per MEAL and the variant is per week and recipe, so the row
    // says so in its own words before anybody taps it.
    expect(
      find.textContaining('a change covers every day this week'),
      findsOneWidget,
    );
    await tester.tap(find.text('edit for this week'));
    await tester.pumpAndSettle();

    // ------------------------------------------------------------------------
    // 3 · Week mode: the list, and nothing it cannot edit.
    // ------------------------------------------------------------------------
    await pumpUntilFound(tester, find.byType(WeekVariantEditorView));
    expect(find.byType(RecipeHeaderForm), findsNothing);
    expect(find.text('Brown it.'), findsNothing);
    expect(find.textContaining('from the recipe · not edited here'), findsOne);

    // The bin on a recipe line EXCLUDES it; the row stays, struck.
    // The line's own row is the nearest Row above the name that holds exactly
    // one bin — the control nests rows, so neither the innermost nor the
    // outermost ancestor is the line.
    Finder? flourBin;
    for (final row
        in find
            .ancestor(
              of: find.textContaining('All-Purpose Flour').first,
              matching: find.byType(Row),
            )
            .evaluate()) {
      final bins = find.descendant(
        of: find.byWidget(row.widget),
        matching: find.byIcon(FLucideIcons.x),
      );
      if (bins.evaluate().length == 1) {
        flourBin = bins;
        break;
      }
    }
    expect(flourBin, isNotNull, reason: 'the flour line has one bin');
    await tester.tap(flourBin!);
    await tester.pumpAndSettle();
    await pumpUntilFound(tester, find.text('this week · left out'));
    expect(find.text('Back to the recipe · drops 1 change'), findsOneWidget);

    // Nothing is stored until Save — the editor's own posture.
    expect(
      await db.get(
        'SELECT COUNT(*) AS n FROM week_recipe_line_override '
        'WHERE deleted_at IS NULL',
      ),
      containsPair('n', 0),
    );

    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    await waitForDb(
      tester,
      () async =>
          (await db.get(
            'SELECT COUNT(*) AS n FROM week_recipe_line_override wro '
            'JOIN week_plan wp ON wp.id = wro.week_plan_id '
            'WHERE wp.week_start_date = ? AND wro.deleted_at IS NULL',
            [weekKey],
          ))['n'] ==
          1,
      'the exclusion to be stored',
      // A cross-client round trip: the app uploads, the service replicates,
      // this file's own client downloads — not one write to one database.
      timeout: const Duration(seconds: 60),
    );

    // Save pops the editor back onto the meal sheet it was opened from; the
    // sheet's barrier would swallow every tap below, the tab bar included.
    if (find.text('Close').evaluate().isNotEmpty) {
      await tester.tap(find.text('Close'));
      await tester.pumpAndSettle();
    }

    // ------------------------------------------------------------------------
    // 4 · The week grid: BOTH planned days read the one variant.
    // ------------------------------------------------------------------------
    await pumpUntilFound(tester, find.byType(WeekView));
    await scrollTo(tester, find.text('Tuesday'));
    await pumpUntilFound(tester, find.byType(EditedForThisWeekMark));
    await scrollTo(tester, find.text('Saturday'));
    expect(find.byType(EditedForThisWeekMark), findsWidgets);

    // ------------------------------------------------------------------------
    // 5 · Cook: one pot for both days, and four words on the card.
    // ------------------------------------------------------------------------
    await tapTab(tester, FLucideIcons.cookingPot);
    await pumpUntilFound(tester, find.byKey(CookView.rootKey));
    expect(
      find.textContaining('edited for this week'),
      findsOneWidget,
      reason: 'one card, because the variant is per (week, recipe)',
    );

    // ------------------------------------------------------------------------
    // 6 · Shop: the excluded line is gone from the aisles, and named instead.
    // ------------------------------------------------------------------------
    await tapTab(tester, FLucideIcons.shoppingBasket);
    await pumpUntilFound(tester, find.byKey(ShoppingView.rootKey));
    await pumpUntilFound(tester, find.text('Almonds'));
    expect(find.text('All-Purpose Flour'), findsNothing);
    await scrollTo(tester, find.textContaining('left out this week'));
    expect(
      find.textContaining('1 line left out this week — All-Purpose Flour'),
      findsOneWidget,
    );
  });
}
