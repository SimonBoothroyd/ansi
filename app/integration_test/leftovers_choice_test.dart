/// Sim smoke — **planning from a pot** (plan 0062), on LIVE sync: the add
/// flow's choice, a pick across the week edge, and a double-tapped Add.
///
/// 5. **The choice sheet.** Adding a dish that has a pot asks **From
///    leftovers · Cook fresh** with neither picked and Add disabled until
///    one is; From leftovers for more than is left is blocked (`only 1
///    portion left`), and fits once the portions do.
/// 6. **A pick across the week edge.** Ragù planned later this week (today,
///    on a Sunday); next Thursday picks `Ragù · cooks <day>`. One cooking:
///    this week's Shop buys it, next week's has nothing for it, and next
///    week's Cook reads `Ragù · Thu · from the freezer`.
/// 8. **Double-tapped Add.** No crash, and exactly one meal.
///
/// Meals are placed on today, later this week, or next week, all from the
/// real today, so the file holds on any weekday.
///
/// Local gate `make test-sim FILE=leftovers_choice`. Needs the local backend
/// running (`make db-up`) and the usual `--dart-define`s.
library;

import 'package:ansi/features/cook_plan/data/leftover_repository_impl.dart';
import 'package:ansi/features/cook_plan/domain/cooking.dart' show LeftoverPlace;
import 'package:ansi/features/cook_plan/presentation/cook_view.dart'
    show CookView;
import 'package:ansi/features/cook_plan/presentation/leftover_format.dart'
    show leftoverDay;
import 'package:ansi/features/planning/presentation/week_view.dart'
    show WeekView;
import 'package:ansi/features/shopping/presentation/shopping_view.dart'
    show ShoppingView, shopChevronTargetKey;
import 'package:flutter/widgets.dart';
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

/// The confirm sheet's Add, by its words.
Finder _add(String day) => find.widgetWithText(FButton, 'Add to $day');

bool _addEnabled(WidgetTester tester, String day) =>
    tester.widget<FButton>(_add(day)).onPress != null;

/// Whether the confirm sheet's choice whose words start with [label] is
/// picked: each choice states it in its semantics. `.last`: the sheet is
/// built over the Week.
bool _picked(WidgetTester tester, String label) => tester
    .widget<Semantics>(
      find
          .byWidgetPredicate(
            (w) =>
                w is Semantics &&
                (w.properties.button ?? false) &&
                (w.properties.label?.startsWith(label) ?? false),
          )
          .last,
    )
    .properties
    .selected!;

/// The recipe's own row in the open picker: `.last`, because the picker's
/// Leftovers block above the list can carry the same title.
Future<void> _pickRecipe(WidgetTester tester, String title) async {
  await pumpUntilFound(tester, find.text(title));
  await tester.tap(find.text(title).last);
  await pumpUntilFound(tester, find.text('Add to plan'));
}

/// The plan's live meals of [recipeId], by week key.
Future<List<Map<String, Object?>>> _meals(SmokeStack stack, String recipeId) =>
    stack.db.getAll(
      'SELECT pe.id, pe.cooking, pe.day_of_week, wp.week_start_date AS week '
      'FROM plan_entry pe JOIN week_plan wp ON wp.id = pe.week_plan_id '
      'WHERE pe.recipe_id = ? AND pe.deleted_at IS NULL',
      [recipeId],
    );

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  late SmokeStack stack;

  setUpAll(() async => stack = await SmokeStack.start());
  tearDownAll(() => stack.dispose());

  testWidgets('5 · a dish with a pot asks From leftovers or Cook fresh', (
    tester,
  ) async {
    ignoreForuiSemanticsAssertion();
    await stack.openLibrary(tester);
    const title = 'Pot Chili';
    final today = dayName(todayOffset());
    final recipe = await seedDish(
      tester,
      stack,
      title: title,
      ingredient: 'Rolled Oats',
      keepsForDays: 10,
    );
    // One portion in the fridge, said today, as *Add a leftover* says it.
    final pot =
        await SqliteLeftoverRepository(
          stack.db,
          householdId: stack.householdId,
        ).addLeftover(
          place: LeftoverPlace.fridge,
          portions: 1,
          since: smokeToday(),
          recipeId: recipe,
        );
    await stack.waitForSyncRoundTrip(tester);

    await _openWeek(tester);
    await openPickerOn(tester, today);
    await _pickRecipe(tester, title);

    // The choice, neither side picked, and Add waits for one.
    await pumpUntilFound(tester, find.text('From leftovers'));
    expect(find.text('Cook fresh'), findsOneWidget);
    expect(_picked(tester, 'From leftovers'), isFalse);
    expect(_picked(tester, 'Cook fresh'), isFalse);
    expect(_addEnabled(tester, today), isFalse);

    // From leftovers for both of them: 2 wanted, 1 there — blocked.
    await tester.tap(find.text('From leftovers'));
    await tester.pumpAndSettle();
    expect(_picked(tester, 'From leftovers'), isTrue);
    await pumpUntilFound(tester, find.text('only 1 portion left'));
    expect(_addEnabled(tester, today), isFalse);

    // One portion fits: Add comes alive and links the meal to the pot.
    final minus = find.byIcon(FLucideIcons.minus).last;
    await tester.ensureVisible(minus);
    await tester.pumpAndSettle();
    await tester.tap(minus);
    await pumpUntilFound(tester, find.text('uses all of it'));
    expect(_addEnabled(tester, today), isTrue);
    await tester.ensureVisible(_add(today));
    await tester.pumpAndSettle();
    await tester.tap(_add(today));
    await pumpUntilGone(tester, find.text('Add to plan'));
    await waitForDb(tester, () async {
      final meals = await _meals(stack, recipe);
      return meals.length == 1 && meals.single['cooking'] == pot;
    }, 'the meal planned from the pot');
  });

  testWidgets('8 · a double-tapped Add adds one meal and pops once', (
    tester,
  ) async {
    ignoreForuiSemanticsAssertion();
    await stack.openLibrary(tester);
    const title = 'Twice Tart';
    final today = dayName(todayOffset());
    final recipe = await seedDish(
      tester,
      stack,
      title: title,
      ingredient: 'Peanut Butter',
    );
    await stack.waitForSyncRoundTrip(tester);

    await _openWeek(tester);
    await openPickerOn(tester, today);
    await _pickRecipe(tester, title);
    // No pot: Add is live from the start.
    expect(find.text('From leftovers'), findsNothing);
    await tester.ensureVisible(_add(today));
    await tester.pumpAndSettle();
    expect(_addEnabled(tester, today), isTrue);
    // Two taps with no frame between them: the second lands on the same
    // button before the first write has rebuilt anything.
    await tester.tap(_add(today));
    await tester.tap(_add(today));
    await pumpUntilGone(tester, find.text('Add to plan'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    // The Week is still there under it: only the sheet popped.
    expect(find.byType(WeekView), findsOneWidget);
    await pumpUntilFound(
      tester,
      find.descendant(of: dayCard(today), matching: find.text(title)),
    );
    await waitForDb(
      tester,
      () async => (await _meals(stack, recipe)).isNotEmpty,
      'the meal',
    );
    for (var i = 0; i < 20; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    expect(await _meals(stack, recipe), hasLength(1));
    expect(
      find.descendant(of: dayCard(today), matching: find.text(title)),
      findsOneWidget,
    );
  });

  testWidgets('6 · a pot picked next week is cooked and bought once', (
    tester,
  ) async {
    ignoreForuiSemanticsAssertion();
    final db = stack.db;
    await stack.openLibrary(tester);
    const title = 'Ragù Pick';
    const ingredient = 'Walnuts';
    final m = await smokeMembers(db);
    final t = todayOffset();
    // Later this week; on a Sunday, today (a pot planned today is still
    // to cook).
    final cookDay = t < 6 ? t + 1 : t;
    final thisWeek = weekStartFrom(0);
    final recipe = await seedDish(
      tester,
      stack,
      title: title,
      ingredient: ingredient,
      // Three fridge days: next Thursday is always past them, so it eats
      // from the freezer.
      keepsForDays: 3,
      freezable: true,
      freezerDays: 90,
    );
    final ragu = await planMeal(
      stack,
      weekStart: thisWeek,
      day: cookDay,
      recipeId: recipe,
      eaters: [m.ada, m.jun],
    );
    await stack.waitForSyncRoundTrip(tester);

    // Next week's Thursday picks the pot not cooked yet.
    await _openWeek(tester);
    await stepWeek(tester, 1);
    await openPickerOn(tester, 'Thursday');
    final potDay = dateIn(thisWeek, cookDay);
    final cooks = 'cooks ${leftoverDay(potDay, smokeToday(), kSmokeShape)}';
    final offer = find.textContaining(cooks);
    await pumpUntilFound(tester, offer);
    await tester.tap(offer.first);
    await pumpUntilFound(tester, find.text('Add to plan'));
    await tester.ensureVisible(_add('Thursday'));
    await tester.pumpAndSettle();
    await tester.tap(_add('Thursday'));
    await pumpUntilGone(tester, find.text('Add to plan'));

    // One cooking holds both meals.
    final nextKey = isoDate(weekStartFrom(1));
    await waitForDb(tester, () async {
      final meals = await _meals(stack, recipe);
      final next = meals.where((r) => r['week'] == nextKey).toList();
      final mine = meals.where((r) => r['id'] == ragu).toList();
      return meals.length == 2 &&
          next.length == 1 &&
          next.single['day_of_week'] == 3 &&
          next.single['cooking'] != null &&
          mine.single['cooking'] == next.single['cooking'];
    }, 'the pick and its pot in one cooking');

    // Next week's Cook: one line, from the freezer, nothing to cook.
    await tapTab(tester, FLucideIcons.cookingPot);
    await pumpUntilFound(tester, find.byKey(CookView.rootKey));
    await pumpUntilFound(tester, find.text('$title · Thu · from the freezer'));

    // Next week's Shop: nothing for it.
    await tapTab(tester, FLucideIcons.shoppingBasket);
    await pumpUntilFound(tester, find.byKey(ShoppingView.rootKey));
    await pumpUntilFound(tester, find.text('nothing to buy'));
    expect(find.text(ingredient), findsNothing);

    // This week's Shop buys it, once: one cooking is one session, so its
    // line is the title alone (`· cook <day>` names a dish cooked twice).
    await stepWeek(tester, -1);
    await pumpUntilFound(tester, find.text(ingredient));
    final walnuts = await db.get(
      'SELECT id FROM ingredient WHERE canonical_name = ? '
      'AND deleted_at IS NULL',
      [ingredient],
    );
    final chevron = find.byKey(shopChevronTargetKey(walnuts['id']! as String));
    await pumpUntilFound(tester, chevron);
    await tester.tap(chevron);
    await tester.pumpAndSettle();
    expect(find.text(title), findsOneWidget);
    expect(find.textContaining('$title · cook'), findsNothing);
  });
}
