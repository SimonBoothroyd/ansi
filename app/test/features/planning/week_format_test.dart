import 'package:ansi/features/cook_plan/domain/cook_plan.dart';
import 'package:ansi/features/planning/presentation/week_format.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final today = DateTime.utc(2026, 8, 27);

  group('the cook marker (D6) — a read of the cook plan', () {
    /// One recipe planned on [days], all Dinner, 2 portions each.
    CookPlan planFor(
      List<int> days, {
      int? keepsForDays = 4,
      bool freezable = false,
      int? freezerDays,
    }) => buildCookPlan([
      PlannedRecipe(
        recipeId: 'r1',
        title: 'Curry',
        servingsBase: 2,
        keepsForDays: keepsForDays,
        freezable: freezable,
        freezerDays: freezerDays,
        meals: [
          for (final d in days)
            CoveredMeal(dayOfWeek: d, mealSlot: 'Dinner', portions: 2),
        ],
      ),
    ]);

    CookMarker? markerOn(CookPlan plan, int day) =>
        cookMarkerFor(plan, recipeId: 'r1', dayOfWeek: day, mealSlot: 'Dinner');

    test('a single-meal cook gets NO marker — the row stays one line', () {
      expect(markerOn(planFor([0]), 0), isNull);
    });

    test('the cook day names the batch it is cooking', () {
      final marker = markerOn(planFor([0, 2]), 0)!;
      expect(marker.kind, CookMarkerKind.cooks);
      expect(marker.cookDay, 0);
      expect(marker.batchPortions, 4); // 2 + 2 across the session
      expect(marker.position, 0);
      expect(
        cookMarkerLabel(marker, todayDayOfWeek: 0),
        'cooks today · batch of 4',
      );
      // Another week is on screen, so "today" is not available.
      expect(cookMarkerLabel(marker), 'cooks Mon · batch of 4');
      // The current week, but a different day.
      expect(
        cookMarkerLabel(marker, todayDayOfWeek: 4),
        'cooks Mon · batch of 4',
      );
    });

    test('a covered day says where it came from, and how far through', () {
      final marker = markerOn(planFor([0, 2]), 2)!;
      expect(marker.kind, CookMarkerKind.fromBatch);
      expect(marker.cookDay, 0);
      expect(marker.position, 0.5); // day 2 of a 4-day window
      expect(cookMarkerLabel(marker), 'from Monday\u2019s batch');
    });

    test('a day past the fridge window is a freezer share', () {
      // Keeps 2 days, freezable: Thursday is out of the fridge window but the
      // freezer reaches it, so it is ONE session with a frozen day.
      final marker = markerOn(
        planFor([0, 3], keepsForDays: 2, freezable: true),
        3,
      )!;
      expect(marker.kind, CookMarkerKind.freezerShare);
      expect(cookMarkerLabel(marker), 'Monday\u2019s freezer share');
    });

    test('a recipe with no shelf life has no window, so no position', () {
      final marker = markerOn(planFor([0, 5], keepsForDays: null), 5)!;
      expect(marker.kind, CookMarkerKind.fromBatch);
      // An unknown window is not a full one — never a "gone" notch invented
      // out of a missing fact.
      expect(marker.position, 0);
    });

    test('a meal the plan does not cover has no marker', () {
      expect(
        cookMarkerFor(
          planFor([0, 2]),
          recipeId: 'other',
          dayOfWeek: 0,
          mealSlot: 'Dinner',
        ),
        isNull,
      );
      // Same recipe, same day, a slot the session does not cover.
      expect(
        cookMarkerFor(
          planFor([0, 2]),
          recipeId: 'r1',
          dayOfWeek: 0,
          mealSlot: 'Lunch',
        ),
        isNull,
      );
    });

    test('two sessions: each meal reads off its OWN batch', () {
      // Keeps 2 days, not freezable → Mon and Sat are separate cooks, and
      // neither covers more than one meal, so neither says anything.
      final plan = planFor([0, 5], keepsForDays: 2);
      expect(markerOn(plan, 0), isNull);
      expect(markerOn(plan, 5), isNull);

      // Add a Tuesday: now Monday's session covers two meals and Saturday's
      // still covers one.
      final split = planFor([0, 1, 5], keepsForDays: 2);
      expect(markerOn(split, 0)!.kind, CookMarkerKind.cooks);
      expect(markerOn(split, 1)!.cookDay, 0);
      expect(markerOn(split, 5), isNull);
    });
  });

  group('formatWeekTitle (D2 — the week is a position)', () {
    // today is Thursday 27 Aug 2026; this week's Monday is 24 Aug.
    test('names the three weeks around today, with the date', () {
      expect(formatWeekTitle(DateTime.utc(2026, 8, 24), today), (
        label: 'This week',
        date: '24 Aug',
        isThisWeek: true,
      ));
      expect(formatWeekTitle(DateTime.utc(2026, 8, 31), today), (
        label: 'Next week',
        date: '31 Aug',
        isThisWeek: false,
      ));
      expect(formatWeekTitle(DateTime.utc(2026, 8, 17), today), (
        label: 'Last week',
        date: '17 Aug',
        isThisWeek: false,
      ));
    });

    test('falls back to "Week of <date>" beyond the named three', () {
      expect(formatWeekTitle(DateTime.utc(2026, 9, 14), today), (
        label: 'Week of 14 Sep',
        date: null,
        isThisWeek: false,
      ));
      expect(formatWeekTitle(DateTime.utc(2026, 8, 10), today), (
        label: 'Week of 10 Aug',
        date: null,
        isThisWeek: false,
      ));
    });

    test('any day of a week names that week — only the Monday matters', () {
      for (final d in [24, 25, 26, 27, 28, 29, 30]) {
        expect(
          formatWeekTitle(DateTime.utc(2026, 8, d), today).label,
          'This week',
        );
      }
    });

    test('only this week carries the herb dot', () {
      expect(
        formatWeekTitle(DateTime.utc(2026, 8, 24), today).isThisWeek,
        isTrue,
      );
      expect(
        formatWeekTitle(DateTime.utc(2026, 8, 31), today).isThisWeek,
        isFalse,
      );
    });
  });

  group('formatDerivedWeekSuffix (D3 — Cook and Shop say which week)', () {
    test('is null on the current week — the header stays the screen name', () {
      expect(formatDerivedWeekSuffix(DateTime.utc(2026, 8, 24), today), isNull);
    });

    test('lowers only the leading word', () {
      expect(
        formatDerivedWeekSuffix(DateTime.utc(2026, 8, 31), today),
        'next week',
      );
      expect(
        formatDerivedWeekSuffix(DateTime.utc(2026, 8, 17), today),
        'last week',
      );
      expect(
        formatDerivedWeekSuffix(DateTime.utc(2026, 9, 14), today),
        'week of 14 Sep',
      );
    });
  });

  group('formatDayDate', () {
    test('walks the week from its Monday', () {
      final monday = DateTime.utc(2026, 8, 31);
      expect(formatDayDate(monday, 0), '31 Aug');
      expect(formatDayDate(monday, 2), '2 Sep');
      expect(formatDayDate(monday, 6), '6 Sep');
    });
  });

  group('formatLastPlanned (7.7 picker recency)', () {
    test('same day is today', () {
      expect(formatLastPlanned(DateTime.utc(2026, 8, 27), today), 'today');
    });

    test('under a week is in days', () {
      expect(formatLastPlanned(DateTime.utc(2026, 8, 24), today), '3d ago');
      expect(formatLastPlanned(DateTime.utc(2026, 8, 21), today), '6d ago');
    });

    test('under four weeks is in weeks', () {
      expect(formatLastPlanned(DateTime.utc(2026, 8, 13), today), '2w ago');
      expect(formatLastPlanned(DateTime.utc(2026, 8, 6), today), '3w ago');
    });

    test('further back is in months, never 0mo', () {
      expect(formatLastPlanned(DateTime.utc(2026, 7, 29), today), '1mo ago');
      expect(formatLastPlanned(DateTime.utc(2026, 5, 27), today), '3mo ago');
    });

    test('a meal planned ahead reads as upcoming, honestly scaled', () {
      // The old label called ANY future date "this week" — wrong for next
      // month's plan.
      expect(formatLastPlanned(DateTime.utc(2026, 8, 29), today), 'in 2d');
      expect(formatLastPlanned(DateTime.utc(2026, 9, 2), today), 'in 6d');
      expect(formatLastPlanned(DateTime.utc(2026, 9, 17), today), 'in 3w');
      expect(formatLastPlanned(DateTime.utc(2026, 10, 27), today), 'in 2mo');
    });
  });

  group("formatMealCount (the Week's menu row, in its own words)", () {
    test('counts meals, and calls an empty week empty', () {
      expect(formatMealCount(0), 'empty');
      expect(formatMealCount(1), '1 meal');
      expect(formatMealCount(9), '9 meals');
    });
  });
}
