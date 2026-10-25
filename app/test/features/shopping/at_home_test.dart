import 'package:ansi/core/units/macros.dart';
import 'package:ansi/core/units/measure.dart';
import 'package:ansi/core/units/units.dart';
import 'package:ansi/features/ingredients/domain/price.dart';
import 'package:ansi/features/recipes/domain/recipe_cost.dart';
import 'package:ansi/features/shopping/domain/at_home.dart';
import 'package:ansi/features/shopping/domain/shopping.dart';
import 'package:ansi/features/shopping/domain/shopping_cost.dart';
import 'package:flutter_test/flutter_test.dart';

const _weekdays = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
const _onionMedium = Measure(
  id: 'm-onion',
  label: 'onion, medium',
  amount: 110,
);
const _piece = Measure(id: 'piece', label: 'piece', amount: 120);

ShoppingNeed _need(
  List<Quantity> totals, {
  MeasureAmount? measureTotal,
  PieceTotal? pieceTotal,
}) => (totals: totals, measureTotal: measureTotal, pieceTotal: pieceTotal);

CookContributionInput _cook(
  String ingredientId,
  double qty,
  Unit? unit, {
  Measure? measure,
  String recipe = 'Recipe',
  int cookDay = 0,
}) => (
  ingredientId: ingredientId,
  quantity: qty,
  unit: unit,
  rawUnit: unit?.id,
  measure: measure,
  recipeTitle: recipe,
  cookDay: cookDay,
  batched: false,
  forParents: const [],
  weekNote: null,
);

ShoppingEntryInput _entry(
  String id,
  String ingredientId, {
  bool checked = false,
  String? createdAt,
}) => (
  id: id,
  ingredientId: ingredientId,
  freeText: null,
  category: null,
  checked: checked,
  unit: null,
  createdAt: createdAt,
);

AtHomeInput _home(
  String entryId,
  double qty,
  Unit? unit, {
  Measure? measure,
  String? updatedAt,
}) => (
  entryId: entryId,
  quantity: qty,
  unit: unit,
  rawUnit: unit?.id,
  measureId: measure?.id,
  measure: measure,
  updatedAt: updatedAt,
);

IngredientMetaInput _meta(
  String name, {
  String category = 'baking',
  Unit unit = g,
  double? density,
  List<Measure> measures = const [],
  double? pieceWeight,
}) => (
  name: name,
  category: category,
  densityGPerMl: density,
  defaultUnit: unit,
  measures: measures,
  pieceBasisAmount: pieceWeight,
  basis: MacrosBasis.perG,
);

ShoppingList _list({
  required List<CookContributionInput> cook,
  List<ShoppingEntryInput> entries = const [],
  Map<String, AtHomeInput> atHome = const {},
  Map<String, IngredientMetaInput>? meta,
}) => buildShoppingList(
  cook: cook,
  entries: entries,
  manual: const {},
  meta:
      meta ??
      {
        'flour': _meta('Flour'),
        'onion': _meta(
          'Yellow onion',
          category: 'produce',
          unit: pieces,
          measures: const [_onionMedium],
        ),
        'lime': _meta('Lime', category: 'produce'),
      },
  weekdayShort: _weekdays,
  atHome: atHome,
);

ShoppingItem _only(ShoppingList list, String id) => [
  for (final g in list.groups) ...g.items,
].singleWhere((i) => i.ingredientId == id);

void main() {
  group('leftToBuy', () {
    test('grams come off grams', () {
      final r = leftToBuy(
        need: _need([Quantity(500, g)]),
        quantity: 200,
        unit: g,
        measure: null,
      );
      final left = (r as SomeLeft).left;
      expect(left.totals.single.amount, closeTo(300, 1e-9));
      expect(left.totals.single.unit, g);
    });

    test('another unit of the family converts first', () {
      final r = leftToBuy(
        need: _need([Quantity(500, g)]),
        quantity: 0.2,
        unit: kg,
        measure: null,
      );
      expect((r as SomeLeft).left.totals.single.amount, closeTo(300, 1e-9));
    });

    test("a count in the row's own measure comes off the count", () {
      final r = leftToBuy(
        need: _need(
          [Quantity(550, g)],
          measureTotal: (amount: 5, measure: _onionMedium),
        ),
        quantity: 2,
        unit: pieces,
        measure: _onionMedium,
      );
      final left = (r as SomeLeft).left;
      expect(left.measureTotal!.amount, 3);
      expect(left.measureTotal!.measure, _onionMedium);
      expect(left.totals.single.amount, closeTo(330, 1e-9));
    });

    test('a weight off a counted row keeps the row counted', () {
      final r = leftToBuy(
        need: _need(
          [Quantity(550, g)],
          measureTotal: (amount: 5, measure: _onionMedium),
        ),
        quantity: 220,
        unit: g,
        measure: null,
      );
      final left = (r as SomeLeft).left;
      expect(left.measureTotal!.amount, closeTo(3, 1e-9));
      expect(left.totals.single.amount, closeTo(330, 1e-9));
    });

    test('a volume comes off a weight through the density', () {
      // 200 ml at 0.5 g/ml is 100 g.
      final r = leftToBuy(
        need: _need([Quantity(500, g)]),
        quantity: 200,
        unit: ml,
        measure: null,
        densityGPerMl: 0.5,
      );
      expect((r as SomeLeft).left.totals.single.amount, closeTo(400, 1e-9));
    });

    test('a volume with no density is not counted, never guessed', () {
      final r = leftToBuy(
        need: _need([Quantity(500, g)]),
        quantity: 1,
        unit: cup,
        measure: null,
      );
      expect((r as NotCounted).reason, 'no density');
    });

    test('pieces come off a weight through the piece weight', () {
      final r = leftToBuy(
        need: _need([Quantity(360, g)], pieceTotal: (count: 3, approx: false)),
        quantity: 1,
        unit: pieces,
        measure: null,
        pieceMeasure: _piece,
      );
      final left = (r as SomeLeft).left;
      expect(left.totals.single.amount, closeTo(240, 1e-9));
      expect(left.pieceTotal!.count, closeTo(2, 1e-9));
    });

    test('an amount that covers the need is all of it', () {
      expect(
        leftToBuy(
          need: _need([Quantity(500, g)]),
          quantity: 500,
          unit: g,
          measure: null,
        ),
        isA<AllAtHome>(),
      );
      expect(
        leftToBuy(
          need: _need([Quantity(500, g)]),
          quantity: 2,
          unit: kg,
          measure: null,
        ),
        isA<AllAtHome>(),
      );
    });

    test('two measurable totals cannot take an amount', () {
      final r = leftToBuy(
        need: _need([Quantity(300, g), Quantity(2, tbsp)]),
        quantity: 100,
        unit: g,
        measure: null,
      );
      expect((r as NotCounted).reason, 'no density');
    });

    test('imprecise words ride along and never block', () {
      final need = _need([Quantity(1, tsp), Quantity(1, toTaste)]);
      final some = leftToBuy(
        need: need,
        quantity: 0.5,
        unit: tsp,
        measure: null,
      );
      expect((some as SomeLeft).left.totals.map((t) => t.unit), [tsp, toTaste]);
      expect(
        leftToBuy(need: need, quantity: 1, unit: tsp, measure: null),
        isA<AllAtHome>(),
      );
    });

    test('a row of words only is all at home whatever was said', () {
      expect(
        leftToBuy(
          need: _need([Quantity(1, toTaste)]),
          quantity: 1,
          unit: toTaste,
          measure: null,
        ),
        isA<AllAtHome>(),
      );
    });
  });

  group('buildShoppingList with an amount at home', () {
    test(
      'a part-have shortens the row; its provenance still says the need',
      () {
        final list = _list(
          cook: [
            _cook('flour', 300, g, recipe: 'Curry'),
            _cook('flour', 200, g, recipe: 'Cookies'),
          ],
          entries: [_entry('e1', 'flour')],
          atHome: {'e1': _home('e1', 200, g)},
        );
        final flour = _only(list, 'flour');
        expect(flour.totals.single.amount, closeTo(300, 1e-9));
        expect(flour.need.totals.single.amount, closeTo(500, 1e-9));
        expect(flour.atHome!.all, isFalse);
        expect(flour.isAtHome, isFalse);
        expect(flour.contributions.map((c) => c.quantity), [300, 200]);
        expect(list.openGroups.expand((g) => g.items), contains(flour));
      },
    );

    test('a whole-have leaves the aisles for At home', () {
      final list = _list(
        cook: [_cook('flour', 500, g), _cook('lime', 50, g)],
        entries: [_entry('e1', 'flour')],
        atHome: {'e1': _home('e1', 500, g)},
      );
      final flour = _only(list, 'flour');
      expect(flour.isAtHome, isTrue);
      expect(list.atHome, [flour]);
      expect(list.openGroups.expand((g) => g.items).map((i) => i.name), [
        'Lime',
      ]);
      expect(list.allTicked, isFalse);
    });

    test('everything at home and nothing ticked is allAtHome', () {
      final list = _list(
        cook: [_cook('flour', 500, g)],
        entries: [_entry('e1', 'flour')],
        atHome: {'e1': _home('e1', 500, g)},
      );
      expect(list.allTicked, isTrue);
      expect(list.allAtHome, isTrue);
    });

    test('a ticked row stays in the basket even when covered', () {
      final list = _list(
        cook: [_cook('flour', 500, g)],
        entries: [_entry('e1', 'flour', checked: true)],
        atHome: {'e1': _home('e1', 500, g)},
      );
      expect(list.basket, hasLength(1));
      expect(list.atHome, isEmpty);
      expect(list.allAtHome, isFalse);
    });

    test('a week that grows brings a whole-have back as a part-have', () {
      // 5 onions said at home; the week now asks for 7.
      final list = _list(
        cook: [
          _cook('onion', 5, pieces, measure: _onionMedium),
          _cook('onion', 2, pieces, measure: _onionMedium, recipe: 'Shak'),
        ],
        entries: [_entry('e1', 'onion')],
        atHome: {'e1': _home('e1', 5, pieces, measure: _onionMedium)},
      );
      final onion = _only(list, 'onion');
      expect(onion.isAtHome, isFalse);
      expect(onion.measureTotal!.amount, closeTo(2, 1e-9));
      expect(onion.need.measureTotal!.amount, 7);
    });

    test('a week that shrinks keeps the row at home', () {
      final list = _list(
        cook: [_cook('onion', 3, pieces, measure: _onionMedium)],
        entries: [_entry('e1', 'onion')],
        atHome: {'e1': _home('e1', 5, pieces, measure: _onionMedium)},
      );
      expect(_only(list, 'onion').isAtHome, isTrue);
    });

    test('an amount that cannot come off leaves the need and says why', () {
      final list = _list(
        cook: [_cook('flour', 500, g)],
        entries: [_entry('e1', 'flour')],
        atHome: {'e1': _home('e1', 1, cup)},
      );
      final flour = _only(list, 'flour');
      expect(flour.totals.single.amount, 500);
      expect(flour.atHome!.refusal, 'no density');
      expect(flour.isAtHome, isFalse);
    });

    test('the newest amount wins across duplicate entries', () {
      final list = _list(
        cook: [_cook('flour', 500, g)],
        entries: [
          _entry('e1', 'flour', createdAt: '2026-10-01'),
          _entry('e2', 'flour', createdAt: '2026-10-02'),
        ],
        atHome: {
          'e1': _home('e1', 100, g, updatedAt: '2026-10-25T09:00:00Z'),
          'e2': _home('e2', 400, g, updatedAt: '2026-10-25T10:00:00Z'),
        },
      );
      expect(_only(list, 'flour').totals.single.amount, closeTo(100, 1e-9));
    });

    test('an entry with only an amount and no need drops off', () {
      final list = _list(
        cook: [_cook('lime', 50, g)],
        entries: [_entry('e1', 'flour')],
        atHome: {'e1': _home('e1', 200, g)},
      );
      expect([for (final g in list.groups) ...g.items].map((i) => i.name), [
        'Lime',
      ]);
    });
  });

  group('the trip', () {
    test('a row moving to At home never plays the confetti', () {
      final list = _list(
        cook: [
          _cook('flour', 500, g),
          _cook('lime', 50, g),
          _cook('onion', 1, pieces, measure: _onionMedium),
        ],
        entries: [_entry('e1', 'flour'), _entry('e2', 'lime', checked: true)],
        atHome: {'e1': _home('e1', 500, g)},
      );
      // Ticking the onion finishes the trip: the flour is not on it.
      expect(completesTheList(list, _only(list, 'onion')), isTrue);
      expect(completesTheList(list, _only(list, 'flour')), isFalse);
    });

    test(
      'a part-have is priced on what is left; a whole-have adds nothing',
      () {
        final list = _list(
          cook: [_cook('flour', 500, g), _cook('lime', 1000, g)],
          entries: [_entry('e1', 'flour'), _entry('e2', 'lime')],
          atHome: {'e1': _home('e1', 200, g), 'e2': _home('e2', 1000, g)},
        );
        final price = PriceObservation(
          lineId: 'rl',
          receiptId: 'r',
          cents: 100,
          packBasisAmount: 100,
          basis: MacrosBasis.perG,
          store: 'TJ',
          purchasedAt: DateTime.utc(2026, 9, 3),
        );
        final IngredientPricing pricing = (
          row: (
            basis: MacrosBasis.perG,
            densityGPerMl: null,
            pieceBasisAmount: null,
          ),
          price: price,
        );
        // 300 g of flour at $1 / 100 g; the lime is at home and adds nothing.
        final trip = tripCostCents([
          for (final g in list.openGroups) ...g.items,
        ], (_) => pricing);
        expect(trip.cents, closeTo(300, 1e-9));
        expect(trip.unpriced, 0);
      },
    );
  });

  group('amountForAll', () {
    ShoppingItem item(ShoppingNeed need) => ShoppingItem(
      name: 'x',
      ingredientId: 'x',
      totals: need.totals,
      measureTotal: need.measureTotal,
      pieceTotal: need.pieceTotal,
    );

    test('a counted row stores its count in its measure', () {
      final a = amountForAll(
        item(
          _need(
            [Quantity(550, g)],
            measureTotal: (amount: 5, measure: _onionMedium),
          ),
        ),
      )!;
      expect((a.quantity, a.unit, a.measure), (5.0, pieces, _onionMedium));
    });

    test('a piece-counted row stores pieces', () {
      final a = amountForAll(
        item(_need([Quantity(360, g)], pieceTotal: (count: 3, approx: false))),
      )!;
      expect((a.quantity, a.unit, a.measure), (3.0, pieces, null));
    });

    test('a plain row stores its one total; words ride along', () {
      final a = amountForAll(
        item(_need([Quantity(500, g), Quantity(1, pinch)])),
      )!;
      expect((a.quantity, a.unit), (500.0, g));
    });

    test('a row of words stores one of its word', () {
      final a = amountForAll(item(_need([Quantity(1, toTaste)])))!;
      expect((a.quantity, a.unit), (1.0, toTaste));
    });

    test('two measurable totals store nothing', () {
      expect(
        amountForAll(item(_need([Quantity(300, g), Quantity(2, tbsp)]))),
        isNull,
      );
      expect(
        canBeAtHome(item(_need([Quantity(300, g), Quantity(2, tbsp)]))),
        isFalse,
      );
    });
  });
}
