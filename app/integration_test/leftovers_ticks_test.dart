/// Sim smoke — **leftovers by the ticks** (plans 0061/0062), on LIVE sync:
/// what the household's ticks, corrections and removals do to a cooking, read
/// back on the Week, Cook and the Leftovers page.
///
/// 1. **Ticks backfilled out of order.** A dish planned on three days of last
///    week; Sunday ticked, then Saturday, Friday never. The cook day is the
///    earliest ticked day (`cooked Sat` on the Week, `Cooked Sat` on Cook),
///    and the Leftovers row holds the skipped Friday's portions, good till
///    Saturday plus the dish's fridge days. Unticking Saturday moves the cook
///    day to Sunday.
/// 2. **Counts follow ticks.** A count set to 1 on the page, then a meal of 2
///    unticked: 3. Ticked again: 1.
/// 3. **Remove a meal both ate.** Its leftovers stay, and stay after Undo.
/// 4. **Freeze, Froze it, Remove gone off**, each undone; and a later untick
///    never brings food said gone off back.
///
/// Every meal sits in LAST week, which is wholly behind us whatever today is,
/// and every expected date is said by the app's own formatter, so the file
/// holds on any weekday. Ada's ticks go through the meal sheet where the tick
/// is the subject (1, 2) and through the planning repository (the sheet's own
/// write) where it is setup; Jun's are written as Jun over HTTP
/// ([SmokeStack.tickAsPartner]).
///
/// Local gate `make test-sim FILE=leftovers_ticks`. Needs the local backend
/// running (`make db-up`) and the usual `--dart-define`s.
library;

import 'package:ansi/features/cook_plan/domain/cooking.dart' show LeftoverPlace;
import 'package:ansi/features/cook_plan/presentation/cook_view.dart'
    show CookView;
import 'package:ansi/features/cook_plan/presentation/leftover_format.dart'
    show leftoverTill;
import 'package:ansi/features/planning/presentation/week_view.dart'
    show WeekView;
import 'package:flutter_test/flutter_test.dart';
import 'package:forui/forui.dart';
import 'package:integration_test/integration_test.dart';

import 'support/drive.dart';
import 'support/leftovers.dart';
import 'support/stack.dart';

/// `till …` for a fridge row cooked on [cookDay] that keeps [keeps] days.
String _till(DateTime cookDay, int keeps) =>
    leftoverTill(plusDays(cookDay, keeps), smokeToday(), kSmokeShape);

Future<void> _openWeek(WidgetTester tester) async {
  await tapTab(tester, FLucideIcons.calendarDays);
  await pumpUntilFound(tester, find.byType(WeekView));
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  late SmokeStack stack;

  setUpAll(() async => stack = await SmokeStack.start());
  tearDownAll(() => stack.dispose());

  testWidgets('1 · ticks backfilled out of order set the cook day', (
    tester,
  ) async {
    ignoreForuiSemanticsAssertion();
    final db = stack.db;
    await stack.openLibrary(tester);
    const title = 'Backfill Pasta';
    const keeps = 10;
    final m = await smokeMembers(db);
    final lastWeek = weekStartFrom(-1);
    final recipe = await seedDish(
      tester,
      stack,
      title: title,
      ingredient: 'Pasta',
      keepsForDays: keeps,
    );
    // Friday, Saturday, Sunday: Ada's alone, two portions each — made 6.
    final ids = [
      for (final day in [4, 5, 6])
        await planMeal(
          stack,
          weekStart: lastWeek,
          day: day,
          recipeId: recipe,
          eaters: [m.ada],
          portions: 2,
        ),
    ];
    await stack.waitForSyncRoundTrip(tester);

    await _openWeek(tester);
    await stepWeek(tester, -1);
    // The last day first, then the middle one; Friday is never ticked.
    await openMealSheet(tester, 'Sunday', title);
    await tickInSheet(tester);
    await closeSheet(tester);
    await openMealSheet(tester, 'Saturday', title);
    await tickInSheet(tester);
    await closeSheet(tester);
    final cooking = await waitForCooking(tester, db, ids[1]);
    expect(await waitForCooking(tester, db, ids[2]), cooking);

    // The Week: Saturday is the cook day, by the ticks.
    final saturday = await showDish(tester, 'Saturday', title);
    await pumpUntilFound(
      tester,
      find.descendant(of: saturday, matching: find.text('cooked Sat')),
    );
    // Cook, on the same (last) week: ✓ Cooked Sat.
    await tapTab(tester, FLucideIcons.cookingPot);
    await pumpUntilFound(tester, find.byKey(CookView.rootKey));
    await pumpUntilFound(tester, find.text('Cooked Sat'));
    expect(find.text('Cooked Sun'), findsNothing);

    // Leftovers: Friday's two portions, good till Saturday + 10.
    await _openWeek(tester);
    await openLeftovers(tester);
    final sat = dateIn(lastWeek, 5);
    final sun = dateIn(lastWeek, 6);
    await expectLeftover(tester, cooking, '2 left');
    await expectLeftover(tester, cooking, _till(sat, keeps));
    await tapBack(tester);

    // Untick the middle day: the cook day walks later, to Sunday.
    await openMealSheet(tester, 'Saturday', title);
    await untickInSheet(tester);
    await closeSheet(tester);
    final sunday = await showDish(tester, 'Sunday', title);
    await pumpUntilFound(
      tester,
      find.descendant(of: sunday, matching: find.text('cooked Sun')),
    );
    expect(
      find.descendant(
        of: dishRow('Saturday', title),
        matching: find.text('cooked Sat'),
      ),
      findsNothing,
    );
    await tapTab(tester, FLucideIcons.cookingPot);
    await pumpUntilFound(tester, find.byKey(CookView.rootKey));
    await pumpUntilFound(tester, find.text('Cooked Sun'));
    expect(find.text('Cooked Sat'), findsNothing);
    // Made stays the six fixed at the first tick; only Sunday's two are
    // eaten now, and the date counts from Sunday.
    await _openWeek(tester);
    await openLeftovers(tester);
    await expectLeftover(tester, cooking, '4 left');
    await expectLeftover(tester, cooking, _till(sun, keeps));
  });

  testWidgets('2 · a count set by hand still follows the ticks', (
    tester,
  ) async {
    ignoreForuiSemanticsAssertion();
    final db = stack.db;
    await stack.openLibrary(tester);
    const title = 'Counted Chili';
    final m = await smokeMembers(db);
    final lastWeek = weekStartFrom(-1);
    final recipe = await seedDish(
      tester,
      stack,
      title: title,
      ingredient: 'White Rice',
      keepsForDays: 10,
    );
    final ids = [
      for (final day in [4, 5, 6])
        await planMeal(
          stack,
          weekStart: lastWeek,
          day: day,
          recipeId: recipe,
          eaters: [m.ada],
          portions: 2,
        ),
    ];
    await stack.waitForSyncRoundTrip(tester);
    // Saturday and Sunday eaten, Friday skipped: 2 left.
    await tickAsAda(
      stack,
      ids[1],
      memberId: m.ada,
      mealDay: dateIn(lastWeek, 5),
    );
    await tickAsAda(
      stack,
      ids[2],
      memberId: m.ada,
      mealDay: dateIn(lastWeek, 6),
    );
    final cooking = await waitForCooking(tester, db, ids[1]);

    await _openWeek(tester);
    await openLeftovers(tester);
    await expectLeftover(tester, cooking, '2 left');
    // Set it to 1 with the row's stepper.
    final row = leftoverRow(cooking);
    await tester.tap(find.descendant(of: row, matching: find.text('2 left')));
    await tester.pumpAndSettle();
    await tester.tap(
      find.descendant(of: row, matching: find.byIcon(FLucideIcons.minus)),
    );
    await pumpUntilFound(
      tester,
      find.descendant(of: row, matching: find.text('1')),
    );
    // Folding the row shows the chip again.
    await tester.tap(find.descendant(of: row, matching: find.text(title)));
    await tester.pumpAndSettle();
    await expectLeftover(tester, cooking, '1 left');
    await tapBack(tester);

    // Untick Sunday's 2: they are back in the box on top of the count.
    await stepWeek(tester, -1);
    await openMealSheet(tester, 'Sunday', title);
    await untickInSheet(tester);
    await closeSheet(tester);
    await openLeftovers(tester);
    await expectLeftover(tester, cooking, '3 left');
    await tapBack(tester);

    // Tick it again: 1.
    await openMealSheet(tester, 'Sunday', title);
    await tickInSheet(tester);
    await closeSheet(tester);
    await openLeftovers(tester);
    await expectLeftover(tester, cooking, '1 left');
  });

  testWidgets('3 · removing a meal both ate keeps its leftovers', (
    tester,
  ) async {
    ignoreForuiSemanticsAssertion();
    final db = stack.db;
    await stack.openLibrary(tester);
    const title = 'Shared Curry';
    const keeps = 10;
    final m = await smokeMembers(db);
    final lastWeek = weekStartFrom(-1);
    final sat = dateIn(lastWeek, 5);
    final recipe = await seedDish(
      tester,
      stack,
      title: title,
      ingredient: 'Cashews',
      keepsForDays: keeps,
    );
    // Saturday and Sunday for both: made 4. Both eat Saturday, Sunday is
    // skipped, so 2 are left.
    final eaten = await planMeal(
      stack,
      weekStart: lastWeek,
      day: 5,
      recipeId: recipe,
      eaters: [m.ada, m.jun],
    );
    await planMeal(
      stack,
      weekStart: lastWeek,
      day: 6,
      recipeId: recipe,
      eaters: [m.ada, m.jun],
    );
    await stack.waitForSyncRoundTrip(tester);
    await tickAsAda(stack, eaten, memberId: m.ada, mealDay: sat);
    final cooking = await waitForCooking(tester, db, eaten);
    await stack.tickAsPartner(
      eaten,
      eatenAt: DateTime(sat.year, sat.month, sat.day, 19),
    );
    await waitForPartnerTick(tester, db, eaten, m.jun);

    await _openWeek(tester);
    await openLeftovers(tester);
    await expectLeftover(tester, cooking, '2 left');
    await tapBack(tester);

    // Last week stays on screen from here: the Leftovers page is pushed
    // over the Week and leaves the week switcher where it was.
    await stepWeek(tester, -1);
    Future<void> removeSaturday() async {
      final row = await showDish(tester, 'Saturday', title);
      await tester.tap(
        find.descendant(of: row, matching: find.byIcon(FLucideIcons.minus)),
      );
      await pumpUntilFound(
        tester,
        find.textContaining('Removed $title from Saturday'),
      );
      await waitForDb(tester, () async {
        final r = await db.get(
          'SELECT deleted_at FROM plan_entry WHERE id = ?',
          [eaten],
        );
        return r['deleted_at'] != null;
      }, 'the meal to be removed');
    }

    // Removed: still cooked, still 2 left — read through the page's own
    // reader while the toast is up — then Undo.
    await removeSaturday();
    final removed = await readLeftover(stack, cooking);
    expect(removed?.cooked, isTrue, reason: 'its ticks still cook the pot');
    expect(removed?.inBox, closeTo(2, 1e-9));
    await tester.tap(find.text('Undo'));
    await tester.pumpAndSettle();
    await waitForDb(tester, () async {
      final r = await db.get('SELECT deleted_at FROM plan_entry WHERE id = ?', [
        eaten,
      ]);
      return r['deleted_at'] == null;
    }, 'Undo to bring the meal back');
    await pumpUntilGone(tester, find.text('Undo'));
    // After Undo: the count did not move.
    await openLeftovers(tester);
    await expectLeftover(tester, cooking, '2 left');
    await expectLeftover(tester, cooking, _till(sat, keeps));
    await tapBack(tester);

    // Removed for good this time (the toast left on its own): the page
    // still has the 2, dated from Saturday.
    await removeSaturday();
    await pumpUntilGone(tester, find.text('Undo'));
    await openLeftovers(tester);
    await expectLeftover(tester, cooking, '2 left');
    await expectLeftover(tester, cooking, _till(sat, keeps));
  });

  testWidgets('4 · Freeze, Froze it and Remove gone off, each undone', (
    tester,
  ) async {
    ignoreForuiSemanticsAssertion();
    final db = stack.db;
    await stack.openLibrary(tester);
    final m = await smokeMembers(db);
    final lastWeek = weekStartFrom(-1);

    /// Plans [title] on [days] of last week for Ada (2 each), ticks
    /// [ticked] of them, and returns the cooking with every meal's id.
    Future<({String cooking, List<String> ids})> cooked(
      String title,
      String ingredient, {
      required int keeps,
      required bool freezable,
      required List<int> days,
      required List<int> ticked,
    }) async {
      final recipe = await seedDish(
        tester,
        stack,
        title: title,
        ingredient: ingredient,
        keepsForDays: keeps,
        freezable: freezable,
        freezerDays: freezable ? 90 : null,
      );
      final ids = [
        for (final day in days)
          await planMeal(
            stack,
            weekStart: lastWeek,
            day: day,
            recipeId: recipe,
            eaters: [m.ada],
            portions: 2,
          ),
      ];
      await stack.waitForSyncRoundTrip(tester);
      for (final day in ticked) {
        await tickAsAda(
          stack,
          ids[days.indexOf(day)],
          memberId: m.ada,
          mealDay: dateIn(lastWeek, day),
        );
      }
      return (cooking: await waitForCooking(tester, db, ids.first), ids: ids);
    }

    // In date and freezable: Freeze. Saturday eaten, Sunday skipped.
    final chili = await cooked(
      'Freeze Chili',
      'Spaghetti',
      keeps: 10,
      freezable: true,
      days: [5, 6],
      ticked: [5],
    );
    // Past its date (one fridge day from last Friday) and freezable: Froze it.
    final stew = await cooked(
      'Froze Stew',
      'Walnuts',
      keeps: 1,
      freezable: true,
      days: [4, 5],
      ticked: [4],
    );
    // Past its date and not freezable: Remove gone off. Thursday and Friday
    // eaten, Saturday skipped.
    final soup = await cooked(
      'Gone Soup',
      'Almonds',
      keeps: 1,
      freezable: false,
      days: [3, 4, 5],
      ticked: [3, 4],
    );

    await _openWeek(tester);
    await openLeftovers(tester);

    // --- Freeze, then Undo ------------------------------------------------
    await expectLeftover(tester, chili.cooking, '2 left');
    await tester.tap(
      find.descendant(
        of: leftoverRow(chili.cooking),
        matching: find.text('Freeze'),
      ),
    );
    await pumpUntilFound(tester, find.text('Froze Freeze Chili.'));
    await expectLeftover(tester, chili.cooking, '2 left', shelf: 'freezer');
    await tester.tap(find.text('Undo'));
    await tester.pumpAndSettle();
    await expectLeftover(tester, chili.cooking, '2 left');
    await pumpUntilGone(tester, leftoverRow(chili.cooking, shelf: 'freezer'));
    await pumpUntilGone(tester, find.text('Undo'));

    // --- Froze it, then Undo, then Froze it for good -----------------------
    final stewCookDay = dateIn(lastWeek, 4);
    await expectLeftover(tester, stew.cooking, 'past its date');
    Future<void> frozeIt() async {
      await tester.tap(
        find.descendant(
          of: leftoverRow(stew.cooking),
          matching: find.text('Froze it'),
        ),
      );
      await pumpUntilFound(tester, find.text('Froze Froze Stew.'));
      await expectLeftover(tester, stew.cooking, '2 left', shelf: 'freezer');
      // Dated from its cook day, in the freezer's months.
      await expectLeftover(
        tester,
        stew.cooking,
        leftoverTill(
          plusDays(stewCookDay, 90),
          smokeToday(),
          kSmokeShape,
          frozen: true,
        ),
        shelf: 'freezer',
      );
    }

    await frozeIt();
    await tester.tap(find.text('Undo'));
    await tester.pumpAndSettle();
    await expectLeftover(tester, stew.cooking, 'past its date');
    await pumpUntilGone(tester, leftoverRow(stew.cooking, shelf: 'freezer'));
    await pumpUntilGone(tester, find.text('Undo'));
    // In the freezer for good, so Remove gone off below has the soup alone.
    await frozeIt();
    await pumpUntilGone(tester, find.text('Undo'));

    // --- Remove gone off, then Undo, then for good ------------------------
    await expectLeftover(tester, soup.cooking, 'past its date');
    await expectLeftover(tester, soup.cooking, '2 left');
    Future<void> removeGoneOff() async {
      final link = find.text('Remove gone off');
      await scrollTo(tester, link);
      await tester.tap(link);
      await pumpUntilFound(tester, find.text('Undo'));
      await pumpUntilGone(tester, leftoverRow(soup.cooking));
    }

    await removeGoneOff();
    // The freezer's stew is in date: it stays.
    await revealLeftover(tester, leftoverRow(stew.cooking, shelf: 'freezer'));
    await tester.tap(find.text('Undo'));
    await tester.pumpAndSettle();
    await expectLeftover(tester, soup.cooking, '2 left');
    await pumpUntilGone(tester, find.text('Undo'));
    await removeGoneOff();
    await pumpUntilGone(tester, find.text('Undo'));

    // A later untick of Friday would put 2 back in the box: gone is final.
    await tickAsAda(stack, soup.ids[1], memberId: m.ada, mealDay: null);
    await waitForDb(
      tester,
      () async =>
          (await db.getOptional(
            'SELECT id FROM meal_eaten WHERE plan_entry_id = ? '
            'AND deleted_at IS NULL',
            [soup.ids[1]],
          )) ==
          null,
      'the untick to land',
    );
    for (var i = 0; i < 20; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    expect(leftoverRow(soup.cooking), findsNothing);
    expect(await readLeftover(stack, soup.cooking), isNull);
    expect(
      await readLeftover(stack, soup.cooking, place: LeftoverPlace.freezer),
      isNull,
    );
  });
}
