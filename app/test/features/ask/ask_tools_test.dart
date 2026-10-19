import 'dart:convert';

import 'package:ansi/core/units/units.dart';
import 'package:ansi/features/ask/domain/ask_tools.dart';
import 'package:ansi/features/recipes/domain/line_override.dart';
import 'package:ansi/features/recipes/domain/method_step.dart';
import 'package:ansi/features/recipes/domain/recipe.dart';
import 'package:flutter_test/flutter_test.dart';

LineItem _li(
  String id, {
  double? qty,
  Unit unit = g,
  String? name,
  bool optional = false,
}) => LineItem(
  id: id,
  ingredientId: 'ing-$id',
  ingredientName: name ?? id,
  unit: unit,
  quantity: qty,
  optional: optional,
);

Map<String, Object?> _json(String s) => jsonDecode(s) as Map<String, Object?>;

List<Map<String, Object?>> _lines(String s) => [
  for (final l in _json(s)['lines']! as List) l as Map<String, Object?>,
];

void main() {
  // Written for 4; a sauce with tamari and a glaze with more of it.
  final ragu = Recipe(
    id: 'r1',
    title: 'Ragù',
    servingsBase: 4,
    groups: [
      IngredientGroup(
        id: 'g1',
        name: 'Sauce',
        items: [
          _li('tamari', qty: 2, unit: tbsp, name: 'Tamari'),
          _li('garlic', qty: 4, unit: pieces, name: 'Garlic'),
          _li('salt', unit: toTaste, name: 'Salt'),
        ],
      ),
      IngredientGroup(
        id: 'g2',
        name: 'Glaze',
        items: [
          _li('tamari2', qty: 1, unit: tbsp, name: 'Tamari'),
          _li('chilli', qty: 1, unit: pieces, name: 'Chilli', optional: true),
        ],
      ),
    ],
    methodSteps: const [
      MethodStep(
        tokens: [
          MethodText(s: 'Fry the '),
          MethodRef(refs: ['garlic'], label: 'garlic'),
          MethodText(s: '.'),
        ],
      ),
      MethodStep(
        tokens: [
          MethodText(s: 'Simmer for '),
          MethodTimer(lowSeconds: 1200, highSeconds: 1500),
          MethodText(s: ', then rest '),
          MethodTimer(lowSeconds: 300, highSeconds: 300),
          MethodText(s: '.'),
        ],
      ),
    ],
  );

  group('recipe_lines — the app counts', () {
    test('every line is scaled and printed as the page prints it', () {
      final lines = _lines(recipeLinesResult(ragu, servings: 6));
      expect(lines.first, {
        'name': 'Tamari',
        'amount': '3 tbsp',
        'group': 'Sauce',
      });
      expect(lines[1]['amount'], '6');
      // An imprecise unit never scales.
      expect(lines[2]['amount'], 'to taste');
    });

    test('an ingredient asked for comes back on each line, with its group', () {
      final r = _json(
        recipeLinesResult(ragu, servings: 6, ingredient: 'tamari'),
      );
      expect(r['servings'], '6');
      expect(r['written_for'], '4');
      expect(
        [
          for (final l in r['lines']! as List)
            ((l as Map)['amount'], l['group']),
        ],
        [('3 tbsp', 'Sauce'), ('1½ tbsp', 'Glaze')],
      );
      expect(r.containsKey('note'), isFalse);
    });

    test(
      'a word that names no line returns every line, for a misheard name',
      () {
        final r = _json(
          recipeLinesResult(ragu, servings: 4, ingredient: 'tomorrow'),
        );
        expect((r['lines']! as List).length, 5);
        expect(r['note'], contains('no line is named "tomorrow"'));
      },
    );

    test("this week's variant is applied and what it leaves out is named", () {
      final r = _json(
        recipeLinesResult(
          ragu,
          servings: 8,
          overrides: const [
            LineOverride(
              id: 'o1',
              recipeLineItemId: 'garlic',
              action: LineOverrideAction.exclude,
            ),
          ],
          basis: "this week's plan: 8 portions",
        ),
      );
      final names = [for (final l in r['lines']! as List) (l as Map)['name']];
      expect(names, isNot(contains('Garlic')));
      // Optional lines are left out of the week's lines too.
      expect(names, isNot(contains('Chilli')));
      expect(r['left_out_this_week'], containsAll(['Garlic', 'Chilli']));
      expect(r['basis'], "this week's plan: 8 portions");
    });

    test('optional lines are marked on the page reading', () {
      final chilli = _lines(
        recipeLinesResult(ragu, servings: 4, ingredient: 'chilli'),
      ).single;
      expect(chilli['optional'], isTrue);
    });
  });

  group('method_step', () {
    test('a step reads as plain text with its chip amount scaled', () {
      final r = _json(methodStepResult(ragu, number: 1, servings: 8));
      expect(r['text'], 'Fry the 8 garlic.');
      expect(r['of'], 2);
      expect(r['timers'], isEmpty);
    });

    test('a step lists its timers', () {
      final r = _json(methodStepResult(ragu, number: 2, servings: 4));
      expect((r['timers']! as List).length, 2);
    });

    test('a step that does not exist is refused in words', () {
      expect(
        () => methodStepResult(ragu, number: 3, servings: 4),
        throwsA(
          isA<AskToolError>().having(
            (e) => e.message,
            'message',
            'Ragù has 2 steps; there is no step 3',
          ),
        ),
      );
    });
  });

  group('start_step_timer', () {
    test('picks the step and the timer, from 1', () {
      expect(resolveStepTimer(ragu, number: 2, timer: 2), (
        step: 1,
        ordinal: 1,
        low: 300,
        high: 300,
      ));
      expect(
        resolveStepTimer(ragu, number: 2).ordinal,
        0,
        reason: 'no timer named means the first',
      );
    });

    test('a step with no timer, or no such timer, is refused', () {
      expect(
        () => resolveStepTimer(ragu, number: 1),
        throwsA(isA<AskToolError>()),
      );
      expect(
        () => resolveStepTimer(ragu, number: 2, timer: 3),
        throwsA(isA<AskToolError>()),
      );
    });
  });

  group('find_recipe', () {
    const recipes = [
      (id: 'r1', title: 'Ragù'),
      (id: 'r2', title: 'Ragù bianco'),
      (id: 'r3', title: 'Aioli'),
    ];

    test('returns matches best first', () {
      final r = _json(findRecipeResult(recipes, 'aioli'));
      expect(r['matches'], [
        {'id': 'r3', 'title': 'Aioli'},
      ]);
    });

    test('says when nothing matches', () {
      final r = _json(findRecipeResult(recipes, 'hamburger helper'));
      expect(r['matches'], isEmpty);
      expect(r['note'], 'no recipe title matches');
    });
  });

  group('set_servings', () {
    test('accepts a positive number, kept to quarter steps', () {
      expect(acceptServings(8), 8);
      expect(acceptServings(2.6), 2.5);
    });

    test('refuses nothing, zero and nonsense', () {
      for (final bad in [null, 0, -2, 'six', double.nan]) {
        expect(() => acceptServings(bad), throwsA(isA<AskToolError>()));
      }
    });
  });
}
