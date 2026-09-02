import 'package:ansi/core/units/units.dart';
import 'package:ansi/features/import/domain/line_resolution.dart';
import 'package:ansi/features/import/domain/preview_recipe.dart';
import 'package:ansi/features/import/domain/reconciliation_payload.dart';
import 'package:ansi/features/recipes/domain/method_step.dart';
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
      initialResolution(1, payload.flatLines[1]).resolveToNewStub('Garlic'),
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
      initialResolution(0, payload.flatLines[0]).resolveToNewStub('Spaghetti'),
      initialResolution(
        1,
        payload.flatLines[1],
      ).resolveToNewStub('Basil').drop(),
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

  test('identical no-match uses share an identity id so they fold inline', () {
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
      ).resolveToNewStub('Aleppo chilli'),
      initialResolution(
        1,
        payload.flatLines[1],
      ).resolveToNewStub('Aleppo chilli'),
    ];

    final recipe = buildPreviewRecipe(payload, resolutions, servingsBase: 1);
    final items = recipe.groups.single.items;
    expect(items[0].ingredientId, items[1].ingredientId);
  });

  test('a LINKED line previews as the component it is about to be (8.6)', () {
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
}
