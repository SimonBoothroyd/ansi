import 'package:ansi/features/import/domain/line_resolution.dart';
import 'package:ansi/features/import/domain/line_validation.dart';
import 'package:ansi/features/import/domain/reconciliation_payload.dart';
import 'package:ansi/features/import/presentation/recon_amount.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('amountLabel', () {
    test('an imprecise unit reads as the clean unit, never the raw phrase', () {
      const r = LineResolution(
        lineIndex: 0,
        band: MatchBand.none,
        ingredientText: 'chilli',
        isRange: false,
        unit: 'pinch',
      );
      expect(
        amountLabel(
          r,
          const RawLineItem(
            ingredientText: 'chilli',
            rawAmount: 'A good pinch',
          ),
        ),
        'pinch',
      );
    });

    test('an unpicked range shows the printed original for reference', () {
      const r = LineResolution(
        lineIndex: 0,
        band: MatchBand.auto,
        ingredientText: 'garlic',
        isRange: true,
        unit: 'clove',
      );
      expect(
        amountLabel(
          r,
          const RawLineItem(ingredientText: 'garlic', rawAmount: '2–3 cloves'),
        ),
        '2–3 cloves',
      );
    });

    test('a counted line landed on the whole measure prints the measure’s own '
        'words — "1 lime, whole", never a renamed piece', () {
      const r = LineResolution(
        lineIndex: 0,
        band: MatchBand.auto,
        ingredientText: 'lime',
        isRange: false,
        unit: 'lime, whole',
        quantity: 1,
        chosenIngredientId: 'i-lime',
      );
      const raw = RawLineItem(ingredientText: 'lime', rawAmount: '1');
      expect(amountLabel(r, raw), '1 lime, whole');
      expect(amountSlotLabel(r, raw, const []), '1 lime, whole');
    });

    test('a picked quantity + unit reads plainly', () {
      const r = LineResolution(
        lineIndex: 0,
        band: MatchBand.auto,
        ingredientText: 'spaghetti',
        isRange: false,
        unit: 'g',
        quantity: 400,
      );
      expect(amountLabel(r, const RawLineItem(ingredientText: 'x')), '400 g');
    });

    test('a prose amount shows the qualifier, never the raw parenthetical', () {
      const r = LineResolution(
        lineIndex: 0,
        band: MatchBand.none,
        ingredientText: 'Tortilla chips',
        isRange: false,
        unit: null,
      );
      expect(
        amountLabel(
          r,
          const RawLineItem(
            ingredientText: 'Tortilla chips',
            rawAmount: '(to serve (optional))',
          ),
        ),
        'to serve',
      );
    });

    test('nothing printed reads as nothing — the caller renders "—"', () {
      const r = LineResolution(
        lineIndex: 0,
        band: MatchBand.none,
        ingredientText: 'Tortilla chips',
        isRange: false,
        unit: null,
      );
      expect(
        amountLabel(r, const RawLineItem(ingredientText: 'Tortilla chips')),
        '',
      );
    });

    test('a printed amount the vocab could not map still shows as printed', () {
      const r = LineResolution(
        lineIndex: 0,
        band: MatchBand.none,
        ingredientText: 'thyme',
        isRange: false,
        unit: 'sprig',
      );
      expect(
        amountLabel(
          r,
          const RawLineItem(ingredientText: 'thyme', rawAmount: '2 sprigs'),
        ),
        '2 sprigs',
      );
    });
  });

  group('amountSlotLabel', () {
    // "1 whole lime": `whole` is not a unit at all, and no measure of a lime
    // is called one, so the row refuses it.
    const whole = LineResolution(
      lineIndex: 0,
      band: MatchBand.auto,
      ingredientText: 'lime',
      isRange: false,
      unit: 'whole',
      quantity: 1,
      chosenIngredientId: 'ing-lime',
    );
    const wholeRaw = RawLineItem(ingredientText: 'lime', rawAmount: '1 whole');

    test('a unit the matched row cannot carry prints NOTHING', () {
      expect(
        amountSlotLabel(whole, wholeRaw, const [LineIssue.unitNotAllowed]),
        '',
      );
    });

    test('a count-measure noun the row does not measure prints NOTHING', () {
      const r = LineResolution(
        lineIndex: 0,
        band: MatchBand.auto,
        ingredientText: 'chopped tomatoes',
        isRange: false,
        unit: 'can',
        quantity: 1,
        chosenIngredientId: 'ing-tom',
      );
      expect(
        amountSlotLabel(
          r,
          const RawLineItem(
            ingredientText: 'chopped tomatoes',
            rawAmount: '1 can',
          ),
          const [LineIssue.unitNotAllowed],
        ),
        '',
      );
    });

    test('blanking the SLOT never takes the number off the LINE', () {
      // The sheet still opens on "1" and one chip tap resolves the line.
      expect(whole.quantity, 1);
      expect(amountLabel(whole, wholeRaw), '1 whole');
    });

    test('an unpicked range keeps the printed original', () {
      const r = LineResolution(
        lineIndex: 0,
        band: MatchBand.auto,
        ingredientText: 'garlic',
        isRange: true,
        unit: 'clove',
        chosenIngredientId: 'ing-garlic',
      );
      expect(
        amountSlotLabel(
          r,
          const RawLineItem(ingredientText: 'garlic', rawAmount: '2–3 cloves'),
          const [LineIssue.rangeUnpicked],
        ),
        '2–3 cloves',
      );
    });

    test('an admitted imprecise unit still names itself', () {
      const r = LineResolution(
        lineIndex: 0,
        band: MatchBand.auto,
        ingredientText: 'chilli',
        isRange: false,
        unit: 'pinch',
        chosenIngredientId: 'ing-chilli',
      );
      expect(
        amountSlotLabel(
          r,
          const RawLineItem(
            ingredientText: 'chilli',
            rawAmount: 'A good pinch',
          ),
          const [],
        ),
        'pinch',
      );
    });
  });
}
