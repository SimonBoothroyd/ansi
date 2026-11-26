import 'package:ansi/core/units/units.dart';
import 'package:ansi/features/recipes/domain/method_step.dart';
import 'package:ansi/features/recipes/domain/recipe.dart';
import 'package:flutter_test/flutter_test.dart';

LineItem _li(String id, {double? qty, Unit unit = g}) => LineItem(
  id: id,
  ingredientId: 'ing-$id',
  ingredientName: id,
  unit: unit,
  quantity: qty,
);

/// Runs the fold and returns only the chip amounts (null = quantity-less),
/// in order.
List<String?> _chipAmounts(
  MethodStep step, {
  required Map<String, LineItem> lineById,
  double factor = 1,
}) => foldMethod(
  step,
  lineById: lineById,
  factor: factor,
).whereType<MethodChipSpan>().map((c) => c.amount).toList();

void main() {
  final lines = {
    'flour': _li('flour', qty: 200),
    'eggs': _li('eggs', qty: 2, unit: pieces),
    'salt': _li('salt', unit: toTaste),
    'stock': _li('stock', qty: 2.5, unit: cup),
  };

  group('chip number derivation', () {
    test('first mention (isNew) shows the line quantity', () {
      const step = MethodStep(
        tokens: [
          MethodText(s: 'Add the '),
          MethodRef(refs: ['flour'], label: 'flour'),
          MethodText(s: '.'),
        ],
      );
      expect(_chipAmounts(step, lineById: lines), ['200 g']);
    });

    test('a re-mention is quantity-less', () {
      const step = MethodStep(
        tokens: [
          MethodRef(
            refs: ['flour'],
            label: 'flour',
            amountRule: ChipAmountRule.hideAmount,
          ),
        ],
      );
      expect(_chipAmounts(step, lineById: lines), [null]);
    });

    test('a count reads as a bare number; an imprecise unit as its word', () {
      const step = MethodStep(
        tokens: [
          MethodRef(refs: ['eggs'], label: 'eggs'),
          MethodRef(refs: ['salt'], label: 'salt'),
        ],
      );
      expect(_chipAmounts(step, lineById: lines), ['2', 'to taste']);
    });

    test('a collective chip (more than one ref) shows no number', () {
      const step = MethodStep(
        tokens: [
          MethodRef(refs: ['flour', 'eggs'], label: 'the dry ingredients'),
        ],
      );
      expect(_chipAmounts(step, lineById: lines), [null]);
    });

    test('a step portion wins over the line qty, even on a re-mention', () {
      const step = MethodStep(
        tokens: [
          MethodRef(
            refs: ['stock'],
            label: 'stock',
            amountRule: ChipAmountRule.partial,
            portion: StepPortion(qty: 1, unit: 'cup'),
          ),
        ],
      );
      expect(_chipAmounts(step, lineById: lines), ['1 cup']);
    });

    test('a qualifier-only portion renders the relative word, no number', () {
      const step = MethodStep(
        tokens: [
          MethodRef(
            refs: ['salt'],
            label: 'salt',
            portion: StepPortion(qualifier: 'for garnish'),
          ),
        ],
      );
      expect(_chipAmounts(step, lineById: lines), ['for garnish']);
    });
  });

  group('chip label', () {
    List<String> labelsOf(MethodStep step) => foldMethod(
      step,
      lineById: lines,
    ).whereType<MethodChipSpan>().map((c) => c.label).toList();

    test('the token label wins when it has one', () {
      const step = MethodStep(
        tokens: [
          MethodRef(refs: ['flour'], label: 'the flour'),
        ],
      );
      expect(labelsOf(step), ['the flour']);
    });

    test('a BLANK label falls back to the line item ingredient', () {
      // The shipped bug: steps read "Add the chopped 1, 0.5, 0.25" — amounts
      // with no ingredient — because the chip rendered an empty label.
      const step = MethodStep(
        tokens: [
          MethodRef(refs: ['flour'], label: ''),
        ],
      );
      expect(labelsOf(step), ['flour']);
    });

    test('a blank-labelled collective stays label-less — the names ride on the '
        'constituents instead', () {
      const step = MethodStep(
        tokens: [
          MethodRef(refs: ['flour', 'eggs', 'ghost'], label: '   '),
        ],
      );
      // Joining them made one un-wrappable mega-chip that overflowed the step.
      expect(labelsOf(step), ['']);
    });

    test('an unresolvable blank-label chip stays empty, never invented', () {
      const step = MethodStep(
        tokens: [
          MethodRef(refs: ['ghost'], label: ''),
        ],
      );
      expect(labelsOf(step), ['']);
    });
  });

  group('collective constituents', () {
    List<List<String>> constituentsOf(MethodStep step) => foldMethod(
      step,
      lineById: lines,
    ).whereType<MethodChipSpan>().map((c) => c.constituents).toList();

    test('a named collective chip carries its lines, in ref order', () {
      const step = MethodStep(
        tokens: [
          MethodRef(refs: ['eggs', 'flour'], label: 'the dry ingredients'),
        ],
      );
      expect(constituentsOf(step), [
        ['eggs', 'flour'],
      ]);
    });

    test('a single-ref chip has none — there is nothing to unpack', () {
      const step = MethodStep(
        tokens: [
          MethodRef(refs: ['flour'], label: 'the flour'),
        ],
      );
      expect(constituentsOf(step), [<String>[]]);
    });

    test('a blank-labelled collective carries them too — they ARE its '
        'chips', () {
      const step = MethodStep(
        tokens: [
          MethodRef(refs: ['flour', 'eggs'], label: ''),
        ],
      );
      expect(constituentsOf(step), [
        ['flour', 'eggs'],
      ]);
    });

    test('a dropped ref is skipped, never named', () {
      const step = MethodStep(
        tokens: [
          MethodRef(refs: ['flour', 'ghost', 'eggs'], label: 'the base'),
        ],
      );
      expect(constituentsOf(step), [
        ['flour', 'eggs'],
      ]);
    });
  });

  group('scaling', () {
    test('a first-mention line quantity and a numeric portion both scale', () {
      const step = MethodStep(
        tokens: [
          MethodRef(refs: ['flour'], label: 'flour'),
          MethodRef(
            refs: ['stock'],
            label: 'stock',
            portion: StepPortion(qty: 1, unit: 'cup'),
          ),
        ],
      );
      expect(_chipAmounts(step, lineById: lines, factor: 2), [
        '400 g',
        '2 cup',
      ]);
    });

    test('scaled, a spoon reads what a measuring set holds; as written, '
        'as written', () {
      final spoons = {
        ...lines,
        'cumin': _li('cumin', qty: 1, unit: tsp),
        'onion': _li('onion', qty: 1, unit: pieces),
      };
      const step = MethodStep(
        tokens: [
          MethodRef(refs: ['cumin'], label: 'cumin'),
          MethodRef(refs: ['onion'], label: 'onion'),
          MethodRef(
            refs: ['stock'],
            label: 'stock',
            portion: StepPortion(qty: 1, unit: 'tbsp'),
          ),
        ],
      );
      // 1¾ servings of a recipe for four.
      expect(_chipAmounts(step, lineById: spoons, factor: 1.75 / 4), [
        '½ tsp',
        '½',
        '1¼ tsp',
      ]);
      expect(_chipAmounts(step, lineById: spoons), ['1 tsp', '1', '1 tbsp']);
    });
  });

  group('timer formatting', () {
    List<String> timers(MethodStep step) => foldMethod(
      step,
      lineById: const {},
    ).whereType<MethodTimerSpan>().map((t) => t.text).toList();

    test('single, range, and multi-hour times', () {
      expect(
        timers(
          const MethodStep(
            tokens: [
              MethodTimer(lowSeconds: 600, highSeconds: 600),
              MethodTimer(lowSeconds: 540, highSeconds: 660),
              MethodTimer(lowSeconds: 9000, highSeconds: 9000),
            ],
          ),
        ),
        ['10 min', '9–11 min', '2 h 30 min'],
      );
    });
  });

  test('a missing line reference is quantity-less, never invented', () {
    const step = MethodStep(
      tokens: [
        MethodRef(refs: ['ghost'], label: 'ghost'),
      ],
    );
    expect(_chipAmounts(step, lineById: lines), [null]);
  });

  group('formatDuration — the one voice for a time', () {
    test('minutes, hours, and the honest odd seconds', () {
      expect(formatDuration(30), '30 s');
      expect(formatDuration(90), '1 min 30 s');
      expect(formatDuration(2100), '35 min');
      expect(formatDuration(3600), '1 h');
      expect(formatDuration(4200), '1 h 10 min');
    });

    test('a zero-width timer range is the same word', () {
      expect(formatTimerRange(2100, 2100), formatDuration(2100));
    });
  });

  group("a step's own amount", () {
    List<String> amounts(MethodStep step, double factor) => foldMethod(
      step,
      lineById: const {},
      factor: factor,
    ).whereType<MethodAmountSpan>().map((a) => a.text).toList();

    const water = MethodStep(
      tokens: [
        MethodText(s: 'Fill '),
        MethodAmount(text: 'one empty can', qty: 1, unit: 'can'),
        MethodText(s: ' with water and add '),
        MethodAmount(text: '4 tablespoons', qty: 4, unit: 'tablespoons'),
        MethodText(s: ' of the pasta water, then '),
        MethodAmount(text: '2–3 cups', qty: 2, qtyHigh: 3, unit: 'cups'),
        MethodText(s: ' of stock, and '),
        MethodAmount(
          text: '60–80ml (4–5 tbsp)',
          qty: 4,
          qtyHigh: 5,
          unit: 'tbsp',
        ),
        MethodText(s: ' of water.'),
      ],
    );

    test('as written it reads as written', () {
      expect(amounts(water, 1), [
        'one empty can',
        '4 tablespoons',
        '2–3 cups',
        '60–80ml (4–5 tbsp)',
      ]);
    });

    test(
      'scaled, it says the figure as a cook measures it, in its own word',
      () {
        // 3½ servings of a recipe for 4: a can is said by hand, so ⅞ of one is
        // the whole can; cups keep their thirds.
        expect(amounts(water, 3.5 / 4), [
          '1 can',
          '3½ tablespoons',
          '1¾–2⅔ cups',
          '3½–4½ tbsp',
        ]);
        // A spoon too coarse steps down, as a line's amount does.
        // A range whose ends would land in different spoons is said in the
        // smaller one, whole.
        expect(amounts(water, 0.25), [
          '¼ can',
          '1 tablespoons',
          '½–¾ cups',
          '3–3¾ tsp',
        ]);
      },
    );

    test('it is stored with its words, and a token this build does not know '
        'reads as its words rather than failing the recipe', () {
      final json = const MethodToken.amount(
        text: '2–3 cups',
        qty: 2,
        qtyHigh: 3,
        unit: 'cups',
      ).toJson();
      expect(json['t'], 'amount');
      expect(json['qty_high'], 3);
      expect(MethodToken.fromJson(json), isA<MethodAmount>());
      expect(
        MethodToken.fromJson(const {'t': 'temperature', 'text': '200 °C'}),
        const MethodToken.text(s: '200 °C'),
      );
      expect(
        MethodToken.fromJson(const {'t': 'sketch'}),
        const MethodToken.text(s: ''),
      );
    });
  });
}
