/// Sim smoke — **what a batch makes** (plan 0062), on LIVE sync.
///
/// 7. **Whole batch.** A serves-4 recipe planned for two, with Cook's
///    `×1 whole batch` chosen: both eat it and 2 are left — the spare the
///    whole batch made, not 0.
/// 9. **A recipe opens at its cooking's amount.** A serves-2 dish planned
///    twice today for both of them is one pot of 4: its title on the Week and
///    on Cook opens the recipe at `4 servings`, not the recipe's own 2.
///
/// Every meal is today's, so the file holds on any weekday. Ada ticks through
/// the meal sheet; Jun's tick is written as Jun over HTTP
/// ([SmokeStack.tickAsPartner]).
///
/// Local gate `make test-sim FILE=leftovers_batch`. Needs the local backend
/// running (`make db-up`) and the usual `--dart-define`s.
library;

import 'package:ansi/features/cook_plan/presentation/cook_view.dart'
    show CookView;
import 'package:ansi/features/planning/presentation/week_view.dart'
    show WeekView;
import 'package:flutter_test/flutter_test.dart';
import 'package:forui/forui.dart';
import 'package:integration_test/integration_test.dart';

import 'support/drive.dart';
import 'support/leftovers.dart';
import 'support/stack.dart';
import 'support/week.dart';

Future<void> _openWeek(WidgetTester tester) async {
  await tapTab(tester, FLucideIcons.calendarDays);
  await pumpUntilFound(tester, find.byType(WeekView));
}

Future<void> _openCook(WidgetTester tester) async {
  await tapTab(tester, FLucideIcons.cookingPot);
  await pumpUntilFound(tester, find.byKey(CookView.rootKey));
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  late SmokeStack stack;

  setUpAll(() async => stack = await SmokeStack.start());
  tearDownAll(() => stack.dispose());

  testWidgets('7 · a whole batch chosen leaves its spare', (tester) async {
    ignoreForuiSemanticsAssertion();
    final db = stack.db;
    await stack.openLibrary(tester);
    const title = 'Whole Pot Curry';
    final m = await smokeMembers(db);
    final today = dayName(todayOffset());
    final recipe = await seedDish(
      tester,
      stack,
      title: title,
      ingredient: 'Cashews',
      servings: 4,
      keepsForDays: 10,
    );
    final meal = await planMeal(
      stack,
      weekStart: weekStartFrom(0),
      day: todayOffset(),
      recipeId: recipe,
      eaters: [m.ada, m.jun],
    );
    await stack.waitForSyncRoundTrip(tester);

    // Cook: ×½ exact or ×1 whole batch. The whole batch, which births the
    // pot.
    await _openCook(tester);
    final whole = find.text('×1 whole batch');
    await scrollTo(tester, whole);
    await tester.tap(whole);
    await tester.pumpAndSettle();
    final cooking = await waitForCooking(tester, db, meal);

    // Both eat it: Ada on the sheet, Jun on his phone.
    await _openWeek(tester);
    await openMealSheet(tester, today, title);
    await tickInSheet(tester);
    await closeSheet(tester);
    await stack.tickAsPartner(meal);
    await waitForPartnerTick(tester, db, meal, m.jun);

    // Made 4 (the whole batch), 2 eaten: 2 left.
    await openLeftovers(tester);
    await expectLeftover(tester, cooking, '2 left');
  });

  testWidgets('9 · a recipe opens at its cooking’s amount', (tester) async {
    ignoreForuiSemanticsAssertion();
    final db = stack.db;
    await stack.openLibrary(tester);
    const title = 'Scaled Dal';
    final m = await smokeMembers(db);
    final today = dayName(todayOffset());
    final recipe = await seedDish(
      tester,
      stack,
      title: title,
      ingredient: 'Rolled Oats',
      keepsForDays: 10,
    );
    // Lunch and dinner today, both of them: one pot of 4.
    for (final slot in ['Lunch', 'Dinner']) {
      await planMeal(
        stack,
        weekStart: weekStartFrom(0),
        day: todayOffset(),
        recipeId: recipe,
        eaters: [m.ada, m.jun],
        slot: slot,
      );
    }
    await stack.waitForSyncRoundTrip(tester);

    // The Week: the meal's title opens the whole pot, not its own 2.
    await _openWeek(tester);
    await showDish(tester, today, title);
    await tester.tap(
      find.descendant(of: dayCard(today), matching: find.text(title)).first,
    );
    await pumpUntilFound(tester, find.text('4 servings'));
    expect(find.text('2 servings'), findsNothing);
    await tapBack(tester);

    // Cook: the card's title opens the batch it names.
    await _openCook(tester);
    await scrollTo(tester, find.text(title));
    await tester.tap(find.text(title).first);
    await pumpUntilFound(tester, find.text('4 servings'));
    expect(find.text('2 servings'), findsNothing);
    await tapBack(tester);
  });
}
