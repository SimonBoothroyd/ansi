import 'package:ansi/core/week_shape.dart';
import 'package:ansi/features/account/data/household_providers.dart';
import 'package:ansi/features/planning/presentation/meal_fields.dart';
import 'package:ansi/features/recipes/domain/recipe.dart';
import 'package:ansi/shared/week_strip.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/pump_app.dart';

const _curry = RecipeSummary(
  id: 'r1',
  title: 'Weeknight Chicken Curry',
  servingsBase: 4,
  keepsForDays: 3,
  freezable: true,
);

Future<WeekStrip?> _pump(
  WidgetTester tester, {
  required List<int> planned,
  required int newDay,
}) async {
  await tester.pumpApp(
    MealBatchStrip(recipe: _curry, plannedDays: planned, newDay: newDay),
    overrides: [weekShapeProvider.overrideWithValue(WeekShape.monday)],
  );
  final found = find.byType(WeekStrip);
  return found.evaluate().isEmpty ? null : tester.widget<WeekStrip>(found);
}

void main() {
  testWidgets('a meal inside the window is outlined in the batch it joins', (
    tester,
  ) async {
    final strip = await _pump(tester, planned: [0], newDay: 2);
    expect(strip!.size, WeekStripSize.full);
    expect([for (final d in strip.days) d.fill].take(5), [
      WeekStripFill.cooked,
      WeekStripFill.keeps,
      WeekStripFill.keeps,
      WeekStripFill.keeps,
      WeekStripFill.gone,
    ]);
    // Monday already eats from it; Wednesday is the one being added.
    expect(strip.days[0].eats, isTrue);
    expect(strip.days[2].eats, isFalse);
    expect(strip.days[2].thisMeal, isTrue);
    expect(find.text('from Monday’s batch'), findsOneWidget);
  });

  testWidgets('a far meal on a freezable dish lands on a freezer day', (
    tester,
  ) async {
    final strip = await _pump(tester, planned: [0], newDay: 5);
    expect(strip!.days[5].fill, WeekStripFill.frozen);
    expect(strip.days[5].thisMeal, isTrue);
    expect(find.text('from Monday’s batch, frozen'), findsOneWidget);
  });

  testWidgets('on the cook day itself the strip has no caption', (
    tester,
  ) async {
    final strip = await _pump(tester, planned: [3], newDay: 1);
    expect(strip!.days[1].fill, WeekStripFill.cooked);
    expect(strip.days[1].thisMeal, isTrue);
    expect(strip.caption, isNull);
  });

  testWidgets('nothing planned draws nothing', (tester) async {
    expect(await _pump(tester, planned: [], newDay: 1), isNull);
  });
}
