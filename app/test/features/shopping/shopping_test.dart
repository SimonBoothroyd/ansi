import 'package:ansi/core/units/measure.dart';
import 'package:ansi/core/units/units.dart';
import 'package:ansi/features/recipes/domain/effective_lines.dart';
import 'package:ansi/features/shopping/domain/shopping.dart';
import 'package:flutter_test/flutter_test.dart';

const _weekdays = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];

const _potatoLarge = Measure(id: 'm1', label: 'potato, large', amount: 299);
const _can400 = Measure(id: 'm2', label: 'can (400 ml)', amount: 400);
const _proteinBar = Measure(id: 'm3', label: 'bar', amount: 60);

CookContributionInput _cook(
  String ingredientId,
  double qty,
  Unit? unit, {
  String? rawUnit,
  Measure? measure,
  String recipe = 'Recipe',
  int cookDay = 0,
  bool batched = false,
  List<String> forParents = const [],
  String? weekNote,
}) => (
  ingredientId: ingredientId,
  quantity: qty,
  unit: unit,
  rawUnit: rawUnit ?? unit?.id,
  measure: measure,
  recipeTitle: recipe,
  cookDay: cookDay,
  batched: batched,
  forParents: forParents,
  weekNote: weekNote,
);

/// A planned INGREDIENT meal's contribution — the week's own entry, already
/// multiplied by its demand (step 8.14 / A-D4).
PlanIngredientInput _planned(
  String ingredientId,
  double qty,
  Unit? unit, {
  String? rawUnit,
  Measure? measure,
  int day = 0,
  String slot = 'Snack',
}) => (
  ingredientId: ingredientId,
  quantity: qty,
  unit: unit,
  rawUnit: rawUnit ?? unit?.id,
  measure: measure,
  dayOfWeek: day,
  mealSlot: slot,
);

ManualContributionInput _manual(
  String id,
  String entryId,
  double qty,
  Unit? unit, {
  String? measureId,
  Measure? measure,
  String? note,
}) => (
  id: id,
  entryId: entryId,
  quantity: qty,
  unit: unit,
  measureId: measureId ?? measure?.id,
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
      const bad = Measure(id: 'mb', label: 'bad', amount: 0);
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
        measures: const [_potatoLarge],
      );
      expect(hint, isNotNull);
      expect(hint!.count, 2.25);
      expect(hint.buy, 3);
      expect(hint.unitLabel, 'piece');
      expect(hint.approx, isFalse);
    });

    test('a fractional count needs no measure — "2.25 piece → buy 3"', () {
      // A count is already a whole-thing tally: rounding it up invents
      // nothing, so the hint is un-gated for the count branch.
      final hint = wholeUnitHintFor(
        totals: [Quantity(2.25, pieces)],
        measures: const [],
      );
      expect(hint, isNotNull);
      expect(hint!.buy, 3);
      expect(hint.approx, isFalse);
    });

    test('derives a count from a mass total via the primary measure', () {
      final hint = wholeUnitHintFor(
        totals: [Quantity(674, g)],
        measures: const [_potatoLarge],
      );
      expect(hint, isNotNull);
      expect(hint!.count, closeTo(674 / 299, 1e-9));
      expect(hint.buy, 3);
      expect(hint.unitLabel, 'potato, large');
      expect(hint.approx, isTrue);
    });

    test('a mass total without any measure never hints', () {
      expect(
        wholeUnitHintFor(totals: [Quantity(674, g)], measures: const []),
        isNull,
      );
    });

    test('a mass-default item with a measure hints too (canned/blocks)', () {
      // Tofu defaults to oz (mass) but has a block measure: the hint applies
      // regardless of default-unit family — the measure is the purchasable
      // thing.
      const block = Measure(id: 'mt', label: 'block (14 oz)', amount: 397);
      final hint = wholeUnitHintFor(
        totals: [Quantity(600, g)],
        measures: const [block],
      );
      expect(hint, isNotNull);
      expect(hint!.buy, 2);
      expect(hint.unitLabel, 'block (14 oz)');
      expect(hint.approx, isTrue);
    });

    test('a whole total needs no hint', () {
      expect(
        wholeUnitHintFor(
          totals: [Quantity(3, pieces)],
          measures: const [_potatoLarge],
        ),
        isNull,
      );
      expect(
        wholeUnitHintFor(
          totals: [Quantity(598, g)], // exactly 2 × 299 g
          measures: const [_potatoLarge],
        ),
        isNull,
      );
    });

    test('mixed subtotals get no hint (it could not cover both)', () {
      expect(
        wholeUnitHintFor(
          totals: [Quantity(1.5, pieces), Quantity(100, g)],
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

    test('a component contribution gains one segment — deepest recipe first, '
        'then the plan it serves', () {
      expect(
        cookLabel(
          _cook(
            'x',
            1,
            g,
            recipe: 'Romesco Aioli',
            cookDay: 5,
            forParents: const ['Sliders'],
          ),
          _weekdays,
        ),
        'Romesco Aioli · for Sliders · cook Sat',
      );
    });

    test('two parents sharing one component batch are both named', () {
      expect(
        cookLabel(
          _cook(
            'x',
            1,
            g,
            recipe: 'Romesco Aioli',
            cookDay: 5,
            forParents: const ['Sliders', 'Toasts'],
          ),
          _weekdays,
        ),
        'Romesco Aioli · for Sliders + Toasts · cook Sat',
      );
    });

    test('a component contribution keeps its day even unbatched — the day is '
        'the actionable fact for a derived cook', () {
      final label = cookLabel(
        _cook('x', 1, g, recipe: 'Aioli', forParents: const ['Sliders']),
        _weekdays,
      );
      expect(label, contains('cook Mon'));
    });
  });

  group('buildShoppingList', () {
  group('ShoppingList sections (the aisles and the basket)', () {
    ShoppingItem item(String name, {bool checked = false}) =>
        ShoppingItem(name: name, ingredientId: name, checked: checked);

    final list = ShoppingList(
      groups: [
        ShoppingGroup(
          label: 'Produce',
          items: [item('Lime', checked: true), item('Onion')],
        ),
        ShoppingGroup(label: 'Baking', items: [item('Flour', checked: true)]),
        ShoppingGroup(label: 'Dairy', items: [item('Milk')]),
      ],
    );

    test('the open groups hold only what is still to grab', () {
      // Produce keeps Onion; Baking, all ticked, is gone from the top.
      expect(list.openGroups.map((g) => g.label), ['Produce', 'Dairy']);
      expect(list.openGroups.first.items.map((i) => i.name), ['Onion']);
      // …while the full list is untouched for whatever counts items.
      expect(list.groups, hasLength(3));
    });

    test('the basket is every ticked row, in aisle order', () {
      expect(list.basket.map((i) => i.name), ['Lime', 'Flour']);
      expect(list.allTicked, isFalse);
    });

    test('all ticked is known in one place', () {
      final done = ShoppingList(
        groups: [
          ShoppingGroup(label: 'Produce', items: [item('Lime', checked: true)]),
        ],
      );
      expect(done.allTicked, isTrue);
      expect(done.openGroups, isEmpty);
      expect(done.basket, hasLength(1));
      // An empty list is not a finished trip.
      expect(const ShoppingList().allTicked, isFalse);
    });
  });

    ShoppingList build({
      List<CookContributionInput> cook = const [],
      List<PlanIngredientInput> planned = const [],
      List<ShoppingEntryInput> entries = const [],
      Map<String, List<ManualContributionInput>> manual = const {},
      Map<String, IngredientMetaInput> meta = const {},
      List<UnresolvedComponentNote> unresolvedComponents = const [],
      List<OptionalLinesNote> optionalLines = const [],
      List<RetiredIngredientNote> retiredIngredients = const [],
    }) => buildShoppingList(
      cook: cook,
      planned: planned,
      entries: entries,
      manual: manual,
      meta: meta,
      weekdayShort: _weekdays,
      unresolvedComponents: unresolvedComponents,
      optionalLines: optionalLines,
      retiredIngredients: retiredIngredients,
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

    test('one measure everywhere: the total is a count of it', () {
      // "2 × potato, large" from a cook line + a 1-potato manual top-up: the
      // row reads 3 potatoes, with the grams they weigh beside it, and each
      // breakdown line keeps its own measure.
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
      expect(item.measureTotal, isNotNull);
      expect(item.measureTotal!.amount, 3);
      expect(item.measureTotal!.measure, _potatoLarge);
      // The mass the count weighs stays beside it, honest and untouched.
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

    group('a can of lentils', () {
      // The live repro: "1 can (400 g), drained" of Canned Lentils, whose can
      // is 240 g drained and whose default unit is oz. The shop used to print
      // "8.47 oz" — a number nobody asked for and nothing sells.
      const can = Measure(id: 'ml', label: 'can (400 g), drained', amount: 240);
      IngredientMetaInput lentils() =>
          metaFor('Canned Lentils', 'pantry', unit: oz, measures: const [can]);

      test('one measure everywhere: the row is counted in cans', () {
        final item = build(
          cook: [_cook('lentils', 1, pieces, measure: can, recipe: 'Dal')],
          meta: {'lentils': lentils()},
        ).groups.single.items.single;
        expect(item.measureTotal!.amount, 1);
        expect(item.measureTotal!.measure, can);
        // The default unit never reaches a measure-only sum: the mass beside
        // the count stays in the basis the can folded into.
        expect(item.totals.single.unit, g);
        expect(item.totals.single.amount, closeTo(240, 1e-9));
      });

      test('two cans are two cans, not 16.93 oz', () {
        final item = build(
          cook: [
            _cook('lentils', 1, pieces, measure: can, recipe: 'Dal'),
            _cook(
              'lentils',
              1,
              pieces,
              measure: can,
              recipe: 'Soup',
              cookDay: 2,
            ),
          ],
          meta: {'lentils': lentils()},
        ).groups.single.items.single;
        expect(item.measureTotal!.amount, 2);
        expect(item.totals.single.amount, closeTo(480, 1e-9));
      });

      test('a can plus 200 g has no count — the family sum prints as ever', () {
        final item = build(
          cook: [
            _cook('lentils', 1, pieces, measure: can, recipe: 'Dal'),
            _cook('lentils', 200, g, recipe: 'Salad', cookDay: 2),
          ],
          meta: {'lentils': lentils()},
        ).groups.single.items.single;
        expect(item.measureTotal, isNull);
        // A real mass line was stated, so the default unit biases it again.
        expect(item.totals.single.unit, oz);
        expect(item.totals.single.amount, closeTo(440 / 28.349523125, 1e-9));
        // …and each provenance line still keeps its own words.
        expect(item.contributions.first.measure, can);
        expect(item.contributions.first.quantity, 1);
        expect(item.contributions.last.unit, g);
        expect(item.contributions.last.quantity, 200);
      });
    });

    test('a measure-counted total needs no round-up hint', () {
      // ×0.75 scaling left 2.25 potatoes on the list. The count says so
      // itself, so the hint that used to reconstruct it from grams is gone.
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
      expect(item.measureTotal!.amount, closeTo(2.25, 1e-9));
      expect(item.wholeUnitHint, isNull);
      // The honest total is untouched — the count never replaces it.
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

    test('the count is said in the measure asked for, not the primary one', () {
      // Live repro from review: "2 × potato, large" with "medium" sorted
      // first must never be restated off the wrong denominator — the row
      // says 2 large, because that is what was asked for.
      const medium = Measure(id: 'mm', label: 'potato, medium', amount: 213);
      final list = build(
        cook: [
          _cook('potato', 2, pieces, measure: _potatoLarge, recipe: 'Stew'),
        ],
        meta: {
          'potato': metaFor(
            'Potato',
            'produce',
            unit: pieces,
            measures: [medium, _potatoLarge],
          ),
        },
      );
      final item = list.groups.single.items.single;
      expect(item.measureTotal!.measure, _potatoLarge);
      expect(item.measureTotal!.amount, 2);
      expect(item.totals.single.amount, closeTo(598, 1e-9));
      expect(item.wholeUnitHint, isNull);
    });

    test('two different measures have no single count — the mass sum wins', () {
      // A large potato and a medium one are not 3 of anything. The canonical
      // family sum is the only honest total, and each line keeps its words.
      const medium = Measure(id: 'mm', label: 'potato, medium', amount: 213);
      final list = build(
        cook: [
          _cook('potato', 2, pieces, measure: _potatoLarge, recipe: 'Stew'),
          _cook('potato', 1, pieces, measure: medium, recipe: 'Curry'),
        ],
        meta: {
          'potato': metaFor(
            'Potato',
            'produce',
            unit: pieces,
            measures: [medium, _potatoLarge],
          ),
        },
      );
      final item = list.groups.single.items.single;
      expect(item.measureTotal, isNull);
      expect(item.totals.single.amount, closeTo(2 * 299 + 213, 1e-9));
      expect(item.contributions.first.measure, _potatoLarge);
      expect(item.contributions.last.measure, medium);
    });

    test('an invalid measure is a visible note, never a silent drop', () {
      // grams = 0 (bad data past the DB check, e.g. a rogue local write):
      // the line must surface as "not counted", like an unrecognised unit —
      // not vanish from the breakdown while the total quietly shrinks.
      const bad = Measure(id: 'mb', label: 'mystery bag', amount: 0);
      final list = build(
        cook: [
          _cook('potato', 100, g, recipe: 'Curry'),
          _cook('potato', 2, pieces, measure: bad, recipe: 'Stew'),
        ],
        entries: [_entry('e1', ingredientId: 'potato')],
        manual: {
          'e1': [_manual('c1', 'e1', 1, pieces, measure: bad)],
        },
        meta: {'potato': metaFor('Potato', 'produce', unit: pieces)},
      );
      final item = list.groups.single.items.single;
      expect(item.totals.single.amount, 100); // only the honest 100 g
      final cookNote = item.contributions.firstWhere(
        (c) =>
            c.source == ContributionSource.cookSession &&
            c.label.contains('invalid measure'),
      );
      expect(cookNote.label, contains('Stew'));
      expect(cookNote.label, contains('"mystery bag"'));
      expect(cookNote.quantity, isNull);
      final manualNote = item.contributions.firstWhere(
        (c) => c.source == ContributionSource.manual,
      );
      expect(manualNote.label, contains('invalid measure'));
      expect(manualNote.quantity, isNull);
      expect(manualNote.contributionId, 'c1'); // still editable/removable
      expect(manualNote.measureId, 'mb'); // the FK is never stripped
    });

    test('a non-count unit beside a measure never folds invented mass', () {
      // Contradictory rows (a measure row always stores a count unit): the
      // number cannot honestly be both grams and a measure count, so it must
      // surface as a note — never 500 × 299 g, and never a hard 1 × 299 g
      // from an imprecise line that ignored the session scale.
      final list = build(
        cook: [
          _cook('potato', 100, g, recipe: 'Curry'),
          _cook('potato', 500, g, measure: _potatoLarge, recipe: 'Stew'),
          _cook('potato', 1, toTaste, measure: _potatoLarge, recipe: 'Soup'),
        ],
        entries: [_entry('e1', ingredientId: 'potato')],
        manual: {
          'e1': [_manual('c1', 'e1', 2, g, measure: _potatoLarge)],
        },
        meta: {'potato': metaFor('Potato', 'produce', unit: pieces)},
      );
      final item = list.groups.single.items.single;
      expect(item.totals.single.amount, 100); // only the honest plain line
      final notes = item.contributions
          .where((c) => c.label.contains('measure beside non-count unit'))
          .toList();
      expect(notes, hasLength(3));
      expect(notes.map((c) => c.label).join(), contains('"g"'));
      expect(notes.map((c) => c.label).join(), contains('"to taste"'));
      for (final n in notes) {
        expect(n.quantity, isNull); // a dash, not an invented number
        expect(n.measure, isNull); // and never fed to the mass fold
      }
      // The manual note stays editable and keeps its FK.
      final manualNote = notes.singleWhere(
        (c) => c.source == ContributionSource.manual,
      );
      expect(manualNote.contributionId, 'c1');
      expect(manualNote.measureId, 'm1');
    });

    test('a manual contribution keeps its unresolved measure_id', () {
      // The measure row hasn't synced: the breakdown line degrades to the
      // honest count, but the raw id rides along so an edit re-save can
      // preserve it (the review's A1 wipe).
      final list = build(
        cook: [_cook('potato', 1, pieces, recipe: 'Stew')],
        entries: [_entry('e1', ingredientId: 'potato')],
        manual: {
          'e1': [_manual('c1', 'e1', 2, pieces, measureId: 'm-ghost')],
        },
        meta: {'potato': metaFor('Potato', 'produce', unit: pieces)},
      );
      final item = list.groups.single.items.single;
      final manualLine = item.contributions.firstWhere(
        (c) => c.source == ContributionSource.manual,
      );
      expect(manualLine.measure, isNull);
      expect(manualLine.measureId, 'm-ghost');
      expect(manualLine.quantity, 2);
      expect(manualLine.unit, pieces); // honest count fallback
      expect(item.totals.single.amount, 3); // counts sum honestly
    });

    test('a component contributes through the pipeline, provenance naming both '
        'levels', () {
      // 240 g of almonds in a 1-cup aioli, at ¼ batch for Saturday's sliders.
      final list = build(
        cook: [
          _cook(
            'almonds',
            60,
            g,
            recipe: 'Romesco Aioli',
            cookDay: 5,
            forParents: const ['Sliders'],
          ),
        ],
        meta: {'almonds': metaFor('Almonds, blanched', 'pantry')},
      );
      final item = list.groups.single.items.single;
      expect(item.totals.single, Quantity(60, g));
      expect(
        item.contributions.single.label,
        'Romesco Aioli · for Sliders · cook Sat',
      );
    });

    test(
      'an ingredient used at BOTH levels sums into one line you buy once',
      () {
        final list = build(
          cook: [
            _cook('oil', 30, ml, recipe: 'Sausage Sliders', cookDay: 5),
            _cook(
              'oil',
              30,
              ml,
              recipe: 'Romesco Aioli',
              cookDay: 5,
              forParents: const ['Sliders'],
            ),
          ],
          meta: {'oil': metaFor('Olive oil', 'fats & oils', unit: ml)},
        );
        final item = list.groups.single.items.single;
        expect(item.totals.single, Quantity(60, ml));
        expect(item.contributions.map((c) => c.label), [
          'Sausage Sliders',
          'Romesco Aioli · for Sliders · cook Sat',
        ]);
      },
    );

    test('an unresolved component contributes NOTHING, and the echo says so '
        'rather than leaving the list quietly short', () {
      final list = build(
        cook: [_cook('pork', 500, g, recipe: 'Sausage Sliders', cookDay: 5)],
        meta: {'pork': metaFor('Pork mince', 'meat')},
        unresolvedComponents: const [
          (recipeId: 'sliders', recipeTitle: 'Sausage Sliders', count: 1),
        ],
      );
      // Nothing from the aioli is on the list — no invented quantity anywhere.
      expect(list.groups.expand((g) => g.items).map((i) => i.ingredientId), [
        'pork',
      ]);
      expect(list.unresolvedComponents, [
        (recipeId: 'sliders', recipeTitle: 'Sausage Sliders', count: 1),
      ]);
    });

    test('optional lines ride through as the per-recipe echo, untouched — the '
        'drop itself happened at the seam', () {
      final list = build(
        cook: [_cook('flour', 100, g)],
        meta: {'flour': metaFor('Flour', 'baking')},
        optionalLines: const [
          (
            recipeId: 'curry',
            recipeTitle: 'Weeknight Chicken Curry',
            names: ['lime', 'coriander'],
            lineIds: ['li-lime', 'li-coriander'],
            reason: LineDropReason.optional,
          ),
        ],
      );
      expect(list.groups.expand((g) => g.items).map((i) => i.ingredientId), [
        'flour',
      ]);
      expect(list.optionalLines.single.recipeTitle, 'Weeknight Chicken Curry');
      expect(list.optionalLines.single.names, ['lime', 'coriander']);
    });

    test('a line at a RETIRED ingredient rides through as its own echo — the '
        'builder never sees it as a contribution', () {
      final list = build(
        cook: [_cook('flour', 100, g)],
        meta: {'flour': metaFor('Flour', 'baking')},
        retiredIngredients: const [
          (
            heading: 'Curry',
            ingredientName: 'Sauerkraut',
            site: RetiredIngredientSite.recipeLine,
          ),
        ],
      );
      // Nothing named Sauerkraut is buyable: the drop happened upstream, where
      // the row's liveness is known, and this channel only carries the words.
      expect(list.groups.expand((g) => g.items).map((i) => i.ingredientId), [
        'flour',
      ]);
      expect(list.retiredIngredients.single.ingredientName, 'Sauerkraut');
      expect(list.retiredIngredients.single.heading, 'Curry');
    });

    test('no unresolved components means no echo at all', () {
      final list = build(
        cook: [_cook('flour', 100, g)],
        meta: {'flour': metaFor('Flour', 'baking')},
      );
      expect(list.unresolvedComponents, isEmpty);
      expect(list.retiredIngredients, isEmpty);
    });

    // --- A planned ingredient is bought, though nothing cooks it (8.14) -----

    group('a planned INGREDIENT meal', () {
      test('lands on the list with no cook session behind it at all', () {
        final list = build(
          planned: [_planned('bar', 2, pieces, measure: _proteinBar, day: 1)],
          meta: {'bar': metaFor('Protein bar', 'snacks')},
        );
        final item = list.groups.single.items.single;
        expect(item.name, 'Protein bar');
        // Two bars of 60 g, priced through the measure's stored weight.
        expect(item.totals.single.amount, 120);
        expect(item.totals.single.unit, g);
        final c = item.contributions.single;
        expect(c.source, ContributionSource.planEntry);
        // The provenance says WHEN, not what — the item's name is the what.
        expect(c.label, 'Snack · Tue');
      });

      test('it sums with a cook contribution of the same ingredient', () {
        final list = build(
          cook: [_cook('yoghurt', 200, g, recipe: 'Curry')],
          planned: [_planned('yoghurt', 170, g, day: 3)],
          meta: {'yoghurt': metaFor('Greek yoghurt', 'dairy')},
        );
        final item = list.groups.single.items.single;
        expect(item.totals.single.amount, 370);
        // The breakdown interleaves by day: the Monday cook, then Thursday.
        expect(item.contributions.map((c) => c.label), [
          'Curry',
          'Snack · Thu',
        ]);
      });

      test('an unrecognised unit is a note, never a number in the total', () {
        final list = build(
          planned: [_planned('bar', 2, null, rawUnit: 'scoop')],
          meta: {'bar': metaFor('Protein bar', 'snacks')},
        );
        final item = list.groups.single.items.single;
        expect(item.totals, isEmpty);
        expect(
          item.contributions.single.label,
          contains('not counted (unrecognised unit "scoop")'),
        );
      });

      test('an invalid measure is a note too, not invented grams', () {
        const broken = Measure(id: 'm9', label: 'bar', amount: 0);
        final list = build(
          planned: [_planned('bar', 2, pieces, measure: broken)],
          meta: {'bar': metaFor('Protein bar', 'snacks')},
        );
        final item = list.groups.single.items.single;
        expect(item.totals, isEmpty);
        expect(
          item.contributions.single.label,
          contains('not counted (invalid measure "bar")'),
        );
      });

      test('a stale checked row with only a removed snack drops off', () {
        final list = build(
          entries: [_entry('e1', ingredientId: 'bar', checked: true)],
          meta: {'bar': metaFor('Protein bar', 'snacks')},
        );
        expect(list.groups, isEmpty);
      });
    });
  });
}
