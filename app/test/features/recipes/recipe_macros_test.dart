import 'package:ansi/core/units/macros.dart';
import 'package:ansi/core/units/measure.dart';
import 'package:ansi/core/units/units.dart';
import 'package:ansi/features/recipes/domain/component_math.dart';
import 'package:ansi/features/recipes/domain/recipe.dart';
import 'package:ansi/features/recipes/domain/recipe_macros.dart';
import 'package:ansi/shared/incomplete_macros.dart';
import 'package:flutter_test/flutter_test.dart';

const _per100 = Macros(kcal: 100, protein: 10, carb: 20, fat: 5);

LineItem _line(
  String ingredientId, {
  double? quantity,
  Unit unit = g,
  Measure? measure,
  String? measureId,
}) => LineItem(
  id: 'li-$ingredientId',
  ingredientId: ingredientId,
  ingredientName: ingredientId,
  unit: measure != null || measureId != null ? pieces : unit,
  quantity: quantity,
  measure: measure,
  measureId: measureId ?? measure?.id,
);

/// One vocab row: per-100 macros on [basis], plus the two row facts a line
/// can convert through — the density, and the piece weight (ADR-0015).
IngredientNutrition _nutrition({
  Macros? macros = _per100,
  MacrosBasis basis = MacrosBasis.perG,
  double? density,
  double? pieceBasisAmount,
}) => (
  macros: macros,
  basis: basis,
  densityGPerMl: density,
  pieceBasisAmount: pieceBasisAmount,
);

/// A one-ingredient vocabulary for most cases below.
IngredientNutrition? Function(String) _vocab({
  Macros? macros = _per100,
  MacrosBasis basis = MacrosBasis.perG,
  double? density,
  double? pieceBasisAmount,
}) =>
    (id) => id == 'missing'
    ? null
    : _nutrition(
        macros: macros,
        basis: basis,
        density: density,
        pieceBasisAmount: pieceBasisAmount,
      );

void main() {
  group('the basis matrix', () {
    test('a mass line joins a per-100 g basis directly', () {
      final summary = summarizeRecipeMacros(
        servingsBase: 2,
        lines: [_line('x', quantity: 250)],
        nutritionOf: _vocab(),
      );
      // 250 g × (100 kcal / 100 g) = 250 kcal → /2 servings.
      expect(summary.incomplete, isFalse);
      expect(summary.perServing!.kcal, 125);
      expect(summary.perServing!.protein, 12.5);
    });

    test('a volume line joins a per-100 ml basis directly — no density', () {
      final summary = summarizeRecipeMacros(
        servingsBase: 1,
        lines: [_line('x', quantity: 600, unit: ml)],
        nutritionOf: _vocab(basis: MacrosBasis.perMl),
      );
      expect(summary.incomplete, isFalse);
      expect(summary.perServing!.kcal, 600);
    });

    test('kg and l convert through their family before the basis', () {
      final summary = summarizeRecipeMacros(
        servingsBase: 1,
        lines: [_line('x', quantity: 0.5, unit: kg)],
        nutritionOf: _vocab(),
      );
      expect(summary.perServing!.kcal, 500);
    });

    test('a volume line bridges to a per-100 g basis via density', () {
      final summary = summarizeRecipeMacros(
        servingsBase: 1,
        lines: [_line('x', quantity: 100, unit: ml)],
        nutritionOf: _vocab(density: 1.02),
      );
      // 100 ml × 1.02 g/ml = 102 g → ×1.02 of the per-100 macros.
      expect(summary.incomplete, isFalse);
      expect(summary.perServing!.kcal, closeTo(102, 1e-9));
    });

    test('a mass line bridges to a per-100 ml basis via density', () {
      final summary = summarizeRecipeMacros(
        servingsBase: 1,
        lines: [_line('x', quantity: 204)],
        nutritionOf: _vocab(basis: MacrosBasis.perMl, density: 1.02),
      );
      // 204 g / 1.02 g/ml = 200 ml.
      expect(summary.incomplete, isFalse);
      expect(summary.perServing!.kcal, closeTo(200, 1e-9));
    });

    test('a cross-basis line without a density is honestly incomplete', () {
      final cases = [(ml, MacrosBasis.perG), (g, MacrosBasis.perMl)];
      for (final (unit, basis) in cases) {
        final summary = summarizeRecipeMacros(
          servingsBase: 1,
          lines: [_line('x', quantity: 100, unit: unit)],
          nutritionOf: _vocab(basis: basis),
        );
        expect(summary.incomplete, isTrue, reason: '$unit vs $basis');
        expect(summary.perServing, isNull);
        expect(summary.unconvertibleLines, 1);
      }
    });
  });

  group('stubs and unbridgeable lines', () {
    test('a stub ingredient marks the summary incomplete — never zeros', () {
      final summary = summarizeRecipeMacros(
        servingsBase: 2,
        lines: [_line('x', quantity: 100), _line('stub', quantity: 50)],
        nutritionOf: (id) =>
            id == 'stub' ? _nutrition(macros: null) : _nutrition(),
      );
      expect(summary.incomplete, isTrue);
      expect(summary.stubLines, 1);
      expect(summary.unconvertibleLines, 0);
    });

    test('an ingredient unknown locally counts as a stub', () {
      final summary = summarizeRecipeMacros(
        servingsBase: 1,
        lines: [_line('missing', quantity: 100)],
        nutritionOf: _vocab(),
      );
      expect(summary.stubLines, 1);
    });

    test('a count line without a measure cannot join — and says so in its own '
        'words, not as a failed conversion', () {
      final summary = summarizeRecipeMacros(
        servingsBase: 1,
        lines: [_line('x', quantity: 3, unit: pieces)],
        nutritionOf: _vocab(),
      );
      expect(summary.incomplete, isTrue);
      expect(summary.countLinesWithoutMeasure, 1);
      expect(summary.unconvertibleLines, 0);
    });

    test('a line pointing at a measure that has not synced in is NOT "needs a '
        'weight" — something weighs it, this device just cannot see it', () {
      final summary = summarizeRecipeMacros(
        servingsBase: 1,
        lines: [_line('x', quantity: 3, unit: pieces, measureId: 'm-unsynced')],
        nutritionOf: _vocab(),
      );
      expect(summary.countLinesWithoutMeasure, 0);
      expect(summary.unconvertibleLines, 1);
    });

    test('an imprecise line does NOT make the summary incomplete — it is the '
        'one bucket that does not', () {
      final summary = summarizeRecipeMacros(
        servingsBase: 1,
        lines: [
          _line('x', quantity: 100),
          _line('x', quantity: 1, unit: pinch),
        ],
        nutritionOf: _vocab(),
      );
      expect(summary.incomplete, isFalse);
      // The total is the sum of the REST: 100 g × 100 kcal/100 g.
      expect(summary.perServing!.kcal, 100);
      expect(summary.impreciseLines, 1);
      // Never "unconvertible": nothing failed to convert, and nothing was
      // ever weighed.
      expect(summary.unconvertibleLines, 0);
    });

    test('a numberless line marks the summary incomplete', () {
      final summary = summarizeRecipeMacros(
        servingsBase: 1,
        lines: [_line('x')],
        nutritionOf: _vocab(),
      );
      expect(summary.unconvertibleLines, 1);
    });
  });

  // --- ADR-0015: the piece weight -------------------------------------------
  // What one of the thing weighs is a ROW fact, like the density. With it, a
  // bare count is not a defect at all — it converts through the row's own
  // stated number, and nothing is invented on the way.

  group('the piece weight turns a bare count into a weight', () {
    test(
      'a bare count converts through it: quantity × weight ÷ 100 × macros',
      () {
        final summary = summarizeRecipeMacros(
          servingsBase: 1,
          lines: [_line('x', quantity: 2, unit: pieces)],
          nutritionOf: _vocab(pieceBasisAmount: 110),
        );
        // 2 × 110 g = 220 g → ×2.2 of the per-100 g macros.
        expect(summary.incomplete, isFalse);
        expect(summary.countLinesWithoutMeasure, 0);
        expect(summary.perServing!.kcal, closeTo(220, 1e-9));
        expect(summary.perServing!.protein, closeTo(22, 1e-9));
        expect(summary.notes, isEmpty);
      },
    );

    test('a fractional count is a fraction of the weight', () {
      final summary = summarizeRecipeMacros(
        servingsBase: 2,
        lines: [_line('x', quantity: 0.5, unit: pieces)],
        nutritionOf: _vocab(pieceBasisAmount: 110),
      );
      // 0.5 × 110 g = 55 g → 55 kcal, over two servings.
      expect(summary.perServing!.kcal, closeTo(27.5, 1e-9));
    });

    test('it joins the other lines rather than replacing them', () {
      final summary = summarizeRecipeMacros(
        servingsBase: 1,
        lines: [
          _line('x', quantity: 100),
          _line('x', quantity: 1, unit: pieces),
        ],
        nutritionOf: _vocab(pieceBasisAmount: 50),
      );
      expect(summary.perServing!.kcal, closeTo(150, 1e-9));
    });

    test('the weight is stated in the row BASIS: on a per-100 ml row a piece '
        'is millilitres, and needs no density to count', () {
      final summary = summarizeRecipeMacros(
        servingsBase: 1,
        lines: [_line('x', quantity: 3, unit: pieces)],
        nutritionOf: _vocab(basis: MacrosBasis.perMl, pieceBasisAmount: 15),
      );
      // 3 × 15 ml = 45 ml → ×0.45 of the per-100 ml macros.
      expect(summary.incomplete, isFalse);
      expect(summary.perServing!.kcal, closeTo(45, 1e-9));
    });

    test('a density is still needed exactly where it always was — the piece '
        'weight bridges the COUNT, never the families', () {
      final without = summarizeRecipeMacros(
        servingsBase: 1,
        lines: [_line('x', quantity: 100, unit: ml)],
        nutritionOf: _vocab(pieceBasisAmount: 110),
      );
      expect(without.incomplete, isTrue);
      expect(without.notes.single.reason, MacroLineReason.needsDensity);

      final with_ = summarizeRecipeMacros(
        servingsBase: 1,
        lines: [_line('x', quantity: 100, unit: ml)],
        nutritionOf: _vocab(density: 1.02, pieceBasisAmount: 110),
      );
      expect(with_.perServing!.kcal, closeTo(102, 1e-9));
    });

    test('with NO weight on the row the count is still needsWeight, and the '
        'summary says so in the words the household reads', () {
      final summary = summarizeRecipeMacros(
        servingsBase: 1,
        lines: [_line('x', quantity: 2, unit: pieces)],
        nutritionOf: _vocab(),
      );
      expect(summary.incomplete, isTrue);
      expect(summary.countLinesWithoutMeasure, 1);
      expect(summary.notes.single.reason, MacroLineReason.needsWeight);
      expect(incompleteNote(summary), '1 line needs a piece weight');
    });

    test('two unweighed counts read as two', () {
      final summary = summarizeRecipeMacros(
        servingsBase: 1,
        lines: [
          _line('a', quantity: 2, unit: pieces),
          _line('b', quantity: 1, unit: pieces),
        ],
        nutritionOf: _vocab(),
      );
      expect(incompleteNote(summary), '2 lines need a piece weight');
    });

    test('a line naming a measure that has not synced in is UNCHANGED — the '
        "row's piece weight is not what that line claimed", () {
      final summary = summarizeRecipeMacros(
        servingsBase: 1,
        lines: [_line('x', quantity: 3, measureId: 'm-unsynced')],
        nutritionOf: _vocab(pieceBasisAmount: 110),
      );
      expect(summary.incomplete, isTrue);
      expect(summary.countLinesWithoutMeasure, 0);
      expect(summary.unconvertibleLines, 1);
      expect(summary.perServing, isNull);
    });

    test(
      'a RESOLVED measure still wins: the line said "clove", not "piece"',
      () {
        const clove = Measure(id: 'm1', label: 'clove', amount: 3);
        final summary = summarizeRecipeMacros(
          servingsBase: 1,
          lines: [_line('x', quantity: 5, measure: clove)],
          nutritionOf: _vocab(pieceBasisAmount: 110),
        );
        expect(summary.perServing!.kcal, closeTo(15, 1e-9));
      },
    );

    test('a weight without a number is still no amount — nothing is assumed '
        'to be one of the thing', () {
      final summary = summarizeRecipeMacros(
        servingsBase: 1,
        lines: [_line('x', unit: pieces)],
        nutritionOf: _vocab(pieceBasisAmount: 110),
      );
      expect(summary.incomplete, isTrue);
      expect(summary.notes.single.reason, MacroLineReason.noAmount);
    });

    test('a stub row is a stub however much one of it weighs', () {
      final summary = summarizeRecipeMacros(
        servingsBase: 1,
        lines: [_line('x', quantity: 2, unit: pieces)],
        nutritionOf: _vocab(macros: null, pieceBasisAmount: 110),
      );
      expect(summary.stubLines, 1);
      expect(summary.countLinesWithoutMeasure, 0);
    });
  });

  group('pieceMeasureOf', () {
    test('a stated weight becomes the measure the converter already knows', () {
      final measure = pieceMeasureOf(_nutrition(pieceBasisAmount: 110));
      expect(measure, isNotNull);
      expect(measure!.id, 'piece');
      expect(measure.label, 'piece');
      expect(measure.amount, 110);
      expect(measure.basis, MacrosBasis.perG);
    });

    test('it carries the ROW basis, so a per-100 ml row measures in ml', () {
      final measure = pieceMeasureOf(
        _nutrition(basis: MacrosBasis.perMl, pieceBasisAmount: 15),
      );
      expect(measure!.basis, MacrosBasis.perMl);
      expect(measure.amount, 15);
    });

    test('no weight, no measure — nothing is invented to stand in for one', () {
      expect(pieceMeasureOf(_nutrition()), isNull);
      expect(pieceMeasureOf(_nutrition(macros: null)), isNull);
    });
  });

  group('measure lines', () {
    const clove = Measure(id: 'm1', label: 'clove', amount: 3);

    test('convert via grams into a per-100 g basis', () {
      final summary = summarizeRecipeMacros(
        servingsBase: 1,
        lines: [_line('x', quantity: 5, measure: clove)],
        nutritionOf: _vocab(),
      );
      // 5 cloves × 3 g = 15 g → ×0.15.
      expect(summary.perServing!.kcal, closeTo(15, 1e-9));
    });

    test('need a density to reach a per-100 ml basis', () {
      const halfCan = Measure(id: 'm2', label: 'half can', amount: 204);
      final with_ = summarizeRecipeMacros(
        servingsBase: 1,
        lines: [_line('x', quantity: 1, measure: halfCan)],
        nutritionOf: _vocab(basis: MacrosBasis.perMl, density: 1.02),
      );
      expect(with_.perServing!.kcal, closeTo(200, 1e-9));

      final without = summarizeRecipeMacros(
        servingsBase: 1,
        lines: [_line('x', quantity: 1, measure: halfCan)],
        nutritionOf: _vocab(basis: MacrosBasis.perMl),
      );
      expect(without.incomplete, isTrue);
      expect(without.unconvertibleLines, 1);
    });

    test('an unresolved measure id is unbridgeable until it syncs', () {
      final summary = summarizeRecipeMacros(
        servingsBase: 1,
        lines: [_line('x', quantity: 2, measureId: 'not-synced')],
        nutritionOf: _vocab(),
      );
      expect(summary.unconvertibleLines, 1);
    });

    test('invalid measure grams degrade honestly, never Infinity', () {
      const bad = Measure(id: 'm3', label: 'phantom', amount: 0);
      final summary = summarizeRecipeMacros(
        servingsBase: 1,
        lines: [_line('x', quantity: 2, measure: bad)],
        nutritionOf: _vocab(),
      );
      expect(summary.unconvertibleLines, 1);
    });
  });

  group('serving division', () {
    test('sums every line then divides by servings', () {
      final summary = summarizeRecipeMacros(
        servingsBase: 4,
        lines: [_line('a', quantity: 100), _line('b', quantity: 300)],
        nutritionOf: _vocab(),
      );
      expect(summary.perServing!.kcal, 100); // (100 + 300) / 4
      expect(summary.perServing!.fat, 5);
    });

    test('zero or negative servings guard: incomplete, never Infinity', () {
      for (final servings in [0.0, -2.0]) {
        final summary = summarizeRecipeMacros(
          servingsBase: servings,
          lines: [_line('x', quantity: 100)],
          nutritionOf: _vocab(),
        );
        expect(summary.incomplete, isTrue);
        expect(summary.perServing, isNull);
      }
    });

    test('an empty recipe is honestly incomplete — never ~0 kcal', () {
      // Nothing was summed, so a per-serving figure would be fabricated from
      // absence (invariant 3). The reason is distinct from any per-line
      // failure so the UI can say "no ingredients yet".
      final summary = summarizeRecipeMacros(
        servingsBase: 2,
        lines: const [],
        nutritionOf: _vocab(),
      );
      expect(summary.incomplete, isTrue);
      expect(summary.perServing, isNull);
      expect(summary.noLines, isTrue);
      expect(summary.stubLines, 0);
      expect(summary.unconvertibleLines, 0);
    });

    test('a recipe with lines never reads as line-less', () {
      final summary = summarizeRecipeMacros(
        servingsBase: 2,
        lines: [_line('x', quantity: 100)],
        nutritionOf: _vocab(),
      );
      expect(summary.noLines, isFalse);
      expect(summary.incomplete, isFalse);
    });
  });

  group('sub-recipe components', () {
    /// A component line asking for [quantity] [unit] of [subRecipeId].
    LineItem component(
      String subRecipeId, {
      double? quantity = 0.25,
      Unit unit = cup,
    }) => LineItem(
      id: 'li-$subRecipeId',
      subRecipeId: subRecipeId,
      ingredientName: subRecipeId,
      unit: unit,
      quantity: quantity,
    );

    /// The aioli: serves 4, makes 1 cup, one 200 g ingredient line.
    SubRecipeNode aioli({
      List<YieldDenomination> yields = const [(qty: 1.0, unit: cup)],
      List<LineItem> lines = const [],
    }) => (
      servingsBase: 4,
      lines: lines.isEmpty ? [_line('x', quantity: 200)] : lines,
      yields: yields,
    );

    test('a resolvable component contributes target TOTAL × batches', () {
      // The aioli totals 200 kcal; ¼ of a batch is 50 kcal, over 2 servings.
      final summary = summarizeRecipeMacros(
        servingsBase: 2,
        lines: [component('aioli')],
        nutritionOf: _vocab(),
        subRecipeOf: (id) => id == 'aioli' ? aioli() : null,
      );
      expect(summary.incomplete, isFalse);
      expect(summary.perServing!.kcal, 25);
    });

    test('it sums alongside the parent’s own ingredient lines', () {
      final summary = summarizeRecipeMacros(
        servingsBase: 1,
        lines: [_line('x', quantity: 100), component('aioli')],
        nutritionOf: _vocab(),
        subRecipeOf: (id) => id == 'aioli' ? aioli() : null,
      );
      expect(summary.perServing!.kcal, 150); // 100 + 50
    });

    test('a `batch` line takes the whole target, no yield needed', () {
      final summary = summarizeRecipeMacros(
        servingsBase: 1,
        lines: [component('aioli', quantity: 2, unit: batches)],
        nutritionOf: _vocab(),
        subRecipeOf: (id) => id == 'aioli' ? aioli(yields: const []) : null,
      );
      expect(summary.perServing!.kcal, 400);
    });

    test('no yield ⇒ "1 sub-recipe unresolved", never a 1× assumption', () {
      final summary = summarizeRecipeMacros(
        servingsBase: 2,
        lines: [component('aioli')],
        nutritionOf: _vocab(),
        subRecipeOf: (id) => id == 'aioli' ? aioli(yields: const []) : null,
      );
      expect(summary.incomplete, isTrue);
      expect(summary.perServing, isNull);
      expect(summary.subRecipesUnresolved, 1);
      expect(summary.subRecipesIncomplete, 0);
      expect(summary.stubLines, 0);
    });

    test('a family mismatch is unresolved too', () {
      final summary = summarizeRecipeMacros(
        servingsBase: 2,
        lines: [component('aioli', quantity: 2, unit: pieces)],
        nutritionOf: _vocab(),
        subRecipeOf: (id) => id == 'aioli' ? aioli() : null,
      );
      expect(summary.subRecipesUnresolved, 1);
    });

    test('a target whose own summary refuses ⇒ "1 sub-recipe incomplete" — the '
        'share is known, the macros behind it are not', () {
      final summary = summarizeRecipeMacros(
        servingsBase: 2,
        lines: [component('aioli')],
        nutritionOf: _vocab(),
        subRecipeOf: (id) => id == 'aioli'
            ? aioli(lines: [_line('missing', quantity: 100)])
            : null,
      );
      expect(summary.incomplete, isTrue);
      expect(summary.subRecipesIncomplete, 1);
      expect(summary.subRecipesUnresolved, 0);
    });

    test('a dangling link is unresolved — nothing derives from a link whose '
        'other end is gone', () {
      final summary = summarizeRecipeMacros(
        servingsBase: 2,
        lines: [component('ghost')],
        nutritionOf: _vocab(),
        subRecipeOf: (_) => null,
      );
      expect(summary.subRecipesUnresolved, 1);
    });

    test('without a resolver every component line is unresolved', () {
      final summary = summarizeRecipeMacros(
        servingsBase: 2,
        lines: [component('aioli')],
        nutritionOf: _vocab(),
      );
      expect(summary.subRecipesUnresolved, 1);
    });

    test('recursion folds a component of a component', () {
      // top → 1 batch of mid → ½ cup of a 1-cup aioli (200 kcal) + its own
      // 100 g line = 200 kcal for mid, over 1 serving of top.
      final nodes = <String, SubRecipeNode>{
        'mid': (
          servingsBase: 2,
          lines: [_line('x', quantity: 100), component('aioli', quantity: 0.5)],
          yields: const [(qty: 1.0, unit: cup)],
        ),
        'aioli': aioli(),
      };
      final summary = summarizeRecipeMacros(
        servingsBase: 1,
        lines: [component('mid', quantity: 1, unit: batches)],
        nutritionOf: _vocab(),
        subRecipeOf: (id) => nodes[id],
      );
      expect(summary.incomplete, isFalse);
      expect(summary.perServing!.kcal, 200);
    });

    test('a cycle renders incomplete and never loops', () {
      final nodes = <String, SubRecipeNode>{
        'a': (
          servingsBase: 1,
          lines: [component('b', quantity: 1, unit: batches)],
          yields: const [(qty: 1.0, unit: cup)],
        ),
        'b': (
          servingsBase: 1,
          lines: [component('a', quantity: 1, unit: batches)],
          yields: const [(qty: 1.0, unit: cup)],
        ),
      };
      final summary = summarizeRecipeMacros(
        servingsBase: 1,
        lines: [component('a', quantity: 1, unit: batches)],
        nutritionOf: _vocab(),
        subRecipeOf: (id) => nodes[id],
      );
      expect(summary.incomplete, isTrue);
      // a's own summary refuses (b's does, because of the visited guard), so
      // the parent reads "1 sub-recipe incomplete".
      expect(summary.subRecipesIncomplete, 1);
    });

    test('two unresolved components count as two', () {
      final summary = summarizeRecipeMacros(
        servingsBase: 2,
        lines: [component('a'), component('b')],
        nutritionOf: _vocab(),
        subRecipeOf: (_) => null,
      );
      expect(summary.subRecipesUnresolved, 2);
    });
  });

  // --- seam D5 + D6 --------------------------------------------------------
  // The refusal names its causes, and `imprecise` is a RULE rather than a
  // defect. The owner's two sentences: "this message makes it impossible to
  // know what ingredients need fixing" and "things that are to taste, or
  // imprecise should[n't] be required or show up in macros".

  group('the named lines', () {
    test('every excluded line is named, in line order, with its reason', () {
      final summary = summarizeRecipeMacros(
        servingsBase: 1,
        lines: [
          _line('x', quantity: 100),
          _line('missing', quantity: 50),
          _line('stub', quantity: 50),
          _line('count', quantity: 2, unit: pieces),
          _line('none'),
        ],
        nutritionOf: (id) => switch (id) {
          'missing' => null,
          'stub' => _nutrition(macros: null),
          _ => _nutrition(),
        },
      );
      expect(summary.notes.map((n) => n.reason), [
        MacroLineReason.unknownIngredient,
        MacroLineReason.stubIngredient,
        MacroLineReason.needsWeight,
        MacroLineReason.noAmount,
      ]);
      // …and each names the ROW it is waiting on, so a surface can mark it in
      // place rather than making the reader hunt for it.
      expect(summary.notes.map((n) => n.lineId), [
        'li-missing',
        'li-stub',
        'li-count',
        'li-none',
      ]);
      expect(summary.notes.first.name, 'missing');
    });

    test('a cross-basis line with no density says "needs a density", not the '
        'anonymous "unconvertible"', () {
      final summary = summarizeRecipeMacros(
        servingsBase: 1,
        lines: [_line('x', quantity: 1, unit: cup)],
        nutritionOf: _vocab(),
      );
      expect(summary.notes.single.reason, MacroLineReason.needsDensity);
      // The COUNT bucket is untouched, so `incompleteNote` still says exactly
      // what it said before.
      expect(summary.unconvertibleLines, 1);
    });

    test('a component names the TARGET, with its own reason', () {
      final summary = summarizeRecipeMacros(
        servingsBase: 1,
        lines: [
          const LineItem(
            id: 'li-aioli',
            subRecipeId: 'r-aioli',
            subRecipe: SubRecipeTarget(id: 'r-aioli', title: 'Romesco Aioli'),
            ingredientName: 'Romesco Aioli',
            unit: batches,
            quantity: 1,
          ),
        ],
        nutritionOf: _vocab(),
        subRecipeOf: (_) => null,
      );
      expect(summary.notes.single.name, 'Romesco Aioli');
      expect(summary.notes.single.reason, MacroLineReason.subRecipeUnresolved);
    });

    test("a nested recipe's own exclusions do NOT propagate — a parent names "
        "its component line, never the child's lines", () {
      final nodes = <String, SubRecipeNode>{
        'a': (
          servingsBase: 1,
          lines: [
            _line('stub', quantity: 10),
            _line('x', quantity: 1, unit: pinch),
          ],
          yields: const [(qty: 1.0, unit: cup)],
        ),
      };
      final summary = summarizeRecipeMacros(
        servingsBase: 1,
        lines: [
          const LineItem(
            id: 'li-a',
            subRecipeId: 'a',
            subRecipe: SubRecipeTarget(id: 'a', title: 'Sauce'),
            ingredientName: 'Sauce',
            unit: batches,
            quantity: 1,
          ),
        ],
        nutritionOf: (id) =>
            id == 'stub' ? _nutrition(macros: null) : _nutrition(),
        subRecipeOf: (id) => nodes[id],
      );
      expect(summary.notes.single.name, 'Sauce');
      expect(summary.notes.single.reason, MacroLineReason.subRecipeIncomplete);
      expect(
        summary.impreciseLines,
        0,
        reason: "the child's pinch is the child's business",
      );
    });
  });

  group('imprecise never gates the total', () {
    test('handful goes with to taste — one word, one meaning, and the line '
        'carries its OWN printed word', () {
      for (final unit in [pinch, dash, handful, toTaste]) {
        final summary = summarizeRecipeMacros(
          servingsBase: 1,
          lines: [
            _line('x', quantity: 100),
            _line('herb', quantity: 1, unit: unit),
          ],
          nutritionOf: _vocab(),
        );
        expect(summary.incomplete, isFalse, reason: unit.id);
        expect(summary.perServing!.kcal, 100, reason: unit.id);
        expect(summary.impreciseLines, 1, reason: unit.id);
        expect(
          summary.notes.single.reason,
          MacroLineReason.imprecise,
          reason: unit.id,
        );
        expect(summary.notes.single.unit, unit.label, reason: unit.id);
      }
    });

    test('a bare count is still a bare count — the two are different claims, '
        'and only one of them is fixable', () {
      final summary = summarizeRecipeMacros(
        servingsBase: 1,
        lines: [
          _line('x', quantity: 100),
          _line('x', quantity: 2, unit: pieces),
        ],
        nutritionOf: _vocab(),
      );
      expect(summary.incomplete, isTrue);
      expect(summary.countLinesWithoutMeasure, 1);
      expect(summary.notes.single.reason, MacroLineReason.needsWeight);
    });

    test('a recipe of NOTHING but imprecise lines still refuses — 0 kcal there '
        'would be a fabrication, not a number', () {
      final summary = summarizeRecipeMacros(
        servingsBase: 1,
        lines: [
          _line('x', quantity: 1, unit: toTaste),
          _line('x', quantity: 1, unit: pinch),
        ],
        nutritionOf: _vocab(),
      );
      expect(summary.incomplete, isTrue);
      expect(summary.nothingWeighable, isTrue);
      expect(summary.perServing, isNull);
    });

    test('an imprecise line on a STUB row is still excluded by rule — a pinch '
        'of anything is still a pinch', () {
      final summary = summarizeRecipeMacros(
        servingsBase: 1,
        lines: [
          _line('x', quantity: 100),
          _line('stub', quantity: 1, unit: pinch),
        ],
        nutritionOf: (id) =>
            id == 'stub' ? _nutrition(macros: null) : _nutrition(),
      );
      expect(summary.incomplete, isFalse);
      expect(summary.stubLines, 0);
      expect(summary.impreciseLines, 1);
    });

    test('a MEASURE line is never imprecise, whatever unit it stores', () {
      const clove = Measure(id: 'm', label: 'clove', amount: 3);
      final summary = summarizeRecipeMacros(
        servingsBase: 1,
        lines: [_line('x', quantity: 2, measure: clove)],
        nutritionOf: _vocab(),
      );
      expect(summary.incomplete, isFalse);
      expect(summary.impreciseLines, 0);
    });
  });

  group('optional lines — through the effectiveLines seam', () {
    LineItem optional(String id, {double? quantity = 50, Unit unit = g}) =>
        _line(id, quantity: quantity, unit: unit).copyWith(optional: true);

    test('excluded by rule: the total shows, the line is named, nothing is '
        'incomplete', () {
      final summary = summarizeRecipeMacros(
        servingsBase: 1,
        lines: [_line('x', quantity: 100), optional('lime')],
        nutritionOf: _vocab(),
      );
      expect(summary.incomplete, isFalse);
      expect(summary.perServing!.kcal, 100); // the lime's 50 g added nothing
      expect(summary.optionalLines, 1);
      expect(summary.notes.single.reason, MacroLineReason.optional);
      expect(summary.notes.single.name, 'lime');
      expect(summary.notes.single.lineId, 'li-lime');
    });

    test('the seam runs first: an optional stub, or an optional pinch, is '
        'named once — as optional', () {
      final summary = summarizeRecipeMacros(
        servingsBase: 1,
        lines: [
          _line('x', quantity: 100),
          optional('missing'),
          optional('salt', quantity: null, unit: toTaste),
        ],
        nutritionOf: _vocab(),
      );
      expect(summary.incomplete, isFalse);
      expect(summary.stubLines, 0);
      expect(summary.impreciseLines, 0);
      expect(summary.optionalLines, 2);
      expect(
        summary.notes.map((n) => n.reason),
        everyElement(MacroLineReason.optional),
      );
    });

    test('composes with the imprecise exclusion — every one named, in line '
        'order', () {
      final summary = summarizeRecipeMacros(
        servingsBase: 1,
        lines: [
          _line('x', quantity: 100),
          optional('lime'),
          _line('parsley', unit: handful),
          optional('coriander'),
        ],
        nutritionOf: _vocab(),
      );
      expect(summary.incomplete, isFalse);
      expect(summary.impreciseLines, 1);
      expect(summary.optionalLines, 2);
      expect(summary.notes.map((n) => n.name), [
        'lime',
        'parsley',
        'coriander',
      ]);
    });

    test('a recipe whose lines are ALL optional summed nothing and still '
        'refuses — the same guard, shared', () {
      final summary = summarizeRecipeMacros(
        servingsBase: 1,
        lines: [
          optional('lime'),
          _line('salt', unit: toTaste),
        ],
        nutritionOf: _vocab(),
      );
      expect(summary.incomplete, isTrue);
      expect(summary.nothingWeighable, isTrue);
      expect(summary.noLines, isFalse);
    });

    test("a sub-recipe's own optional line leaves ITS total the same way, "
        'and the parent does not name it', () {
      LineItem component(String subId) => LineItem(
        id: 'c-$subId',
        subRecipeId: subId,
        subRecipe: SubRecipeTarget(id: subId, title: subId),
        ingredientName: subId,
        unit: batches,
        quantity: 1,
      );
      final summary = summarizeRecipeMacros(
        servingsBase: 1,
        lines: [component('aioli')],
        nutritionOf: _vocab(),
        subRecipeOf: (id) => id == 'aioli'
            ? (
                servingsBase: 1,
                lines: [_line('x', quantity: 100), optional('lime')],
                yields: const <YieldDenomination>[],
              )
            : null,
      );
      expect(summary.incomplete, isFalse);
      expect(summary.perServing!.kcal, 100); // 1 batch of the aioli, lime out
      expect(summary.optionalLines, 0);
      expect(summary.notes, isEmpty);
    });
  });

  group('the per-line record — the other half of the same walk', () {
    /// A component line asking for [quantity] [unit] of [subRecipeId].
    LineItem component(
      String subRecipeId, {
      double? quantity = 0.25,
      Unit unit = cup,
    }) => LineItem(
      id: 'li-$subRecipeId',
      subRecipeId: subRecipeId,
      ingredientName: subRecipeId,
      unit: unit,
      quantity: quantity,
    );

    test('every line that joined is recorded with what it contributed', () {
      final summary = summarizeRecipeMacros(
        servingsBase: 2,
        lines: [_line('x', quantity: 250), _line('y', quantity: 50)],
        nutritionOf: _vocab(),
      );
      expect(
        summary.lineMacros['li-x'],
        const Macros(kcal: 250, protein: 25, carb: 50, fat: 12.5),
      );
      expect(summary.lineMacros['li-y']!.kcal, 50);
    });

    test('the recorded lines sum back to the total the summary published', () {
      final summary = summarizeRecipeMacros(
        servingsBase: 4,
        lines: [
          _line('x', quantity: 250),
          _line('y', quantity: 50),
          _line('z', quantity: 0.5, unit: kg),
        ],
        nutritionOf: _vocab(),
      );
      final summed = summary.lineMacros.values.reduce((a, b) => a + b);
      expect(summed.scaledBy(1 / 4), summary.perServing);
    });

    test('an excluded line is in the notes and NOT in the record — never a '
        'zero (invariant 3)', () {
      final summary = summarizeRecipeMacros(
        servingsBase: 1,
        lines: [
          _line('x', quantity: 100),
          _line('missing', quantity: 100),
          _line('parsley', unit: handful),
          _line('lime', quantity: 50).copyWith(optional: true),
        ],
        nutritionOf: _vocab(),
      );
      expect(summary.lineMacros.keys, ['li-x']);
      expect(summary.notes.map((n) => n.lineId), [
        'li-missing',
        'li-parsley',
        'li-lime',
      ]);
    });

    test('a line that resolved is recorded even while the SUMMARY refuses — '
        'the line stays honest about itself', () {
      final summary = summarizeRecipeMacros(
        servingsBase: 1,
        lines: [_line('x', quantity: 100), _line('missing', quantity: 100)],
        nutritionOf: _vocab(),
      );
      expect(summary.incomplete, isTrue);
      expect(summary.perServing, isNull);
      expect(summary.lineMacros['li-x']!.kcal, 100);
    });

    test('a component line records the WHOLE share it contributed, and the '
        'nested lines never appear', () {
      final summary = summarizeRecipeMacros(
        servingsBase: 1,
        lines: [component('aioli')],
        nutritionOf: _vocab(),
        subRecipeOf: (id) => id == 'aioli'
            ? (
                servingsBase: 4,
                lines: [_line('x', quantity: 200)],
                yields: const [(qty: 1.0, unit: cup)],
              )
            : null,
      );
      // A quarter of a 200 kcal batch; `li-x` belongs to the aioli, not here.
      expect(summary.lineMacros.keys, ['li-aioli']);
      expect(summary.lineMacros['li-aioli']!.kcal, 50);
    });

    test('two summaries differing only in the record are not equal', () {
      const withRecord = RecipeMacroSummary(
        perServing: _per100,
        lineMacros: {'li-x': _per100},
      );
      const without = RecipeMacroSummary(perServing: _per100);
      expect(withRecord == without, isFalse);
      expect(
        withRecord,
        const RecipeMacroSummary(
          perServing: _per100,
          lineMacros: {'li-x': _per100},
        ),
      );
    });
  });

  group('fibre — optional per row, all-or-nothing in the total', () {
    const withFibre = Macros(
      kcal: 100,
      protein: 10,
      carb: 20,
      fat: 5,
      fiber: 3,
    );

    /// Rows that state fibre, and the named ones that do not. `missing` is
    /// unknown to the vocabulary, as everywhere else in this file.
    IngredientNutrition? Function(String) vocab(Set<String> without) =>
        (id) => id == 'missing'
        ? null
        : _nutrition(macros: without.contains(id) ? _per100 : withFibre);

    test('every line stating fibre totals it', () {
      final summary = summarizeRecipeMacros(
        servingsBase: 2,
        lines: [_line('x', quantity: 250), _line('y', quantity: 50)],
        nutritionOf: vocab(const {}),
      );
      expect(summary.incomplete, isFalse);
      // (250 g × 3 g/100 g) + (50 g × 3 g/100 g) = 9 g, over 2 servings.
      expect(summary.perServing!.fiber, 4.5);
      expect(summary.linesWithoutFiber, isEmpty);
    });

    test('one line without it costs the TOTAL its fibre, and names the '
        'line', () {
      final summary = summarizeRecipeMacros(
        servingsBase: 2,
        lines: [
          _line('onion', quantity: 250),
          _line('carrot', quantity: 50),
          _line('stock', quantity: 100),
        ],
        nutritionOf: vocab(const {'onion', 'stock'}),
      );
      // The lines are all IN the total — fibre is optional, not a defect.
      expect(summary.incomplete, isFalse);
      expect(summary.perServing!.kcal, 200);
      expect(summary.notes, isEmpty);
      // What it costs is the fifth figure, and the rows are named in line
      // order rather than dropped in silence.
      expect(summary.perServing!.fiber, isNull);
      expect(summary.linesWithoutFiber, ['onion', 'stock']);
      expect(
        fiberNotCountedNote(summary),
        'fibre not counted · 2 lines without it: onion, stock',
      );
    });

    test('one line reads as one line, not two', () {
      final summary = summarizeRecipeMacros(
        servingsBase: 1,
        lines: [_line('x', quantity: 100), _line('stock', quantity: 100)],
        nutritionOf: vocab(const {'stock'}),
      );
      expect(
        fiberNotCountedNote(summary),
        'fibre not counted · 1 line without it: stock',
      );
    });

    test('a total that states fibre has no note to print', () {
      final summary = summarizeRecipeMacros(
        servingsBase: 1,
        lines: [_line('x', quantity: 100)],
        nutritionOf: vocab(const {}),
      );
      expect(fiberNotCountedNote(summary), isNull);
    });

    test('an incomplete summary prints no fibre note — there is no total for '
        'it to qualify', () {
      final summary = summarizeRecipeMacros(
        servingsBase: 1,
        lines: [_line('x', quantity: 100), _line('missing', quantity: 100)],
        nutritionOf: vocab(const {}),
      );
      expect(summary.incomplete, isTrue);
      expect(fiberNotCountedNote(summary), isNull);
    });

    test('an EXCLUDED line never lands in the fibre list — it is not in the '
        'total to withhold anything from it', () {
      final summary = summarizeRecipeMacros(
        servingsBase: 1,
        lines: [
          _line('x', quantity: 250),
          _line('parsley', unit: handful),
          _line('lime', quantity: 50).copyWith(optional: true),
        ],
        nutritionOf: vocab(const {'parsley', 'lime'}),
      );
      expect(summary.perServing!.fiber, 7.5);
      expect(summary.linesWithoutFiber, isEmpty);
      expect(fiberNotCountedNote(summary), isNull);
    });

    test('a sub-recipe whose own total states no fibre names the COMPONENT '
        'line, never the child’s lines', () {
      final summary = summarizeRecipeMacros(
        servingsBase: 1,
        lines: const [
          LineItem(
            id: 'li-aioli',
            subRecipeId: 'aioli',
            ingredientName: 'aioli',
            unit: cup,
            quantity: 0.25,
          ),
        ],
        nutritionOf: vocab(const {'stock'}),
        subRecipeOf: (id) => id == 'aioli'
            ? (
                servingsBase: 4,
                lines: [
                  _line('x', quantity: 200),
                  _line('stock', quantity: 100),
                ],
                yields: const [(qty: 1.0, unit: cup)],
              )
            : null,
      );
      expect(summary.incomplete, isFalse);
      expect(summary.perServing!.fiber, isNull);
      expect(summary.linesWithoutFiber, ['aioli']);
    });

    test('two summaries differing only in the fibre list are not equal', () {
      const named = RecipeMacroSummary(
        perServing: _per100,
        linesWithoutFiber: ['onion'],
      );
      const unnamed = RecipeMacroSummary(perServing: _per100);
      expect(named == unnamed, isFalse);
      expect(named.hashCode, isNot(unnamed.hashCode));
    });
  });
}
