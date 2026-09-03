import 'package:ansi/core/units/units.dart';
import 'package:ansi/features/recipes/domain/effective_lines.dart';
import 'package:ansi/features/recipes/domain/recipe.dart';
import 'package:flutter_test/flutter_test.dart';

LineItem _line(String id, {bool optional = false, SubRecipeTarget? sub}) =>
    LineItem(
      id: id,
      ingredientId: sub == null ? 'ing-$id' : null,
      subRecipeId: sub?.id,
      subRecipe: sub,
      ingredientName: id,
      unit: sub == null ? g : batches,
      quantity: 1,
      optional: optional,
    );

void main() {
  group('effectiveLines — the one seam every derivation runs over (D6b)', () {
    test(
      'nothing optional: every line kept, in stored order, nothing dropped',
      () {
        final lines = [_line('a'), _line('b'), _line('c')];
        final result = effectiveLines(lines);
        expect(result.kept, lines);
        expect(result.dropped, isEmpty);
      },
    );

    test('optional lines are dropped WITH a reason; both sides keep order', () {
      final lime = _line('lime', optional: true);
      final coriander = _line('coriander', optional: true);
      final result = effectiveLines([
        _line('rice'),
        lime,
        _line('onion'),
        coriander,
      ]);
      expect(result.kept.map((l) => l.id), ['rice', 'onion']);
      expect(result.dropped, [
        (line: lime, reason: LineDropReason.optional),
        (line: coriander, reason: LineDropReason.optional),
      ]);
    });

    test('planEntryId is the override seam: accepted, and unread today', () {
      // The per-week override (tick an optional line back in for one planned
      // week) is designed for, not built. Passing an entry must not change the
      // answer until it is — this pins the "nothing reads it yet" half.
      final lines = [_line('rice'), _line('lime', optional: true)];
      final withEntry = effectiveLines(lines, planEntryId: 'pe-1');
      final without = effectiveLines(lines);
      expect(withEntry.kept, without.kept);
      expect(withEntry.dropped, without.dropped);
    });

    test(
      "droppedNames prints the ingredient name — or a component's title",
      () {
        const aioli = SubRecipeTarget(id: 'r-aioli', title: 'Romesco Aioli');
        final result = effectiveLines([
          _line('lime', optional: true),
          _line('c', optional: true, sub: aioli),
          _line('rice'),
        ]);
        expect(droppedNames(result, LineDropReason.optional), [
          'lime',
          'Romesco Aioli',
        ]);
      },
    );
  });
}
