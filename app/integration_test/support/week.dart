/// Driving the Week tab: its two modes, a day's card, and the two-step add
/// flow that puts a recipe on a day.
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

/// The Week rests in PRESENTATION mode since the redesign (D1), and its add
/// doors only exist in edit mode. Idempotent: a no-op when already editing
/// (the header then reads `Done`, not `Edit`).
Future<void> enterWeekEditMode(WidgetTester tester) async {
  final edit = find.text('Edit');
  if (edit.evaluate().isEmpty) return;
  await tester.tap(edit);
  await tester.pumpAndSettle();
}

/// Back to the resting state.
Future<void> leaveWeekEditMode(WidgetTester tester) async {
  final done = find.text('Done');
  if (done.evaluate().isEmpty) return;
  await tester.tap(done);
  await tester.pumpAndSettle();
}

/// Opens the recipe picker from [day]'s card and places [recipe] on it
/// through the two-step flow, leaving the confirm sheet's defaults alone.
Future<void> addMealOn(WidgetTester tester, String day, String recipe) async {
  await enterWeekEditMode(tester);
  await scrollTo(tester, find.text(day));
  final add = find.descendant(
    of: dayCard(day),
    matching: find.text('Add a meal'),
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
