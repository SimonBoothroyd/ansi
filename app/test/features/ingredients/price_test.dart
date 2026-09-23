import 'package:ansi/core/result/result.dart';
import 'package:ansi/core/units/macros.dart';
import 'package:ansi/core/units/measure.dart';
import 'package:ansi/core/units/units.dart';
import 'package:ansi/features/ingredients/domain/allowed_units.dart';
import 'package:ansi/features/ingredients/domain/ingredient.dart';
import 'package:ansi/features/ingredients/domain/price.dart';
import 'package:flutter_test/flutter_test.dart';

/// A per-100 g row — the ordinary shape.
Ingredient _grams({
  double? density,
  double? pieceWeight,
  Unit defaultUnit = g,
}) => Ingredient(
  id: 'i1',
  canonicalName: 'Bananas, organic',
  defaultUnit: defaultUnit,
  status: IngredientStatus.complete,
  densityGPerMl: density,
  pieceBasisAmount: pieceWeight,
);

/// A per-100 ml row — a liquid whose label reads per 100 ml.
Ingredient _millilitres({double? density}) => Ingredient(
  id: 'i2',
  canonicalName: 'Olive Oil',
  defaultUnit: ml,
  status: IngredientStatus.complete,
  macrosBasis: MacrosBasis.perMl,
  densityGPerMl: density,
);

const _bag = Measure(id: 'm1', label: 'bag', amount: 454);

Receipt _receipt({
  String store = "TJ's",
  ReceiptSource source = ReceiptSource.photo,
}) => Receipt(
  id: 'r1',
  store: store,
  purchasedAt: DateTime.utc(2026, 9, 13),
  source: source,
);

void main() {
  group('pricePer100', () {
    test('cents for a pack become cents per 100 of the basis', () {
      final price = pricePer100(
        paidCents: 349,
        packBasisAmount: 454,
        count: 1,
        basis: MacrosBasis.perG,
      );
      expect(price.valueOrNull!.cents, closeTo(76.872, 0.001));
      expect(price.valueOrNull!.basis, MacrosBasis.perG);
      expect(formatPricePer100(price.valueOrNull!), '77¢ / 100 g');
    });

    test('a per-ml row reads per 100 ml, in its own dimension', () {
      final price = pricePer100(
        paidCents: 899,
        packBasisAmount: 500,
        count: 1,
        basis: MacrosBasis.perMl,
      );
      expect(formatPricePer100(price.valueOrNull!), r'$1.80 / 100 ml');
    });

    test('the derived figure is NOT rounded before it is printed', () {
      // Rounding here would put a rounding inside every sum built on it.
      final price = pricePer100(
        paidCents: 100,
        packBasisAmount: 3,
        count: 1,
        basis: MacrosBasis.perG,
      );
      expect(price.valueOrNull!.cents, closeTo(3333.333, 0.001));
    });

    test('a pack of nothing is refused, never divided by', () {
      for (final pack in [0.0, -1.0, double.nan, double.infinity]) {
        final price = pricePer100(
          paidCents: 349,
          packBasisAmount: pack,
          count: 1,
          basis: MacrosBasis.perG,
        );
        expect(price, isA<Err<PricePer100>>(), reason: 'pack $pack');
        expect((price as Err<PricePer100>).failure.code, 'price/no_pack');
      }
    });

    test('a counted line prices ALL of what the cents bought', () {
      // The owner's tofu: eight 1 lb blocks for $23.92. The pack is what ONE
      // block is; the count is how many rang up on the line.
      final price = pricePer100(
        paidCents: 2392,
        packBasisAmount: 453.59237,
        count: 8,
        basis: MacrosBasis.perG,
      );
      expect(price.valueOrNull!.cents, closeTo(65.918, 0.001));
      expect(formatPricePer100(price.valueOrNull!), '66¢ / 100 g');

      // Against ONE pack the same line reads eight times too dear — which is
      // exactly what it did before the count was read.
      final wrong = pricePer100(
        paidCents: 2392,
        packBasisAmount: 453.59237,
        count: 1,
        basis: MacrosBasis.perG,
      );
      expect(wrong.valueOrNull!.cents, closeTo(527.34, 0.01));
    });

    test('a count of none is refused, never divided by', () {
      for (final count in [0, -2]) {
        final price = pricePer100(
          paidCents: 349,
          packBasisAmount: 454,
          count: count,
          basis: MacrosBasis.perG,
        );
        expect((price as Err<PricePer100>).failure.code, 'price/no_pack');
      }
    });

    test('nothing paid is not a price of zero — it is no price', () {
      final price = pricePer100(
        paidCents: 0,
        packBasisAmount: 454,
        count: 1,
        basis: MacrosBasis.perG,
      );
      expect((price as Err<PricePer100>).failure.code, 'price/nothing_paid');
    });
  });

  group('packInBasis — the honesty gate', () {
    test('the basis unit itself needs nothing', () {
      expect(
        packInBasis(_grams(), amount: 454, choice: const UnitOption(g)),
        const Ok<double>(454),
      );
    });

    test('a unit of the basis family converts by the ratio table', () {
      final pack = packInBasis(
        _grams(),
        amount: 1,
        choice: const UnitOption(lb),
      );
      expect(pack.valueOrNull, closeTo(453.592, 0.001));
    });

    test('a measure carries its own weight — no density needed', () {
      expect(
        packInBasis(_grams(), amount: 1, choice: const MeasureOption(_bag)),
        const Ok<double>(454),
      );
    });

    test('two of a measure is two packs', () {
      expect(
        packInBasis(_grams(), amount: 2, choice: const MeasureOption(_bag)),
        const Ok<double>(908),
      );
    });

    test('a volume pack on a g-basis row REFUSES without a density', () {
      final pack = packInBasis(
        _grams(),
        amount: 500,
        choice: const UnitOption(ml),
      );
      expect(pack, isA<Err<double>>());
      expect((pack as Err<double>).failure.code, 'unit/no_density');
    });

    test('…and converts through the density when the row states one', () {
      final pack = packInBasis(
        _grams(density: 0.92),
        amount: 500,
        choice: const UnitOption(ml),
      );
      expect(pack.valueOrNull, closeTo(460, 0.001));
    });

    test('the gate runs the other way too — grams on a per-ml row', () {
      final noDensity = packInBasis(
        _millilitres(),
        amount: 500,
        choice: const UnitOption(g),
      );
      expect((noDensity as Err<double>).failure.code, 'unit/no_density');

      final withDensity = packInBasis(
        _millilitres(density: 0.92),
        amount: 460,
        choice: const UnitOption(g),
      );
      expect(withDensity.valueOrNull, closeTo(500, 0.001));
    });

    test('a weighed piece bridges like the measure it is (ADR-0015)', () {
      final pack = packInBasis(
        _grams(pieceWeight: 118, defaultUnit: pieces),
        amount: 6,
        choice: const UnitOption(pieces),
      );
      expect(pack, const Ok<double>(708));
    });

    test('a count on a row that weighs nothing is refused', () {
      final pack = packInBasis(
        _grams(defaultUnit: pieces),
        amount: 6,
        choice: const UnitOption(pieces),
      );
      expect((pack as Err<double>).failure.code, 'unit/incompatible');
    });

    test('an imprecise word converts to nothing, here as everywhere', () {
      final pack = packInBasis(
        _grams(),
        amount: 1,
        choice: const UnitOption(handful),
      );
      expect((pack as Err<double>).failure.code, 'unit/imprecise');
    });

    test('a pack of no amount is refused before any conversion', () {
      for (final amount in [0.0, -2.0, double.nan]) {
        final pack = packInBasis(
          _grams(),
          amount: amount,
          choice: const UnitOption(g),
        );
        expect((pack as Err<double>).failure.code, 'price/no_pack');
      }
    });
  });

  group('priceFromEntry', () {
    test('the sheet’s whole question, answered in one figure', () {
      final price = priceFromEntry(
        _grams(),
        paidCents: 349,
        packAmount: 1,
        packChoice: const MeasureOption(_bag),
      );
      expect(formatPricePer100(price.valueOrNull!), '77¢ / 100 g');
    });

    test('the pack’s refusal comes back first, so the dock says THAT', () {
      final price = priceFromEntry(
        _grams(),
        paidCents: 899,
        packAmount: 500,
        packChoice: const UnitOption(ml),
      );
      expect((price as Err<PricePer100>).failure.code, 'unit/no_density');
    });

    test('a good pack with nothing paid still refuses', () {
      final price = priceFromEntry(
        _grams(),
        paidCents: 0,
        packAmount: 1,
        packChoice: const MeasureOption(_bag),
      );
      expect((price as Err<PricePer100>).failure.code, 'price/nothing_paid');
    });
  });

  group('the line, and what is paid', () {
    test('a discount rides beside the printed figure, not inside it', () {
      const line = ReceiptLine(
        id: 'l1',
        receiptId: 'r1',
        cents: 349,
        discountCents: 50,
        kind: ReceiptLineKind.item,
      );
      expect(line.cents, 349, reason: 'the paper is kept as printed');
      expect(line.paidCents, 299, reason: 'what you paid is the price');
    });

    test('the price is derived from what was paid', () {
      const line = ReceiptLine(
        id: 'l1',
        receiptId: 'r1',
        ingredientId: 'i1',
        cents: 349,
        discountCents: 50,
        kind: ReceiptLineKind.item,
        packBasisAmount: 454,
      );
      final observation = observationFrom(
        line,
        _receipt(),
        basis: MacrosBasis.perG,
      )!;
      expect(observation.paidCents, 299);
      expect(formatPricePer100(observation.per100.valueOrNull!), '66¢ / 100 g');
    });
  });

  group('observationFrom — what is a price and what is only a line', () {
    ReceiptLine line({
      ReceiptLineKind kind = ReceiptLineKind.item,
      String? ingredientId = 'i1',
      double? pack = 454,
      int cents = 349,
      int count = 1,
      int discount = 0,
    }) => ReceiptLine(
      id: 'l1',
      receiptId: 'r1',
      ingredientId: ingredientId,
      cents: cents,
      count: count,
      discountCents: discount,
      kind: kind,
      packBasisAmount: pack,
    );

    test('food, named, packed and paid for is a price', () {
      final observation = observationFrom(
        line(),
        _receipt(),
        basis: MacrosBasis.perG,
        packLabel: 'bag',
      );
      expect(observation, isNotNull);
      expect(observation!.store, "TJ's");
      expect(observation.purchasedAt, DateTime.utc(2026, 9, 13));
      expect(observation.packLabel, 'bag');
    });

    test("the line's count travels with the fact, and prices it", () {
      final observation = observationFrom(
        line(cents: 2392, count: 8, pack: 453.59237),
        _receipt(),
        basis: MacrosBasis.perG,
      )!;
      expect(observation.count, 8);
      // Every reader of a price goes through `per100`, so no screen can read
      // this line as one block.
      expect(observation.per100.valueOrNull!.cents, closeTo(65.918, 0.001));
    });

    test('a matched line with no pack is honestly not a price yet', () {
      expect(
        observationFrom(line(pack: null), _receipt(), basis: MacrosBasis.perG),
        isNull,
      );
    });

    test('a not-food line never becomes one', () {
      expect(
        observationFrom(
          line(kind: ReceiptLineKind.notFood, ingredientId: null, pack: null),
          _receipt(),
          basis: MacrosBasis.perG,
        ),
        isNull,
      );
    });

    test('a tax line is not a price', () {
      expect(
        observationFrom(
          line(kind: ReceiptLineKind.tax, ingredientId: null, pack: null),
          _receipt(),
          basis: MacrosBasis.perG,
        ),
        isNull,
      );
    });

    test('a line whose ingredient was retired out from under it is not', () {
      expect(
        observationFrom(
          line(ingredientId: null),
          _receipt(),
          basis: MacrosBasis.perG,
        ),
        isNull,
      );
    });

    test('a line discounted to nothing is not a price of zero', () {
      expect(
        observationFrom(
          line(discount: 349),
          _receipt(),
          basis: MacrosBasis.perG,
        ),
        isNull,
      );
    });
  });

  group('the pack as it was entered', () {
    test('a unit chip stores the amount and the unit’s catalog id', () {
      final entered = packAsEntered(1, const UnitOption(lb));
      expect(entered.amount, 1);
      expect(entered.unitId, 'lb');
      expect(
        entered.measureId,
        isNull,
        reason: 'a pound points at no row of the vocabulary',
      );
    });

    test('a measure chip stores the COUNT, and the measure names it', () {
      final entered = packAsEntered(2, const MeasureOption(_bag));
      expect(entered.amount, 2);
      expect(
        entered.unitId,
        isNull,
        reason: 'the measure’s own label is the word — never a second copy',
      );
      expect(entered.measureId, 'm1');
    });

    test('an observation carries the words as well as the weight', () {
      final observation = observationFrom(
        const ReceiptLine(
          id: 'l1',
          receiptId: 'r1',
          ingredientId: 'i1',
          cents: 349,
          kind: ReceiptLineKind.item,
          // A pound, resolved once at entry — and still a pound.
          packBasisAmount: 453.59237,
          packAmount: 1,
          packUnit: lb,
        ),
        _receipt(),
        basis: MacrosBasis.perG,
      )!;
      expect(observation.packAmount, 1);
      expect(observation.packUnit, lb);
      expect(
        observation.packBasisAmount,
        closeTo(453.6, 0.1),
        reason: 'the derivation still reads the basis figure',
      );
      expect(formatPricePer100(observation.per100.valueOrNull!), '77¢ / 100 g');
    });

    test('a line written before the ledger kept the words says nothing', () {
      final observation = observationFrom(
        const ReceiptLine(
          id: 'l1',
          receiptId: 'r1',
          ingredientId: 'i1',
          cents: 349,
          kind: ReceiptLineKind.item,
          packBasisAmount: 454,
        ),
        _receipt(),
        basis: MacrosBasis.perG,
      )!;
      expect(observation.packAmount, isNull);
      expect(observation.packUnit, isNull);
    });
  });

  group('enteredChoice — the chip a stored line reopens on', () {
    PriceObservation stored({double? amount, Unit? unit, String? measureId}) =>
        PriceObservation(
          lineId: 'l1',
          receiptId: 'r1',
          cents: 349,
          packBasisAmount: 454,
          basis: MacrosBasis.perG,
          store: "TJ's",
          purchasedAt: DateTime.utc(2026, 9, 13),
          packAmount: amount,
          packUnit: unit,
          measureId: measureId,
        );

    test('a unit pack reopens on that unit', () {
      expect(
        enteredChoice(stored(amount: 1, unit: lb), const [_bag]),
        const UnitOption(lb),
      );
    });

    test('a measure pack reopens on that measure', () {
      expect(
        enteredChoice(stored(amount: 1, measureId: 'm1'), const [_bag]),
        const MeasureOption(_bag),
      );
    });

    test('a measure deleted since leaves nothing to reopen on', () {
      expect(enteredChoice(stored(amount: 1, measureId: 'm1'), const []), null);
    });

    test('a line that kept no entered pack has no chip to name', () {
      expect(enteredChoice(stored(), const [_bag]), isNull);
    });

    test('a base price reopens on its own chip, as a line does', () {
      final base = BasePrice(
        ingredientId: 'i1',
        cents: 349,
        packBasisAmount: 454,
        basis: MacrosBasis.perG,
        setAt: DateTime.utc(2026, 9, 13),
        packAmount: 1,
        measureId: 'm1',
      );
      expect(enteredChoice(base, const [_bag]), const MeasureOption(_bag));
    });
  });

  group('the base price — a row’s own, on no receipt', () {
    BasePrice? read({int? cents = 349, double? pack = 454, DateTime? setAt}) =>
        basePriceFrom(
          ingredientId: 'i1',
          cents: cents,
          packBasisAmount: pack,
          basis: MacrosBasis.perG,
          setAt: setAt ?? DateTime.utc(2026, 9, 13),
        );

    test('reads per 100 of the basis through the one derivation', () {
      final base = read()!;
      expect(formatPricePer100(base.per100.valueOrNull!), '77¢ / 100 g');
      expect(base.count, 1, reason: 'a base price is one pack');
      expect(base.paidCents, 349);
      expect(base.asOf, DateTime.utc(2026, 9, 13));
    });

    test('an unreadable one is no price, never a zero', () {
      expect(read(cents: null), isNull);
      expect(read(cents: 0), isNull);
      expect(read(pack: null), isNull);
      expect(read(pack: 0), isNull);
      expect(read(pack: double.nan), isNull);
      expect(
        basePriceFrom(
          ingredientId: 'i1',
          cents: 349,
          packBasisAmount: 454,
          basis: MacrosBasis.perG,
          setAt: null,
        ),
        isNull,
      );
    });

    test('its key is the row, and never a receipt line', () {
      expect(read()!.key, 'base:i1');
    });
  });

  group('the key a line’s printed words are filed under', () {
    test('trimmed and upper-cased, and nothing else', () {
      expect(printedNameKey('ORG TRICOLOR QUINOA'), 'ORG TRICOLOR QUINOA');
      expect(printedNameKey('  tj org bananas '), 'TJ ORG BANANAS');
      expect(
        printedNameKey('TJ  ORG   BANANAS'),
        'TJ  ORG   BANANAS',
        reason: 'inner spacing is the paper’s, and is not collapsed',
      );
    });

    test('words that are not there are filed under nothing', () {
      // A line from a server older than the column, and one whose words are
      // all whitespace: neither recalls a pack, and neither is keyed as ''.
      expect(printedNameKey(null), isNull);
      expect(printedNameKey(''), isNull);
      expect(printedNameKey('   '), isNull);
    });
  });

  group('the stored enumerations', () {
    test('source round-trips — an older build’s `manual` still reads — and '
        'an unknown one is never “typed here”', () {
      expect(ReceiptSource.fromDb('manual'), ReceiptSource.manual);
      expect(ReceiptSource.fromDb('photo'), ReceiptSource.photo);
      expect(ReceiptSource.fromDb('something else'), ReceiptSource.photo);
      expect(ReceiptSource.fromDb(null), ReceiptSource.photo);
    });

    test('kind round-trips, and an unknown one can never be a price', () {
      for (final kind in ReceiptLineKind.values) {
        expect(ReceiptLineKind.fromDb(kind.dbValue), kind);
      }
      expect(ReceiptLineKind.fromDb('groceries'), ReceiptLineKind.notFood);
      expect(ReceiptLineKind.fromDb(null), ReceiptLineKind.notFood);
    });
  });
}
