/// Driving the Week tab: a day's card, its one add door, and the two-step
/// add flow that puts a recipe on a day.
///
/// There are no mode helpers any more — week v3 (E1) deleted the mode, so
/// `enterWeekEditMode` / `leaveWeekEditMode` have nothing to enter or leave.
library;

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import 'drive.dart';

/// 'YYYY-MM-DD' — the key `week_plan.week_start_date` is addressed by.
String isoDate(DateTime d) =>
    '${d.year}-${d.month.toString().padLeft(2, '0')}-'
    '${d.day.toString().padLeft(2, '0')}';

/// The Week grid card for a full weekday name (nearest enclosing Column).
Finder dayCard(String day) =>
    find.ancestor(of: find.text(day), matching: find.byType(Column)).first;

/// Opens the recipe picker from [day]'s card and places [recipe] on it
/// through the two-step flow, leaving the confirm sheet's defaults alone.
Future<void> addMealOn(WidgetTester tester, String day, String recipe) async {
  await scrollTo(tester, find.text(day));
  // E5: every day card carries the same add line, in one of two wordings —
  // `add a meal` once the day has meals, `nothing planned` while it has none.
  final add = find.descendant(
    of: dayCard(day),
    matching: find.byWidgetPredicate(
      (w) =>
          w is Text &&
          (w.data == 'add a meal' || w.data == 'nothing planned'),
    ),
  );
  await tester.ensureVisible(add);
  await tester.pumpAndSettle();
  await tester.tap(add);
  await tester.pumpAndSettle();
  // `.last`: the sheet renders after the week grid, whose rows can carry the
  // same title text (the tap must land on the overlay, not under it).
  await tester.tap(find.text(recipe).last);
  await tester.pumpAndSettle();
  await tester.tap(find.text('Add to $day'));
  await tester.pumpAndSettle();
}
