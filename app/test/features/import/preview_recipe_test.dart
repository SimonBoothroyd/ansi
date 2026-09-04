import 'package:ansi/core/units/measure.dart';
import 'package:ansi/core/units/units.dart';
import 'package:ansi/features/import/domain/line_resolution.dart';
import 'package:ansi/features/import/domain/preview_recipe.dart';
import 'package:ansi/features/import/domain/reconciliation_payload.dart';
import 'package:ansi/features/recipes/domain/method_step.dart';
import 'package:ansi/features/recipes/presentation/ingredient_line.dart';
import 'package:flutter_test/flutter_test.dart';

ReconLine _line(String text, {double? qty, String? unit, String? notes}) =>
    ReconLine(
      raw: RawLineItem(
        ingredientText: text,
        qty: qty,
        unit: unit,
        notes: notes,
      ),
      band: MatchBand.none,
    );

void main() {
  test('builds an in-memory recipe with synthetic line ids and notes', () {
    final payload = ReconciliationPayload(
      title: 'Weeknight Pasta',
      servingsBase: 2,
      groups: [
        ReconGroup(
          lines: [
            _line('spaghetti', qty: 200, unit: 'g'),
            _line('garlic', qty: 2, unit: 'clove', notes: 'sliced'),
          ],
        ),
      ],
      steps: [
        const Step(
          tokens: [
            TextToken(s: 'Boil the '),
            RefToken(refs: [0], label: 'spaghetti'),
            TextToken(s: '.'),
          ],
        ),
      ],
    );
    final resolutions = [
      initialResolution(
        0,
        payload.flatLines[0],
      ).resolveToIngredient('ing-spag', 'Spaghetti'),
      initialResolution(
        1,
        payload.flatLines[1],
      ).resolveToIngredient('ing-garlic', 'Garlic'),
    ];

    final recipe = buildPreviewRecipe(payload, resolutions, servingsBase: 2);

    expect(recipe.title, 'Weeknight Pasta');
    final items = recipe.groups.single.items;
    expect(items[0].id, previewLineId(0));
    expect(items[0].ingredientName, 'Spaghetti');
    expect(items[0].unit, g);
    // notes are rendered as the line note.
    expect(items[1].note, 'sliced');

    // The method ref remapped from line index 0 to the synthetic id.
    final ref = recipe.methodSteps!.single.tokens.whereType<MethodRef>().single;
    expect(ref.refs, [previewLineId(0)]);
  });

  test('a dropped line leaves the preview, and its chip demotes to prose', () {
    final payload = ReconciliationPayload(
      title: 'T',
      groups: [
        ReconGroup(
          lines: [
            _line('spaghetti', qty: 200, unit: 'g'),
            _line('basil', qty: 1, unit: 'handful'),
          ],
        ),
      ],
      steps: [
        const Step(
          tokens: [
            TextToken(s: 'Finish with '),
            RefToken(refs: [1], label: 'basil'),
            TextToken(s: '.'),
          ],
        ),
      ],
    );
    final resolutions = [
      initialResolution(
        0,
        payload.flatLines[0],
      ).resolveToIngredient('ing-spag', 'Spaghetti'),
      initialResolution(
        1,
        payload.flatLines[1],
      ).resolveToIngredient('ing-basil', 'Basil').drop(),
    ];

    final recipe = buildPreviewRecipe(payload, resolutions, servingsBase: 2);

    // The dropped line is gone from the ingredient list…
    expect(recipe.groups.single.items, hasLength(1));
    expect(recipe.groups.single.items.single.id, previewLineId(0));
    // …and the step keeps the word, having lost only the chip.
    final tokens = recipe.methodSteps!.single.tokens;
    expect(tokens.whereType<MethodRef>(), isEmpty);
    expect(tokens.whereType<MethodText>().map((t) => t.s), [
      'Finish with ',
      'basil',
      '.',
    ]);
  });

  test('two lines resolved to one row share its id so they fold inline', () {
    final payload = ReconciliationPayload(
      title: 'T',
      groups: [
        ReconGroup(
          lines: [
            _line('Aleppo chilli', notes: 'toasted'),
            _line('Aleppo chilli', notes: 'to serve'),
          ],
        ),
      ],
    );
    final resolutions = [
      initialResolution(
        0,
        payload.flatLines[0],
      ).resolveToIngredient('ing-chilli', 'Aleppo chilli'),
      initialResolution(
        1,
        payload.flatLines[1],
      ).resolveToIngredient('ing-chilli', 'Aleppo chilli'),
    ];

    final recipe = buildPreviewRecipe(payload, resolutions, servingsBase: 1);
    final items = recipe.groups.single.items;
    expect(items[0].ingredientId, items[1].ingredientId);
  });

  test('a LINKED line previews as the component it is about to be', () {
    final payload = ReconciliationPayload(
      title: 'Sausage Sliders',
      servingsBase: 8,
      groups: [
        ReconGroup(
          lines: [_line('Romesco Aioli (page 38)', qty: 0.25, unit: 'cup')],
        ),
      ],
    );
    final recipe = buildPreviewRecipe(payload, [
      initialResolution(
        0,
        payload.flatLines[0],
      ).linkToRecipe('r-aioli', 'Romesco Aioli'),
    ], servingsBase: 8);
    final item = recipe.groups.single.items.single;
    // Exactly one identity, as the saved row will have: the preview shows
    // what a save would write, not a plausible-looking ingredient line.
    expect(item.isComponent, isTrue);
    expect(item.subRecipeId, 'r-aioli');
    expect(item.ingredientId, isNull);
    expect(item.ingredientName, 'Romesco Aioli');
    expect(item.subRecipe?.title, 'Romesco Aioli');
    expect(item.quantity, 0.25);
    expect(item.unit, cup);
  });

  group('a resolved measure', () {
    const avocado = Measure(id: 'm-avocado', label: 'avocado', amount: 150);

    test(
      'previews as commit writes it: piece + measure, formatted by label',
      () {
        final payload = ReconciliationPayload(
          title: 'Guacamole',
          groups: [
            ReconGroup(lines: [_line('avocado', qty: 1)]),
          ],
        );
        // D2's arrival (or a tapped chip) rides the measure LABEL on the line —
        // not a catalogue unit id, which is what used to degrade it to "piece".
        final resolutions = [
          initialResolution(
            0,
            payload.flatLines[0],
          ).resolveToIngredient('ing-avocado', 'Avocado').pickUnit('avocado'),
        ];

        final recipe = buildPreviewRecipe(
          payload,
          resolutions,
          servingsBase: 2,
          measureByLine: {0: avocado},
        );

        final item = recipe.groups.single.items.single;
        expect(item.unit, pieces);
        expect(item.measureId, 'm-avocado');
        expect(item.measure, avocado);
        // The chip sheet and the recipe page format through the same function.
        expect(amountOfLineItem(item), '1 avocado');
      },
    );

    test('without the measure the same line still degrades to piece', () {
      final payload = ReconciliationPayload(
        title: 'Guacamole',
        groups: [
          ReconGroup(lines: [_line('avocado', qty: 1)]),
        ],
      );
      final resolutions = [
        initialResolution(
          0,
          payload.flatLines[0],
        ).resolveToIngredient('ing-avocado', 'Avocado').pickUnit('avocado'),
      ];

      final item = buildPreviewRecipe(
        payload,
        resolutions,
        servingsBase: 2,
      ).groups.single.items.single;
      expect(item.unit, pieces);
      expect(item.measureId, isNull);
      expect(item.measure, isNull);
      expect(amountOfLineItem(item), '1');
    });

    test('a catalogue-unit line and a numberless line are untouched', () {
      final payload = ReconciliationPayload(
        title: 'T',
        groups: [
          ReconGroup(
            lines: [
              _line('spaghetti', qty: 200, unit: 'g'),
              _line('avocado', qty: 1),
              _line('salt'),
            ],
          ),
        ],
      );
      final resolutions = [
        initialResolution(
          0,
          payload.flatLines[0],
        ).resolveToIngredient('ing-spag', 'Spaghetti'),
        initialResolution(
          1,
          payload.flatLines[1],
        ).resolveToIngredient('ing-avocado', 'Avocado').pickUnit('avocado'),
        initialResolution(
          2,
          payload.flatLines[2],
        ).resolveToIngredient('ing-salt', 'Salt'),
      ];

      final items = buildPreviewRecipe(
        payload,
        resolutions,
        servingsBase: 2,
        measureByLine: {1: avocado},
      ).groups.single.items;

      expect(items[0].unit, g);
      expect(items[0].measure, isNull);
      expect(amountOfLineItem(items[0]), '200 g');
      expect(items[1].measure, avocado);
      expect(items[2].unit, toTaste);
      expect(items[2].measure, isNull);
    });

    test('a component line never carries one, whatever the map says', () {
      final payload = ReconciliationPayload(
        title: 'T',
        groups: [
          ReconGroup(lines: [_line('Romesco Aioli', qty: 0.25, unit: 'cup')]),
        ],
      );
      final item = buildPreviewRecipe(
        payload,
        [
          initialResolution(
            0,
            payload.flatLines[0],
          ).linkToRecipe('r-aioli', 'Romesco Aioli'),
        ],
        servingsBase: 8,
        measureByLine: {0: avocado},
      ).groups.single.items.single;

      expect(item.isComponent, isTrue);
      expect(item.unit, cup);
      expect(item.measureId, isNull);
      expect(item.measure, isNull);
    });
  });

  test('the preview carries optional onto the line, as the page will tag '
      'it', () {
    final payload = ReconciliationPayload(
      title: 'T',
      groups: [
        ReconGroup(
          lines: [
            _line('lime', qty: 1, unit: 'piece'),
            const ReconLine(
              raw: RawLineItem(ingredientText: 'coriander', optional: true),
              band: MatchBand.none,
            ),
          ],
        ),
      ],
    );
    final resolutions = [
      initialResolution(
        0,
        payload.flatLines[0],
      ).resolveToIngredient('ing-lime', 'Lime'),
      initialResolution(
        1,
        payload.flatLines[1],
      ).resolveToIngredient('ing-coriander', 'Coriander'),
    ];
    final recipe = buildPreviewRecipe(payload, resolutions, servingsBase: 2);
    expect(recipe.groups.single.items.map((i) => i.optional), [false, true]);
  });
}
