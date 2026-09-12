/// The `yield_raw` → MAKES prefill parser (step 8.6 / D2 · D9, board frame h).
///
/// The rule under test is a posture, not just a function: **parse a plain
/// amount + unit, refuse everything else**. Every refusal below is a case where
/// guessing would have written a number the page never printed, and every
/// derived batch, session and shopping figure downstream divides by that
/// number — so the refusals matter more than the parses.
library;

import 'package:ansi/core/units/units.dart';
import 'package:ansi/features/import/domain/yield_prefill.dart';
import 'package:flutter_test/flutter_test.dart';

import 'gold_fixture.dart';

void main() {
  group('parseYieldRaw — what the page plainly said', () {
    const cases = <String, ({double qty, Unit unit})>{
      // The two gold specimens, verbatim.
      'MAKES: 8 SLIDERS': (qty: 8, unit: pieces),
      'MAKES: 1 CUP': (qty: 1, unit: cup),
      // The board's own example, and the prefix's other spellings.
      'MAKES 1 CUP': (qty: 1, unit: cup),
      'Makes 12 muffins': (qty: 12, unit: pieces),
      'makes 250 g': (qty: 250, unit: g),
      'Makes 250 grams': (qty: 250, unit: g),
      'YIELDS 2 LITRES': (qty: 2, unit: l),
      'Yield: 16 tbsp': (qty: 16, unit: tbsp),
      // The US pair (plan 0025 D2a): stock and cream recipes print these.
      'Makes 2 quarts': (qty: 2, unit: quart),
      'Makes 1 quart': (qty: 1, unit: quart),
      'Yields 1 qt': (qty: 1, unit: quart),
      'Makes 1 pint': (qty: 1, unit: pint),
      'makes 3 pints': (qty: 3, unit: pint),
      'Makes 1 pt.': (qty: 1, unit: pint),
      // No prefix at all — the amount is still plainly the amount.
      '500 ml': (qty: 500, unit: ml),
      '8 pieces': (qty: 8, unit: pieces),
      // Numbers a printed page actually uses.
      'Makes 1.5 l': (qty: 1.5, unit: l),
      'Makes 1/2 cup': (qty: 0.5, unit: cup),
      'Makes ½ cup': (qty: 0.5, unit: cup),
      'Makes 1½ cups': (qty: 1.5, unit: cup),
      // Trailing punctuation is noise, not a word.
      'Makes 1 cup.': (qty: 1, unit: cup),
      // A bare number: a count of whatever the recipe makes.
      'Makes 8': (qty: 8, unit: pieces),
    };

    cases.forEach((raw, expected) {
      test('"$raw" → ${expected.qty} ${expected.unit.id}', () {
        final parsed = parseYieldRaw(raw);
        expect(parsed, isNotNull, reason: '"$raw" is a plain amount + unit');
        expect(parsed!.qty, closeTo(expected.qty, 1e-9));
        expect(parsed.unit, expected.unit);
      });
    });

    test('an unknown noun after the number is a COUNT of the yield', () {
      // "8 SLIDERS" is the sausage answer's other half: the page named what it
      // makes, and `piece` is exactly "one of those". The noun itself is not
      // invented into a unit — the source line still shows it.
      expect(parseYieldRaw('MAKES: 8 SLIDERS')!.unit, pieces);
      expect(parseYieldRaw('Makes 24 cookies')!.unit, pieces);
    });
  });

  group('parseYieldRaw — what it refuses, rather than guesses', () {
    const refusals = <String>[
      // The board's own "leaves the fields honestly empty" case.
      'MAKES ENOUGH FOR A CROWD',
      'Makes enough for 4 people',
      // A hedge word is more than a plain amount — "about" is the page being
      // approximate, and we do not launder that into a stated fact.
      'Makes about 1.5 litres',
      // Three tokens is not "amount + unit", however readable it is.
      'Makes 2 dozen cookies',
      'MAKES 8 SLIDERS PLUS EXTRA',
      // A portion word is the SERVINGS fact wearing a MAKES prefix.
      'Makes 4 servings',
      'Makes 6 portions',
      // No number at all.
      'Makes a big batch',
      'MAKES:',
      '',
      '   ',
      // Nothing positive to divide by.
      'Makes 0 cups',
      'Makes -2 cups',
      // A yield is what other amounts are measured against: neither of these
      // can be one.
      'Makes 1 batch',
      'Makes 2 pinch',
    ];

    for (final raw in refusals) {
      test('"$raw" prefills nothing', () {
        expect(parseYieldRaw(raw), isNull);
      });
    }

    test('null (the usual case — most pages say nothing) is null', () {
      expect(parseYieldRaw(null), isNull);
    });
  });

  test(
    'every gold yield_raw is a good case, and the silent ones stay silent',
    () {
      // The blessed extractions are the real vocabulary this parser meets.
      expect(parseYieldRaw(goldPayload('sausage-sliders').yieldRaw), (
        qty: 8.0,
        unit: pieces,
      ));
      expect(parseYieldRaw(goldPayload('herbed-bread-crumbs').yieldRaw), (
        qty: 1.0,
        unit: cup,
      ));
      // A gold file with no printed yield prefills nothing — and that is the
      // majority of them.
      expect(goldPayload('mint-pea-soup').yieldRaw, isNull);
      expect(parseYieldRaw(goldPayload('mint-pea-soup').yieldRaw), isNull);
    },
    skip: skipWithoutGold,
  );
}
