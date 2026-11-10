/// Driving the leftovers model (plans 0061/0062) on a device: a dish seeded
/// through the app's own repository, meals planned and ticked through the
/// planning repository (the same writes the sheets make), the Week's meal
/// sheet, the week switcher, and the Leftovers page's rows.
///
/// Dates are the real today's, placed through the household's week shape
/// (Monday, the onboarding default), so every scenario holds on any weekday.
library;

import 'package:ansi/core/units/units.dart' show g;
import 'package:ansi/core/week_shape.dart';
import 'package:ansi/features/cook_plan/data/leftover_repository_impl.dart';
import 'package:ansi/features/cook_plan/domain/cooking.dart' show LeftoverPlace;
import 'package:ansi/features/cook_plan/domain/leftovers.dart' show Leftover;
import 'package:ansi/features/cook_plan/presentation/leftovers_view.dart'
    show LeftoversDoor;
import 'package:ansi/features/planning/data/planning_repository_impl.dart';
import 'package:ansi/features/planning/presentation/meal_eaten_row.dart'
    show MealEatenRow;
import 'package:ansi/features/planning/presentation/week_header.dart'
    show WeekSwitcher;
import 'package:ansi/features/planning/presentation/week_widgets.dart'
    show EaterAvatarStack;
import 'package:ansi/features/recipes/data/recipe_repository_impl.dart';
import 'package:ansi/features/recipes/domain/recipe.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:forui/forui.dart';
import 'package:powersync/powersync.dart' hide Column;
import 'package:uuid/uuid.dart';

import 'drive.dart';
import 'stack.dart';
import 'week.dart';

const _uuid = Uuid();

/// The household's week shape: onboarding's default, Monday first.
const kSmokeShape = WeekShape.monday;

/// Today, date only, local.
DateTime smokeToday() {
  final now = DateTime.now();
  return DateTime(now.year, now.month, now.day);
}

/// Today's place in its week, 0..6.
int todayOffset() => kSmokeShape.offsetOf(smokeToday());

/// The first day of the week [weeks] from this one (UTC date, as the app
/// addresses weeks): 0 this week, -1 last week, 1 next.
DateTime weekStartFrom(int weeks) =>
    kSmokeShape.weekStartOf(DateTime.now()).add(Duration(days: 7 * weeks));

/// The local date of [day] in the week beginning [weekStart].
DateTime dateIn(DateTime weekStart, int day) =>
    DateTime(weekStart.year, weekStart.month, weekStart.day + day);

/// [day] plus [days], by the calendar (the app's own arithmetic).
DateTime plusDays(DateTime day, int days) =>
    DateTime(day.year, day.month, day.day + days);

/// The full weekday name the Week's day card is headed with.
String dayName(int day) => kSmokeShape.labelFull(day);

/// Ada's and Jun's member ids, by name.
Future<({String ada, String jun})> smokeMembers(PowerSyncDatabase db) async {
  final rows = await db.getAll(
    'SELECT id, display_name FROM household_member WHERE deleted_at IS NULL',
  );
  String idOf(String name) =>
      rows.firstWhere((r) => r['display_name'] == name)['id']! as String;
  return (ada: idOf('Ada'), jun: idOf('Jun'));
}

/// A dish of one weighed line of [ingredient] (a seed vocab row, so the line
/// reaches the shop), filed in the default book. Returns its id.
Future<String> seedDish(
  WidgetTester tester,
  SmokeStack stack, {
  required String title,
  required String ingredient,
  double servings = 2,
  int? keepsForDays,
  bool freezable = false,
  int? freezerDays,
}) async {
  final db = stack.db;
  // The vocab arrives with the first sync; wait for the row named.
  await waitForDb(
    tester,
    () async =>
        (await db.getOptional(
          'SELECT id FROM ingredient WHERE canonical_name = ? '
          'AND deleted_at IS NULL',
          [ingredient],
        )) !=
        null,
    'the $ingredient vocab row',
  );
  final row = await db.get(
    'SELECT id FROM ingredient WHERE canonical_name = ? '
    'AND deleted_at IS NULL LIMIT 1',
    [ingredient],
  );
  final book = await db.get(
    'SELECT id FROM book WHERE deleted_at IS NULL '
    'ORDER BY sort_order, created_at LIMIT 1',
  );
  final id = _uuid.v4();
  await SqliteRecipeRepository(db, householdId: stack.householdId).saveRecipe(
    Recipe(
      id: id,
      title: title,
      servingsBase: servings,
      keepsForDays: keepsForDays,
      freezable: freezable,
      freezerDays: freezerDays,
      bookId: book['id'] as String,
      groups: [
        IngredientGroup(
          id: _uuid.v4(),
          items: [
            LineItem(
              id: _uuid.v4(),
              ingredientId: row['id'] as String,
              ingredientName: ingredient,
              unit: g,
              quantity: 100 * servings,
            ),
          ],
        ),
      ],
    ),
  );
  return id;
}

/// The planning repository over the throwaway database, as the app builds
/// it: its writes are the sheets' writes.
SqlitePlanningRepository planningOf(SmokeStack stack) =>
    SqlitePlanningRepository(stack.db, householdId: stack.householdId);

/// Plans [recipeId] on [day] of the week beginning [weekStart].
Future<String> planMeal(
  SmokeStack stack, {
  required DateTime weekStart,
  required int day,
  required String recipeId,
  required List<String> eaters,
  int? portions,
  String slot = 'Dinner',
}) => planningOf(stack).addEntry(
  weekStart: weekStart,
  dayOfWeek: day,
  mealSlot: slot,
  recipeId: recipeId,
  eaterIds: eaters,
  portions: portions,
);

/// Ticks [entryId] for [memberId] (the member signed in here: Ada) through
/// the repository — the write the meal sheet's *Ate this* makes, births
/// included — at 19:00 on [mealDay]; a null [mealDay] unticks.
Future<void> tickAsAda(
  SmokeStack stack,
  String entryId, {
  required String memberId,
  required DateTime? mealDay,
}) => planningOf(stack).setMealEaten(
  entryId,
  memberId: memberId,
  eatenAt: mealDay == null
      ? null
      : DateTime(mealDay.year, mealDay.month, mealDay.day, 19),
);

/// The cooking [entryId] is linked to, once it has one.
Future<String> waitForCooking(
  WidgetTester tester,
  PowerSyncDatabase db,
  String entryId,
) async {
  String? cooking;
  await waitForDb(tester, () async {
    final row = await db.getOptional(
      'SELECT cooking FROM plan_entry WHERE id = ?',
      [entryId],
    );
    cooking = row?['cooking'] as String?;
    return cooking != null;
  }, 'the meal to be in a cooking');
  return cooking!;
}

/// Waits for Jun's live tick on [entryId] to sync down.
Future<void> waitForPartnerTick(
  WidgetTester tester,
  PowerSyncDatabase db,
  String entryId,
  String junId,
) => waitForDb(
  tester,
  () async =>
      (await db.getOptional(
        'SELECT id FROM meal_eaten WHERE plan_entry_id = ? AND member_id = ? '
        'AND deleted_at IS NULL',
        [entryId, junId],
      )) !=
      null,
  "Jun's tick to sync down",
  timeout: const Duration(seconds: 60),
);

// --- The Week ---------------------------------------------------------------

/// Steps the week switcher [by] weeks (Week, Cook and Shop share it).
Future<void> stepWeek(WidgetTester tester, int by) async {
  // The switcher's own chevrons: the Shop's empty line draws one too.
  final chevron = find.descendant(
    of: find.byType(WeekSwitcher),
    matching: find.byIcon(
      by < 0 ? FLucideIcons.chevronLeft : FLucideIcons.chevronRight,
    ),
  );
  for (var i = 0; i < by.abs(); i++) {
    await tester.tap(chevron.first);
    await tester.pumpAndSettle();
  }
}

/// [title]'s dish row on [day]'s card: the nearest Column above its title.
Finder dishRow(String day, String title) => find
    .ancestor(
      of: find.descendant(of: dayCard(day), matching: find.text(title)).first,
      matching: find.byType(Column),
    )
    .first;

/// Scrolls the Week to [day] and waits for [title]'s row on it.
Future<Finder> showDish(WidgetTester tester, String day, String title) async {
  await scrollTo(tester, find.text(day));
  await pumpUntilFound(
    tester,
    find.descendant(of: dayCard(day), matching: find.text(title)),
  );
  final row = dishRow(day, title);
  await tester.ensureVisible(row);
  await tester.pumpAndSettle();
  return row;
}

/// Opens [title]'s meal sheet on [day] from the avatars that draw its
/// eaters (the title opens the recipe).
Future<void> openMealSheet(
  WidgetTester tester,
  String day,
  String title,
) async {
  final row = await showDish(tester, day, title);
  final avatars = find.descendant(
    of: row,
    matching: find.byType(EaterAvatarStack),
  );
  await tester.ensureVisible(avatars);
  await tester.pumpAndSettle();
  await tester.tap(avatars);
  await pumpUntilFound(tester, find.byType(MealEatenRow));
}

/// *Ate this* on the open sheet, waiting for the answer's `×` to show it
/// landed.
Future<void> tickInSheet(WidgetTester tester) async {
  await tester.tap(
    find.descendant(
      of: find.byType(MealEatenRow),
      matching: find.text('Ate this'),
    ),
  );
  await pumpUntilFound(
    tester,
    find.descendant(
      of: find.byType(MealEatenRow),
      matching: find.byIcon(FLucideIcons.x),
    ),
  );
}

/// The answer's `×` (*Not eaten*) on the open sheet, waiting for the
/// question to come back.
Future<void> untickInSheet(WidgetTester tester) async {
  await tester.tap(
    find.descendant(
      of: find.byType(MealEatenRow),
      matching: find.byIcon(FLucideIcons.x),
    ),
  );
  await pumpUntilFound(
    tester,
    find.descendant(
      of: find.byType(MealEatenRow),
      matching: find.text('Something else'),
    ),
  );
}

/// Dismisses the open meal sheet.
Future<void> closeSheet(WidgetTester tester) async {
  await tester.tap(find.text('Close').last);
  await tester.pumpAndSettle();
}

/// Opens [day]'s add door and the recipe picker on it.
Future<void> openPickerOn(WidgetTester tester, String day) async {
  await scrollTo(tester, find.text(day));
  final add = find.descendant(
    of: dayCard(day),
    matching: find.byWidgetPredicate(
      (w) =>
          w is Text && (w.data == 'add a meal' || w.data == 'nothing planned'),
    ),
  );
  await tester.ensureVisible(add);
  await tester.pumpAndSettle();
  await tester.tap(add);
  await pumpUntilFound(tester, find.text('Add a meal'));
}

// --- Leftovers --------------------------------------------------------------

/// Opens the Leftovers page from the fridge in the Week's header.
Future<void> openLeftovers(WidgetTester tester) async {
  await tester.tap(find.byType(LeftoversDoor));
  await pumpUntilFound(tester, find.text('FRIDGE'));
}

/// The Leftovers page's row for [cooking] on its [shelf] (`fridge` or
/// `freezer`): the page keys each row by cooking and shelf.
Finder leftoverRow(String cooking, {String shelf = 'fridge'}) =>
    find.byKey(ValueKey('$cooking:$shelf'));

/// [cooking]'s row on [place] as the Leftovers page reads it today, through
/// the page's own reader, or null when the page lists none.
Future<Leftover?> readLeftover(
  SmokeStack stack,
  String cooking, {
  LeftoverPlace place = LeftoverPlace.fridge,
}) async {
  final shelves = await SqliteLeftoverRepository(
    stack.db,
    householdId: stack.householdId,
  ).watchHouseholdLeftovers(today: smokeToday()).first;
  return shelves.rows
      .where((l) => l.id == cooking && l.place == place)
      .firstOrNull;
}

/// Waits a few seconds for [row] to be built (its read is a live query), then
/// scrolls the page's list for it: a page of many rows builds only those near
/// the viewport.
Future<void> revealLeftover(WidgetTester tester, Finder row) async {
  final deadline = DateTime.now().add(const Duration(seconds: 5));
  while (row.evaluate().isEmpty && DateTime.now().isBefore(deadline)) {
    await tester.pump(const Duration(milliseconds: 100));
  }
  if (row.evaluate().isEmpty) await scrollTo(tester, row);
}

/// Waits for [cooking]'s row on [shelf] to read [text] (`2 left`,
/// `till Mon`), scrolling it into view.
Future<void> expectLeftover(
  WidgetTester tester,
  String cooking,
  String text, {
  String shelf = 'fridge',
}) async {
  final row = leftoverRow(cooking, shelf: shelf);
  await revealLeftover(tester, row);
  await tester.ensureVisible(row);
  await tester.pumpAndSettle();
  await pumpUntilFound(
    tester,
    find.descendant(of: row, matching: find.text(text)),
  );
}
