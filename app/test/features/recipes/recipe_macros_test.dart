import 'package:ansi/core/units/macros.dart';
import 'package:ansi/core/units/measure.dart';
import 'package:ansi/core/units/units.dart';
import 'package:ansi/features/recipes/domain/component_math.dart';
import 'package:ansi/features/recipes/domain/recipe.dart';
import 'package:ansi/features/recipes/domain/recipe_macros.dart';
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

/// A one-ingredient vocabulary for most cases below.
IngredientNutrition? Function(String) _vocab({
  Macros? macros = _per100,
  MacrosBasis basis = MacrosBasis.perG,
  double? density,
}) =>
    (id) => id == 'missing'
    ? null
    : (macros: macros, basis: basis, densityGPerMl: density);

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
        nutritionOf: (id) => id == 'stub'
            ? (macros: null, basis: MacrosBasis.perG, densityGPerMl: null)
            : (macros: _per100, basis: MacrosBasis.perG, densityGPerMl: null),
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

    test('a count line without a measure cannot join', () {
      final summary = summarizeRecipeMacros(
        servingsBase: 1,
        lines: [_line('x', quantity: 3, unit: pieces)],
        nutritionOf: _vocab(),
      );
      expect(summary.unconvertibleLines, 1);
    });

    test('an imprecise-only line marks the summary incomplete', () {
      final summary = summarizeRecipeMacros(
        servingsBase: 1,
        lines: [
          _line('x', quantity: 100),
          _line('x', quantity: 1, unit: pinch),
        ],
        nutritionOf: _vocab(),
      );
      expect(summary.incomplete, isTrue);
      expect(summary.unconvertibleLines, 1);
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

  group('sub-recipe components (step 8.6 / D8)', () {
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

    test('a target whose own summary refuses ⇒ "1 sub-recipe incomplete" — '
        'the share is known, the macros behind it are not', () {
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
        'other end is gone (D5)', () {
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
}
