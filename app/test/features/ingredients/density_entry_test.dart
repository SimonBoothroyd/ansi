/// The *Units & measures* section's density block as a piece of LAYOUT
/// (exec plan 0036, Front C) — the one part of this feature whose contract is
/// measured in points rather than in what it stores.
///
/// The fonts are real here (`loadAnsiFonts`): under the test binding's square
/// fallback face the sentence measures half again as wide as it draws on a
/// phone, so a run-count assertion made without them says nothing about the
/// app.
library;

import 'package:ansi/core/units/units.dart';
import 'package:ansi/features/ingredients/presentation/density_entry.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:forui/forui.dart';

import '../../helpers/fonts.dart';
import '../../helpers/forui_semantics.dart';
import '_form_harness.dart';

/// The controls and words that make up `[1] [tbsp] weighs [__] g [Add]`. The
/// sentence takes an amount on its left now — a pack prints "2 tbsp (32 g)"
/// — so the run it has to fit at 402 pt is one field wider than it was.
List<Finder> _sentenceParts() => [
  find.byKey(const ValueKey('density-amount')),
  find.widgetWithText(AnsiModeChip, 'tsp'),
  find.widgetWithText(AnsiModeChip, 'tbsp'),
  find.widgetWithText(AnsiModeChip, 'cup'),
  find.widgetWithText(AnsiModeChip, 'ml'),
  find.text('weighs'),
  find.byKey(const ValueKey('density-grams')),
  find.text('g'),
  find.descendant(
    of: find.byType(DensityEntry),
    matching: find.byType(FButton),
  ),
];

void main() {
  setUpAll(loadAnsiFonts);

  group('C-D2 — the density sentence is one row at 402 pt', () {
    testWidgets('every part of it sits on the same run', (tester) async {
      filterForuiSemanticsAssertions();
      phoneWidth(tester);
      await tester.pumpWidget(densityHost(curryLeaves));
      await tester.pumpAndSettle();

      final rects = [
        for (final part in _sentenceParts()) tester.getRect(part.first),
      ];
      // One run means every part overlaps every other vertically: a Wrap that
      // broke would put the field and the button a run-height below the words.
      final top = rects.map((r) => r.top).reduce((a, b) => a > b ? a : b);
      final bottom = rects.map((r) => r.bottom).reduce((a, b) => a < b ? a : b);
      expect(
        top < bottom,
        isTrue,
        reason:
            'the density sentence broke onto more than one row at 402 pt: '
            '${rects.map((r) => '${r.top.toStringAsFixed(1)}..'
                '${r.bottom.toStringAsFixed(1)}').join(', ')}',
      );

      // And it does it inside the width, not by overflowing it.
      final wrap = find.descendant(
        of: find.byType(DensityEntry),
        matching: find.byType(Wrap),
      );
      final available = tester.getRect(wrap);
      expect(rects.last.right, lessThanOrEqualTo(available.right));
      expect(tester.takeException(), isNull);
    });

    testWidgets('the longest label ("Save", the quantity sheet’s) still fits', (
      tester,
    ) async {
      filterForuiSemanticsAssertions();
      phoneWidth(tester);
      await tester.pumpWidget(densityHost(curryLeaves, saveLabel: 'Save'));
      await tester.pumpAndSettle();

      final wrap = find.descendant(
        of: find.byType(DensityEntry),
        matching: find.byType(Wrap),
      );
      // A single run: the Wrap is exactly one child tall.
      expect(tester.getSize(wrap).height, lessThan(40));
      expect(tester.takeException(), isNull);
    });
  });

  group('the sentence takes an amount', () {
    test('the stored number is the line divided by its own amount', () {
      // A jar prints "2 tbsp (32 g)". That is 1.08 g/ml, and it is typed as
      // it reads rather than halved in somebody's head.
      expect(densityForAmount(2, tbsp, 32), closeTo(16 / 14.78676478125, 1e-9));
      // One of the spoon is the same arithmetic, unchanged.
      expect(densityForAmount(1, tbsp, 15), densityFromVolumeWeight(tbsp, 15));
      // `ml`'s ratio to base is 1, so "1 ml weighs 0.66 g" IS 0.66 g/ml.
      expect(densityForAmount(1, ml, 0.66), 0.66);
    });

    test('refuses what would fabricate a number (invariant 3)', () {
      expect(densityForAmount(0, tbsp, 32), isNull);
      expect(densityForAmount(2, tbsp, 0), isNull);
      expect(densityForAmount(double.nan, tbsp, 32), isNull);
      expect(densityForAmount(2, g, 32), isNull, reason: 'not a volume');
    });

    testWidgets('the amount and unit are offered from the form’s serving, and '
        'the g/ml is the aside', (tester) async {
      filterForuiSemanticsAssertions();
      phoneWidth(tester);
      await tester.pumpWidget(
        densityHost(curryLeaves, servingPrefill: (amount: 2.0, unit: tbsp)),
      );
      await tester.pumpAndSettle();

      expect(fieldText(tester, densityAmountField), '2');
      expect(
        tester
            .widget<AnsiModeChip>(find.widgetWithText(AnsiModeChip, 'tbsp'))
            .selected,
        isTrue,
      );
      expect(
        find.text('the serving you typed above · the pack’s “(32g)” goes here'),
        findsOneWidget,
      );

      await tester.enterText(densityField, '32');
      await tester.pumpAndSettle();
      expect(find.text('= 1.08 g/ml'), findsOneWidget);
    });

    testWidgets('a mass serving offers nothing new — what a millilitre of it '
        'weighs is a separate fact', (tester) async {
      filterForuiSemanticsAssertions();
      phoneWidth(tester);
      await tester.pumpWidget(densityHost(curryLeaves));
      await tester.pumpAndSettle();

      expect(fieldText(tester, densityAmountField), '1');
      expect(find.textContaining('the serving you typed above'), findsNothing);
    });
  });

  group('C-D1 — DENSITY leads like every other label in the group', () {
    testWidgets('the headline carries the form’s micro-label leading space', (
      tester,
    ) async {
      filterForuiSemanticsAssertions();
      phoneWidth(tester);
      await tester.pumpWidget(densityHost(curryLeaves));
      await tester.pumpAndSettle();

      final entry = tester.getRect(find.byType(DensityEntry));
      final headline = tester.getRect(find.text('DENSITY'));
      expect(
        headline.top - entry.top,
        20,
        reason: 'DENSITY used to butt straight against the admission chips',
      );
    });
  });

  group('C-D3 — a stated density folds', () {
    testWidgets('a row that has one shows the number and a way back in', (
      tester,
    ) async {
      filterForuiSemanticsAssertions();
      phoneWidth(tester);
      await tester.pumpWidget(densityHost(mango));
      await tester.pumpAndSettle();

      expect(find.text('0.66 g/ml'), findsOneWidget);
      expect(find.text('· change'), findsOneWidget);
      // The sentence is not the everyday height of this section.
      expect(find.text('weighs'), findsNothing);
      expect(find.text('remove the density'), findsNothing);

      await tester.tap(find.text('· change'));
      await tester.pumpAndSettle();
      expect(find.text('weighs'), findsOneWidget);
      expect(find.text('remove the density'), findsOneWidget);
      expect(find.text('· change'), findsNothing);
    });

    testWidgets('a row with no density opens on the sentence', (tester) async {
      filterForuiSemanticsAssertions();
      phoneWidth(tester);
      await tester.pumpWidget(densityHost(curryLeaves));
      await tester.pumpAndSettle();

      expect(find.text('none yet — unlocks volume⇄weight'), findsOneWidget);
      expect(find.text('weighs'), findsOneWidget);
      expect(find.text('· change'), findsNothing);
    });

    testWidgets('a number landed in this visit does NOT fold under your '
        'hands — the fold is where the section opens', (tester) async {
      filterForuiSemanticsAssertions();
      phoneWidth(tester);
      // The host stands in for the real one: it reports the write landed and
      // the row it draws is the one that now carries the number.
      await tester.pumpWidget(densityHost(curryLeaves, landsAs: mango));
      await tester.pumpAndSettle();

      await tester.enterText(densityField, '0.66');
      await tester.pump();
      await tester.tap(
        find.descendant(
          of: find.byType(DensityEntry),
          matching: find.byType(FButton),
        ),
      );
      await tester.pumpAndSettle();

      // The headline follows the row, the sentence stays where the typing
      // was, and the affordance the number unlocks joins it.
      expect(find.text('0.66 g/ml'), findsOneWidget);
      expect(find.text('weighs'), findsOneWidget);
      expect(find.text('remove the density'), findsOneWidget);
      expect(find.text('· change'), findsNothing);
    });

    testWidgets('removing the number puts the sentence back', (tester) async {
      filterForuiSemanticsAssertions();
      phoneWidth(tester);
      await tester.pumpWidget(densityHost(mango, landsAs: mango));
      await tester.pumpAndSettle();

      await tester.tap(find.text('· change'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('remove the density'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FButton, 'Remove'));
      await tester.pumpAndSettle();

      // The host's row goes back to the one it started with — which here
      // still carries a density, so the point being pinned is the entry's own
      // state: a removal leaves you looking at the sentence, never at a
      // folded line with nothing behind it.
      expect(find.text('weighs'), findsOneWidget);
    });
  });
}
