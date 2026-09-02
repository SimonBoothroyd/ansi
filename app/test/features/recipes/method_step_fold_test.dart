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

    test('a blank-labelled collective stays label-less — the names ride on '
        'the constituents instead (J1)', () {
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

    test('a blank-labelled collective carries them too — they ARE its chips '
        '(J1)', () {
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
}
