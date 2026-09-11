/// The *Units & measures* section's density block as a piece of LAYOUT
/// (exec plan 0036, Front C) — the one part of this feature whose contract is
/// measured in points rather than in what it stores.
///
/// The fonts are real here (`loadAnsiFonts`): under the test binding's square
/// fallback face the sentence measures half again as wide as it draws on a
/// phone, so a run-count assertion made without them says nothing about the
/// app.
library;

import 'package:ansi/core/units/macros.dart';
import 'package:ansi/core/units/measure.dart';
import 'package:ansi/core/units/units.dart';
import 'package:ansi/features/ingredients/domain/ingredient.dart';
import 'package:ansi/features/ingredients/presentation/density_entry.dart';
import 'package:ansi/features/ingredients/presentation/ingredient_facts.dart';
import 'package:ansi/shared/inline_amount_field.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:forui/forui.dart';

import '../../helpers/fonts.dart';
import '../../helpers/forui_semantics.dart';
import '_form_harness.dart';

/// The controls and words that make up `[1] [tbsp] weighs [__] [g] [Add]`.
/// Both sides take an amount and a unit now — a pack prints "1/4 cup (30 g)"
/// or "30 ml (1 oz)" — so the run it has to fit at 402 pt is two pickers
/// wide, and the chips it used to spend that width on are gone.
List<Finder> _sentenceParts() => [
  find.byKey(const ValueKey('density-amount')),
  find.byKey(const ValueKey('density-amount-unit')),
  find.text('weighs'),
  find.byKey(const ValueKey('density-grams')),
  find.byKey(const ValueKey('density-grams-unit')),
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

    testWidgets('every control on the run is the same height', (tester) async {
      filterForuiSemanticsAssertions();
      phoneWidth(tester);
      await tester.pumpWidget(densityHost(curryLeaves));
      await tester.pumpAndSettle();

      // The words are as tall as the words; the CONTROLS are one height, and
      // that is what stops a sentence reading as a form.
      for (final part in [
        find.byKey(const ValueKey('density-amount')),
        find.byKey(const ValueKey('density-amount-unit')),
        find.byKey(const ValueKey('density-grams')),
        find.byKey(const ValueKey('density-grams-unit')),
        find.descendant(
          of: find.byType(DensityEntry),
          matching: find.byType(FButton),
        ),
      ]) {
        expect(
          tester.getSize(part.first).height,
          kInlineControlHeight,
          reason: part.describeMatch(Plurality.one),
        );
      }
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

  group('both sides take an amount and a unit', () {
    test('the stored number is the weight in grams over the volume in ml', () {
      // A jar prints "2 tbsp (32 g)". That is 1.08 g/ml, and it is typed as
      // it reads rather than halved in somebody's head.
      expect(
        densityForPair(2, tbsp, 32, g),
        closeTo(16 / 14.78676478125, 1e-9),
      );
      // One of the spoon is the same arithmetic, unchanged.
      expect(densityForPair(1, tbsp, 15, g), densityFromVolumeWeight(tbsp, 15));
      // `ml` and `g` both have a ratio to base of 1, so "1 ml weighs 0.66 g"
      // IS 0.66 g/ml.
      expect(densityForPair(1, ml, 0.66, g), 0.66);
    });

    test('either order, and any pair of families', () {
      // The label that prints the weight first: "30 ml weighs 1 oz".
      expect(
        densityForPair(1, oz, 30, ml),
        closeTo(densityForPair(30, ml, 1, oz)!, 1e-12),
      );
      // And a pack that prints neither side in a base unit: 1/4 cup = 30 g.
      expect(densityForPair(0.25, cup, 30, g), closeTo(30 / 59.1470591, 1e-9));
    });

    test('refuses what would fabricate a number (invariant 3)', () {
      expect(densityForPair(0, tbsp, 32, g), isNull);
      expect(densityForPair(2, tbsp, 0, g), isNull);
      expect(densityForPair(double.nan, tbsp, 32, g), isNull);
      expect(
        densityForPair(2, g, 32, kg),
        isNull,
        reason: 'two weights bridge nothing',
      );
      expect(
        densityForPair(2, cup, 32, ml),
        isNull,
        reason: 'two volumes bridge nothing',
      );
      expect(densityForPair(2, pieces, 32, g), isNull, reason: 'not a volume');
    });

    testWidgets('the amount and unit are offered from the form’s serving, and '
        'the g/ml is the aside', (tester) async {
      filterForuiSemanticsAssertions();
      phoneWidth(tester);
      await tester.pumpWidget(
        densityHost(
          curryLeaves,
          servingPrefill: (amount: 2.0, unit: tbsp, grams: null),
        ),
      );
      await tester.pumpAndSettle();

      expect(fieldText(tester, densityAmountField), '2');
      expect(
        find.descendant(
          of: find.byKey(const ValueKey('density-amount-unit')),
          matching: find.text('tbsp'),
        ),
        findsOneWidget,
      );
      expect(
        find.text(
          'your serving, ready to use — type what that much weighs '
          '(the pack’s “(32 g)”)',
        ),
        findsOneWidget,
      );

      await tester.enterText(densityField, '32');
      await tester.pumpAndSettle();
      expect(find.text('= 1.08 g/ml'), findsOneWidget);
    });

    testWidgets('a pack that printed the weight beside the spoon fills the '
        'whole sentence — and still writes nothing', (tester) async {
      filterForuiSemanticsAssertions();
      phoneWidth(tester);
      var landed = 0;
      await tester.pumpWidget(
        densityHost(
          curryLeaves,
          servingPrefill: (amount: 2.0, unit: tbsp, grams: 7.0),
          onSaved: () => landed++,
        ),
      );
      await tester.pumpAndSettle();

      // "2 tbsp weighs 7 g", as the label reads — both slots, not one.
      expect(fieldText(tester, densityAmountField), '2');
      expect(fieldText(tester, densityField), '7');
      expect(find.text('= 0.237 g/ml'), findsOneWidget);
      // The note stops pointing at an empty slot and asks for the check the
      // person is actually being asked to make.
      expect(find.textContaining('check them, then tap'), findsOneWidget);
      // An offer, not a write: the button is still the thing that lands it.
      expect(landed, 0);
      await tester.tap(find.widgetWithText(FButton, 'Add'));
      await tester.pumpAndSettle();
      expect(landed, 1);
    });

    testWidgets('a mass serving offers nothing new — what a millilitre of it '
        'weighs is a separate fact', (tester) async {
      filterForuiSemanticsAssertions();
      phoneWidth(tester);
      await tester.pumpWidget(densityHost(curryLeaves));
      await tester.pumpAndSettle();

      expect(fieldText(tester, densityAmountField), '1');
      expect(find.textContaining('your serving, ready to use'), findsNothing);
    });
  });

  group('the sentence opens in the row’s own words', () {
    // A per-100 g row whose serving is a spoon: `2 tsp` is the phrase this
    // density was entered in, and the one it has to be reopened in.
    const flakes = Ingredient(
      id: 'flakes',
      canonicalName: 'Nutritional Yeast',
      defaultUnit: g,
      status: IngredientStatus.complete,
      category: 'pantry',
      densityGPerMl: 0.66,
      macros: Macros(kcal: 385, protein: 50, carb: 36, fat: 5),
      source: 'manual',
    );
    const flakesServing = Measure(
      id: 's1',
      label: 'serving · 2 tsp',
      amount: 6.50617650375,
      source: 'manual',
    );

    // A row counted in a volume unit and stating no serving — the second leg:
    // the word a line about this row will say.
    const oil = Ingredient(
      id: 'oil',
      canonicalName: 'Olive Oil',
      defaultUnit: ml,
      status: IngredientStatus.complete,
      category: 'pantry',
      macrosBasis: MacrosBasis.perMl,
      densityGPerMl: 0.92,
      macros: Macros(kcal: 884, protein: 0, carb: 0, fat: 100),
      source: 'manual',
    );

    testWidgets('a row whose serving is a spoon reopens on that spoon, with '
        'what it weighs already in', (tester) async {
      filterForuiSemanticsAssertions();
      phoneWidth(tester);
      await tester.pumpWidget(densityHost(flakes, serving: flakesServing));
      await tester.pumpAndSettle();

      // Folded, as a stated density always opens — the sentence is behind
      // `change`, which is where this fix matters.
      await tester.tap(find.text('· change'));
      await tester.pumpAndSettle();

      expect(fieldText(tester, densityAmountField), '2');
      expect(
        find.descendant(of: densityAmountUnit, matching: find.text('tsp')),
        findsOneWidget,
      );
      // 0.66 g/ml × 4.93 ml × 2, printed as a scale reading rather than as
      // `6 1/2` — the metric split, in the slot its own picker says `g`.
      expect(fieldText(tester, densityField), '6.51');
      // And the fact sheet says the same sentence back.
      expect(
        densityFact(flakes, serving: flakesServing),
        '2 tsp weighs 6.51 g',
      );
    });

    testWidgets('a row with no serving reopens in its own default unit where '
        'that is a volume', (tester) async {
      filterForuiSemanticsAssertions();
      phoneWidth(tester);
      await tester.pumpWidget(densityHost(oil));
      await tester.pumpAndSettle();
      await tester.tap(find.text('· change'));
      await tester.pumpAndSettle();

      expect(fieldText(tester, densityAmountField), '1');
      expect(
        find.descendant(of: densityAmountUnit, matching: find.text('ml')),
        findsOneWidget,
      );
      expect(fieldText(tester, densityField), '0.92');
      // `1 ml weighs 0.92 g` IS `0.92 g/ml`, so the fact sheet carries no
      // aside repeating it.
      expect(densityFact(oil), '1 ml weighs 0.92 g');
    });

    testWidgets('a row that names neither reopens on the cup a person can '
        'picture', (tester) async {
      filterForuiSemanticsAssertions();
      phoneWidth(tester);
      // Mango is counted in pieces and states no serving: nothing on the row
      // is friendlier than the cup.
      await tester.pumpWidget(densityHost(mango));
      await tester.pumpAndSettle();
      await tester.tap(find.text('· change'));
      await tester.pumpAndSettle();

      expect(fieldText(tester, densityAmountField), '1');
      expect(
        find.descendant(of: densityAmountUnit, matching: find.text('cup')),
        findsOneWidget,
      );
      expect(fieldText(tester, densityField), '156.15');
      expect(densityFact(mango), '1 cup weighs 156.15 g · 0.66 g/ml');
    });

    testWidgets('a row with no density still opens on an empty weight — there '
        'is nothing to reopen', (tester) async {
      filterForuiSemanticsAssertions();
      phoneWidth(tester);
      await tester.pumpWidget(densityHost(curryLeaves));
      await tester.pumpAndSettle();

      expect(fieldText(tester, densityAmountField), '1');
      expect(fieldText(tester, densityField), isEmpty);
    });

    testWidgets('what somebody typed is never rewritten by the row arriving '
        'underneath it', (tester) async {
      filterForuiSemanticsAssertions();
      phoneWidth(tester);
      // The serving is a watched query: it lands after the first build, and
      // by then the sentence may be somebody's.
      await tester.pumpWidget(densityHost(flakes));
      await tester.pumpAndSettle();
      await tester.tap(find.text('· change'));
      await tester.pumpAndSettle();

      await tester.enterText(densityField, '30');
      await tester.pumpAndSettle();
      await tester.pumpWidget(densityHost(flakes, serving: flakesServing));
      await tester.pumpAndSettle();

      expect(fieldText(tester, densityField), '30');
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
