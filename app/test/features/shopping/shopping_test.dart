import 'package:flutter_test/flutter_test.dart';
import 'package:mise/core/units/measure.dart';
import 'package:mise/core/units/units.dart';
import 'package:mise/features/shopping/domain/shopping.dart';

const _weekdays = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];

const _potatoLarge = Measure(id: 'm1', label: 'potato, large', grams: 299);
const _can400 = Measure(id: 'm2', label: 'can (400 ml)', grams: 400);

CookContributionInput _cook(
  String ingredientId,
  double qty,
  Unit? unit, {
  String? rawUnit,
  Measure? measure,
  String recipe = 'Recipe',
  int cookDay = 0,
  bool batched = false,
}) => (
  ingredientId: ingredientId,
  quantity: qty,
  unit: unit,
  rawUnit: rawUnit ?? unit?.id,
  measure: measure,
  recipeTitle: recipe,
  cookDay: cookDay,
  batched: batched,
);

ManualContributionInput _manual(
  String id,
  String entryId,
  double qty,
  Unit? unit, {
  Measure? measure,
  String? note,
}) => (
  id: id,
  entryId: entryId,
  quantity: qty,
  unit: unit,
  measure: measure,
  note: note,
);

ShoppingEntryInput _entry(
  String id, {
  String? ingredientId,
  String? freeText,
  String? category,
  bool checked = false,
  Unit? unit,
  String? createdAt,
}) => (
  id: id,
  ingredientId: ingredientId,
  freeText: freeText,
  category: category,
  checked: checked,
  unit: unit,
  createdAt: createdAt,
);

void main() {
  group('aggregateQuantities', () {
    test('sums same-unit quantities into one total', () {
      final totals = aggregateQuantities([Quantity(300, g), Quantity(150, g)]);
      expect(totals, hasLength(1));
      expect(totals.single.amount, 450);
      expect(totals.single.unit, g);
    });

    test('sums across units within a family via the ratio table', () {
      // 500 g + 1 kg = 1500 g; the dominant contribution (kg) sets the unit.
      final totals = aggregateQuantities([Quantity(500, g), Quantity(1, kg)]);
      expect(totals, hasLength(1));
      expect(totals.single.unit, kg);
      expect(totals.single.amount, closeTo(1.5, 1e-9));
    });

    test('prefers the ingredient default unit when it shares the family', () {
      final totals = aggregateQuantities([
        Quantity(500, g),
        Quantity(500, g),
      ], preferred: kg);
      expect(totals.single.unit, kg);
      expect(totals.single.amount, closeTo(1, 1e-9));
    });

    test('bridges mass and volume when a density is supplied', () {
      // 200 ml water (1 g/ml) + 100 g = 300 g, one honest total.
      final totals = aggregateQuantities([
        Quantity(100, g),
        Quantity(200, ml),
      ], densityGPerMl: 1);
      expect(totals, hasLength(1));
      expect(totals.single.unit.family, UnitFamily.mass);
      expect(totals.single.amount, closeTo(300, 1e-9));
    });

    test('keeps two honest subtotals when no density bridges the families', () {
      final totals = aggregateQuantities([Quantity(100, g), Quantity(200, ml)]);
      expect(totals, hasLength(2));
      expect(totals.map((q) => q.unit.family), contains(UnitFamily.mass));
      expect(totals.map((q) => q.unit.family), contains(UnitFamily.volume));
    });

    test('sums count units without inventing a ratio', () {
      final totals = aggregateQuantities([
        Quantity(3, pieces),
        Quantity(2, pieces),
      ]);
      expect(totals.single.amount, 5);
      expect(totals.single.unit, pieces);
    });

    test('never merges imprecise units', () {
      final totals = aggregateQuantities([
        Quantity(1, pinch),
        Quantity(1, dash),
      ]);
      expect(totals, hasLength(2));
    });

    test('collapses identical imprecise units into one entry', () {
      // Two recipes each wanting "1 pinch" reads "pinch", never
      // "pinch + pinch" — but a pinch and a dash stay distinct.
      final totals = aggregateQuantities([
        Quantity(1, pinch),
        Quantity(1, pinch),
        Quantity(1, dash),
      ]);
      expect(totals, hasLength(2));
      expect(totals.where((q) => q.unit == pinch), hasLength(1));
      expect(totals.where((q) => q.unit == dash), hasLength(1));
    });

    test('a non-positive density never bridges (honest subtotals)', () {
      // Density 0 (bad data) must behave exactly like no density: two honest
      // subtotals, not a divide-by-zero total or a silently dropped volume.
      for (final density in [0.0, -1.5]) {
        final totals = aggregateQuantities([
          Quantity(100, g),
          Quantity(200, ml),
        ], densityGPerMl: density);
        expect(totals, hasLength(2), reason: 'density $density');
        expect(totals.map((q) => q.unit.family), contains(UnitFamily.mass));
        expect(totals.map((q) => q.unit.family), contains(UnitFamily.volume));
      }
    });

    test('folds measured amounts into the mass subtotal via gram weights', () {
      // 2 large potatoes (2 × 299 g) + 100 g = 698 g, one honest mass total.
      final totals = aggregateQuantities(
        [Quantity(100, g)],
        measured: [(amount: 2, measure: _potatoLarge)],
      );
      expect(totals, hasLength(1));
      expect(totals.single.unit.family, UnitFamily.mass);
      expect(totals.single.amount, closeTo(698, 1e-9));
    });

    test('measured amounts alone make one mass total (no density needed)', () {
      final totals = aggregateQuantities(
        const [],
        measured: [
          (amount: 1.5, measure: _can400),
          (amount: 0.5, measure: _can400),
        ],
      );
      expect(totals.single.amount, closeTo(800, 1e-9));
      expect(totals.single.unit, g);
    });

    test('a measure with a non-positive gram weight is never summed', () {
      // Mirrors the density guard: a bad stored weight must not fabricate
      // grams — the measured amount simply stays out of the totals.
      const bad = Measure(id: 'mb', label: 'bad', grams: 0);
      final totals = aggregateQuantities(
        [Quantity(100, g)],
        measured: [(amount: 2, measure: bad)],
      );
      expect(totals.single.amount, 100);
    });

    test('a measured amount still bridges volume via density (one total)', () {
      // 1 can (400 g) + 100 ml @ 1 g/ml = 500 g.
      final totals = aggregateQuantities(
        [Quantity(100, ml)],
        measured: [(amount: 1, measure: _can400)],
        densityGPerMl: 1,
      );
      expect(totals, hasLength(1));
      expect(totals.single.amount, closeTo(500, 1e-9));
    });
  });

  group('wholeUnitHintFor', () {
    test('rounds up a fractional count total on a measure-bearing food', () {
      final hint = wholeUnitHintFor(
        totals: [Quantity(2.25, pieces)],
        defaultUnit: pieces,
        measures: const [_potatoLarge],
      );
      expect(hint, isNotNull);
      expect(hint!.count, 2.25);
      expect(hint.buy, 3);
      expect(hint.unitLabel, 'piece');
      expect(hint.approx, isFalse);
    });

    test('derives a count from a mass total via the primary measure', () {
      final hint = wholeUnitHintFor(
        totals: [Quantity(674, g)],
        defaultUnit: pieces,
        measures: const [_potatoLarge],
      );
      expect(hint, isNotNull);
      expect(hint!.count, closeTo(674 / 299, 1e-9));
      expect(hint.buy, 3);
      expect(hint.unitLabel, 'potato, large');
      expect(hint.approx, isTrue);
    });

    test('never hints without a measure — a bare count stays honest', () {
      expect(
        wholeUnitHintFor(
          totals: [Quantity(2.25, pieces)],
          defaultUnit: pieces,
          measures: const [],
        ),
        isNull,
      );
    });

    test('never hints on a non-count-default ingredient', () {
      expect(
        wholeUnitHintFor(
          totals: [Quantity(674, g)],
          defaultUnit: g,
          measures: const [_potatoLarge],
        ),
        isNull,
      );
    });

    test('a whole total needs no hint', () {
      expect(
        wholeUnitHintFor(
          totals: [Quantity(3, pieces)],
          defaultUnit: pieces,
          measures: const [_potatoLarge],
        ),
        isNull,
      );
      expect(
        wholeUnitHintFor(
          totals: [Quantity(598, g)], // exactly 2 × 299 g
          defaultUnit: pieces,
          measures: const [_potatoLarge],
        ),
        isNull,
      );
    });

    test('mixed subtotals get no hint (it could not cover both)', () {
      expect(
        wholeUnitHintFor(
          totals: [Quantity(1.5, pieces), Quantity(100, g)],
          defaultUnit: pieces,
          measures: const [_potatoLarge],
        ),
        isNull,
      );
    });
  });

  group('cookLabel', () {
    test('a single-session recipe shows just its title', () {
      expect(
        cookLabel(_cook('x', 1, g, recipe: 'Oat Cookies'), _weekdays),
        'Oat Cookies',
      );
    });

    test('a batched recipe appends its cook day', () {
      expect(
        cookLabel(_cook('x', 1, g, recipe: 'Curry', batched: true), _weekdays),
        'Curry · cook Mon',
      );
    });
  });

  group('buildShoppingList', () {
    ShoppingList build({
      List<CookContributionInput> cook = const [],
      List<ShoppingEntryInput> entries = const [],
      Map<String, List<ManualContributionInput>> manual = const {},
      Map<String, IngredientMetaInput> meta = const {},
    }) => buildShoppingList(
      cook: cook,
      entries: entries,
      manual: manual,
      meta: meta,
      weekdayShort: _weekdays,
    );

    IngredientMetaInput metaFor(
      String name,
      String category, {
      Unit unit = g,
      double? density,
      List<Measure> measures = const [],
    }) => (
      name: name,
      category: category,
      densityGPerMl: density,
      defaultUnit: unit,
      measures: measures,
    );

    test('rolls two cook contributions of an ingredient into one item', () {
      final list = build(
        cook: [
          _cook('flour', 300, g, recipe: 'Curry', batched: true),
          _cook('flour', 150, g, recipe: 'Cookies', cookDay: 2),
        ],
        meta: {'flour': metaFor('Flour', 'baking')},
      );
      final item = list.groups.single.items.single;
      expect(list.groups.single.label, 'Baking');
      expect(item.name, 'Flour');
      expect(item.totals.single.amount, 450);
      expect(item.contributions, hasLength(2));
      expect(item.contributions.first.label, 'Curry · cook Mon');
    });

    test('merges a manual top-up into the ingredient total + breakdown', () {
      final list = build(
        cook: [_cook('flour', 300, g)],
        entries: [_entry('e1', ingredientId: 'flour', unit: g)],
        manual: {
          'e1': [_manual('c1', 'e1', 50, g)],
        },
        meta: {'flour': metaFor('Flour', 'baking')},
      );
      final item = list.groups.single.items.single;
      expect(item.totals.single.amount, 350);
      expect(item.checked, isFalse);
      expect(
        item.contributions.where((c) => c.source == ContributionSource.manual),
        hasLength(1),
      );
      expect(item.hasBreakdown, isTrue);
    });

    test('carries the entry check-off state onto the item', () {
      final list = build(
        cook: [_cook('onion', 3, pieces)],
        entries: [_entry('e1', ingredientId: 'onion', checked: true)],
        meta: {'onion': metaFor('Onion', 'produce', unit: pieces)},
      );
      expect(list.groups.single.items.single.checked, isTrue);
    });

    test('drops a stale checked entry with no live contribution', () {
      // Its recipe was deleted (no cook contribution) and it has no top-up.
      final list = build(
        entries: [_entry('e1', ingredientId: 'ghost', checked: true)],
        meta: {'ghost': metaFor('Ghost', 'produce')},
      );
      expect(list.isEmpty, isTrue);
    });

    test('orders aisles by the shopping order and puts non-food last', () {
      final list = build(
        cook: [
          _cook('flour', 100, g, recipe: 'A'),
          _cook('onion', 1, pieces, recipe: 'B'),
        ],
        entries: [_entry('e1', freeText: 'Paper towels')],
        meta: {
          'flour': metaFor('Flour', 'baking'),
          'onion': metaFor('Onion', 'produce', unit: pieces),
        },
      );
      expect(list.groups.map((g) => g.label), [
        'Produce',
        'Baking',
        'Non-food',
      ]);
      final nonFood = list.groups.last.items.single;
      expect(nonFood.isFreeText, isTrue);
      expect(nonFood.totals, isEmpty); // renders as a dash
    });

    test('an unrecognised unit is a breakdown note, never a total', () {
      // A persisted unit id this build doesn't know must not be summed under
      // an assumed unit ("pieces") — it surfaces as an unconverted note.
      final list = build(
        cook: [
          _cook('flour', 300, g, recipe: 'Curry'),
          _cook('flour', 2, null, rawUnit: 'scoop', recipe: 'Cookies'),
        ],
        meta: {'flour': metaFor('Flour', 'baking')},
      );
      final item = list.groups.single.items.single;
      // Only the honest 300 g — the "2 scoop" line contributes nothing.
      expect(item.totals.single.amount, 300);
      expect(item.totals.single.unit, g);
      final note = item.contributions.firstWhere(
        (c) => c.label.contains('unrecognised unit'),
      );
      expect(note.label, contains('Cookies'));
      expect(note.label, contains('"scoop"'));
      expect(note.quantity, isNull); // renders as a dash, not an invented sum
    });

    test('merges duplicate live entries per ingredient (two-device)', () {
      // Two offline devices each created an entry for flour; after sync both
      // rows are live. The merge must keep BOTH manual top-ups, be checked if
      // either was, and pick the oldest row as the canonical entry id.
      final list = build(
        cook: [_cook('flour', 100, g)],
        entries: [
          _entry(
            'e-newer',
            ingredientId: 'flour',
            checked: true,
            createdAt: '2026-08-25T10:00:00Z',
          ),
          _entry(
            'e-older',
            ingredientId: 'flour',
            createdAt: '2026-08-24T09:00:00Z',
          ),
        ],
        manual: {
          'e-older': [_manual('c1', 'e-older', 50, g)],
          'e-newer': [_manual('c2', 'e-newer', 25, g)],
        },
        meta: {'flour': metaFor('Flour', 'baking')},
      );
      final item = list.groups.single.items.single;
      expect(item.entryId, 'e-older'); // oldest row is canonical, everywhere
      expect(item.checked, isTrue); // any-checked
      expect(item.totals.single.amount, 175); // 100 + 50 + 25 — nothing lost
      expect(
        item.contributions
            .where((c) => c.source == ContributionSource.manual)
            .map((c) => c.contributionId),
        containsAll(['c1', 'c2']),
      );
    });

    test('duplicate-entry merge is deterministic without created_at', () {
      // Same createdAt (or none): the smaller id wins, on every device.
      final list = build(
        cook: [_cook('flour', 100, g)],
        entries: [
          _entry('e-b', ingredientId: 'flour'),
          _entry('e-a', ingredientId: 'flour'),
        ],
        meta: {'flour': metaFor('Flour', 'baking')},
      );
      expect(list.groups.single.items.single.entryId, 'e-a');
    });

    test('marks purely user-added lines removable, cook-derived not', () {
      final list = build(
        cook: [_cook('flour', 100, g)],
        entries: [
          // Flour: cook contribution + a top-up → not wholesale-removable.
          _entry('e1', ingredientId: 'flour', unit: g),
          // Salt: an ingredient that exists only as a manual top-up.
          _entry('e2', ingredientId: 'salt', unit: g),
          // Paper towels: a free-text non-food line.
          _entry('e3', freeText: 'Paper towels'),
        ],
        manual: {
          'e1': [_manual('c1', 'e1', 50, g)],
          'e2': [_manual('c2', 'e2', 10, g)],
        },
        meta: {
          'flour': metaFor('Flour', 'baking'),
          'salt': metaFor('Salt', 'spices & seasoning'),
        },
      );
      final flour = list.groups
          .firstWhere((g) => g.label == 'Baking')
          .items
          .single;
      expect(flour.hasCookContribution, isTrue);
      expect(flour.isUserAdded, isFalse);

      final salt = list.groups
          .firstWhere((g) => g.label == 'Spices & Seasoning')
          .items
          .single;
      expect(salt.hasCookContribution, isFalse);
      expect(salt.isUserAdded, isTrue);

      final paper = list.groups
          .firstWhere((g) => g.label == 'Non-food')
          .items
          .single;
      expect(paper.isUserAdded, isTrue);
    });

    test('measure contributions sum in grams with provenance intact', () {
      // "2 × potato, large" from a cook line + a 1-potato manual top-up:
      // one mass total (3 × 299 g), each breakdown line in its measure.
      final list = build(
        cook: [
          _cook('potato', 2, pieces, measure: _potatoLarge, recipe: 'Curry'),
        ],
        entries: [_entry('e1', ingredientId: 'potato')],
        manual: {
          'e1': [_manual('c1', 'e1', 1, pieces, measure: _potatoLarge)],
        },
        meta: {
          'potato': metaFor(
            'Potato',
            'produce',
            unit: pieces,
            measures: [_potatoLarge],
          ),
        },
      );
      final item = list.groups.single.items.single;
      expect(item.totals.single.unit.family, UnitFamily.mass);
      expect(item.totals.single.amount, closeTo(3 * 299, 1e-9));
      final cookLine = item.contributions.first;
      expect(cookLine.measure, _potatoLarge);
      expect(cookLine.quantity, 2);
      expect(cookLine.unit, isNull); // the measure IS the unit shown
      final manualLine = item.contributions.last;
      expect(manualLine.measure, _potatoLarge);
      expect(manualLine.quantity, 1);
    });

    test('a whole-unit hint rides a fractional measure-derived total', () {
      // ×0.75 scaling left 2.25 potatoes' worth of grams on the list.
      final list = build(
        cook: [
          _cook('potato', 2.25, pieces, measure: _potatoLarge, recipe: 'Stew'),
        ],
        meta: {
          'potato': metaFor(
            'Potato',
            'produce',
            unit: pieces,
            measures: [_potatoLarge],
          ),
        },
      );
      final item = list.groups.single.items.single;
      expect(item.wholeUnitHint, isNotNull);
      expect(item.wholeUnitHint!.buy, 3);
      expect(item.wholeUnitHint!.approx, isTrue);
      // The honest total is untouched — the hint never replaces it.
      expect(item.totals.single.amount, closeTo(2.25 * 299, 1e-9));
    });

    test('a fractional plain count on a measure-bearing food hints too', () {
      final list = build(
        cook: [_cook('potato', 2.25, pieces, recipe: 'Stew')],
        meta: {
          'potato': metaFor(
            'Potato',
            'produce',
            unit: pieces,
            measures: [_potatoLarge],
          ),
        },
      );
      final item = list.groups.single.items.single;
      expect(item.totals.single.amount, 2.25); // count stays a count
      expect(item.wholeUnitHint, isNotNull);
      expect(item.wholeUnitHint!.buy, 3);
      expect(item.wholeUnitHint!.approx, isFalse);
    });
  });
}
