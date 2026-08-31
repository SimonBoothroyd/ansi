import 'package:flutter_test/flutter_test.dart';
import 'package:mise/core/units/units.dart';
import 'package:mise/features/import/domain/line_resolution.dart';
import 'package:mise/features/import/domain/preview_recipe.dart';
import 'package:mise/features/import/domain/reconciliation_payload.dart';
import 'package:mise/features/recipes/domain/method_step.dart';

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
}
