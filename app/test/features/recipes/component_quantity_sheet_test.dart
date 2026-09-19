/// The component quantity sheet (step 8.6 / D2, board frame d): batch math on
/// the chips, the honest no-yield state, and the rules the ingredient sheet
/// does NOT bring with it (no measures chip).
library;

import 'package:ansi/core/theme/ansi_theme.dart';
import 'package:ansi/core/units/recipe_measure.dart';
import 'package:ansi/core/units/units.dart';
import 'package:ansi/features/recipes/domain/recipe.dart';
import 'package:ansi/features/recipes/presentation/component_quantity_sheet.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:forui/forui.dart';

import '../../helpers/forui_semantics.dart';

Widget _host({
  required SubRecipeTarget target,
  required ValueChanged<ComponentQuantity> onDone,
  double? initialQuantity,
  Unit? initialUnit,
  String? initialMeasureId,
  bool initialOptional = false,
  VoidCallback? onSetYield,
}) => MaterialApp(
  home: FTheme(
    data: ansiThemeData(),
    child: FScaffold(
      child: ComponentQuantityEditor(
        target: target,
        initialQuantity: initialQuantity,
        initialUnit: initialUnit,
        initialMeasureId: initialMeasureId,
        initialOptional: initialOptional,
        onSetYield: onSetYield,
        onDone: onDone,
      ),
    ),
  ),
);

const _aioli = SubRecipeTarget(
  id: 'aioli',
  title: 'Romesco Aioli',
  yieldQty: 1,
  yieldUnit: cup,
);

const _butter = SubRecipeTarget(
  id: 'butter',
  title: 'Garlic Butter',
  yieldQty: 250,
  yieldUnit: g,
);

const _unmeasured = SubRecipeTarget(id: 'aioli', title: 'Romesco Aioli');

/// The aioli, with the household's own word for a ladleful of it: a blob is 50
/// ml, which against `makes 1 cup` is a fifth of a batch.
const _blob = RecipeMeasure(
  id: 'm-blob',
  recipeId: 'aioli',
  label: 'blob',
  amount: 50,
  unit: ml,
);

const _aioliWithWord = SubRecipeTarget(
  id: 'aioli',
  title: 'Romesco Aioli',
  yieldQty: 1,
  yieldUnit: cup,
  measures: [_blob],
);

/// The same recipe after the word was retired — the line still points at it.
const _aioliWordGone = _aioli;

void main() {
  testWidgets('a stated yield opens its family and the line reads in batches', (
    tester,
  ) async {
    filterForuiSemanticsAssertions();
    await tester.pumpWidget(
      _host(
        target: _aioli,
        initialQuantity: 0.25,
        initialUnit: cup,
        onDone: (_) {},
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('¼ cup = ¼ of a batch · makes 1 cup'), findsOneWidget);
    for (final label in ['batch', 'cup', 'tbsp', 'tsp', 'ml']) {
      expect(find.text(label), findsWidgets, reason: 'chip "$label" missing');
    }
    // A measure is an ingredient concept: no manage-measures chip here.
    expect(find.byIcon(FLucideIcons.plus), findsNothing);
  });

  testWidgets('no yield ⇒ the batch chip alone, and a way to go fix it', (
    tester,
  ) async {
    filterForuiSemanticsAssertions();
    var setYieldTapped = false;
    await tester.pumpWidget(
      _host(
        target: _unmeasured,
        initialQuantity: 1,
        onDone: (_) {},
        onSetYield: () => setYieldTapped = true,
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('no yield set — amounts in batches only'), findsOneWidget);
    expect(find.text('cup'), findsNothing);
    expect(find.text('batch'), findsWidgets);

    await tester.tap(find.text('Set the yield'));
    await tester.pumpAndSettle();
    expect(setYieldTapped, isTrue);
  });

  testWidgets('a stored unit outside the offer stays selectable, flagged, and '
      'reads its honest unresolved line', (tester) async {
    filterForuiSemanticsAssertions();
    // An imported line printed "2 tbsp" of a butter that only says 250 g.
    await tester.pumpWidget(
      _host(
        target: _butter,
        initialQuantity: 2,
        initialUnit: tbsp,
        onDone: (_) {},
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('not in filter'), findsOneWidget);
    expect(
      find.text(
        '2 tbsp — unresolved — the yield is in mass, this line in '
        'volume',
      ),
      findsOneWidget,
    );
    // Never silently rewritten: Done hands back exactly what was stored.
    expect(find.text('tbsp'), findsWidgets);
  });

  testWidgets('Done hands back the amount and the chip that was picked', (
    tester,
  ) async {
    filterForuiSemanticsAssertions();
    ComponentQuantity? saved;
    await tester.pumpWidget(
      _host(
        target: _aioli,
        initialQuantity: 0.25,
        initialUnit: cup,
        onDone: (q) => saved = q,
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('batch').first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Done'));
    await tester.pumpAndSettle();

    expect(saved!.unit, batches);
    expect(saved!.quantity, 0.25);
  });

  testWidgets('a fresh line defaults to the yield’s own unit', (tester) async {
    filterForuiSemanticsAssertions();
    ComponentQuantity? saved;
    await tester.pumpWidget(_host(target: _aioli, onDone: (q) => saved = q));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Done'));
    await tester.pumpAndSettle();
    expect(saved!.unit, cup);
  });

  testWidgets('…and to batch when the recipe states none — the denomination '
      'that never needs a yield', (tester) async {
    filterForuiSemanticsAssertions();
    ComponentQuantity? saved;
    await tester.pumpWidget(
      _host(target: _unmeasured, onDone: (q) => saved = q),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Done'));
    await tester.pumpAndSettle();
    expect(saved!.unit, batches);
  });

  testWidgets('the Optional switch rides on a component line too, and Done '
      'carries it back', (tester) async {
    filterForuiSemanticsAssertions();
    ComponentQuantity? saved;
    await tester.pumpWidget(
      _host(target: _aioli, initialQuantity: 1, onDone: (q) => saved = q),
    );
    await tester.pumpAndSettle();

    expect(find.text('Optional'), findsOneWidget);
    expect(
      find.text(
        'left out of macros and the shop list, and named where it '
        'left',
      ),
      findsOneWidget,
    );

    await tester.tap(find.byType(FSwitch));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Done'));
    await tester.pumpAndSettle();
    expect(saved!.optional, isTrue);
  });

  group('a MEASURED line is not re-denominated here', () {
    testWidgets('the word is the only chip, marked, and Done keeps it', (
      tester,
    ) async {
      filterForuiSemanticsAssertions();
      ComponentQuantity? saved;
      await tester.pumpWidget(
        _host(
          target: _aioliWithWord,
          initialQuantity: 3,
          initialMeasureId: 'm-blob',
          onDone: (q) => saved = q,
        ),
      );
      await tester.pumpAndSettle();

      // The word leads the row and nothing else is on it: every other chip
      // this sheet can draw is a catalog unit, and one of those written where
      // `blob` was is the loss this closes.
      expect(find.text('blob'), findsWidgets);
      expect(find.text('this recipe’s word'), findsOneWidget);
      for (final unit in ['batch', 'cup', 'tbsp', 'ml']) {
        expect(
          find.text(unit),
          findsNothing,
          reason: 'a catalog chip "$unit" would re-denominate the line',
        );
      }
      expect(
        find.text(ComponentQuantityEditor.kMeasuredLineKeepsItsWord),
        findsOneWidget,
      );
      // 3 blob = 150 ml, and a batch is 1 cup ≈ 236.6 ml.
      expect(
        find.textContaining('3 blob = ', findRichText: true),
        findsOneWidget,
      );

      await tester.tap(find.text('Done'));
      await tester.pumpAndSettle();
      // The whole point: null means "the denomination did not change".
      expect(saved!.unit, isNull);
      expect(saved!.quantity, 3);
    });

    testWidgets('the QUANTITY is still fully editable', (tester) async {
      filterForuiSemanticsAssertions();
      ComponentQuantity? saved;
      await tester.pumpWidget(
        _host(
          target: _aioliWithWord,
          initialQuantity: 3,
          initialMeasureId: 'm-blob',
          onDone: (q) => saved = q,
        ),
      );
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(TextField).first, '5');
      await tester.pumpAndSettle();
      await tester.tap(find.text('Done'));
      await tester.pumpAndSettle();

      expect(saved!.quantity, 5);
      expect(saved!.unit, isNull, reason: 'the number moved, the word did not');
    });

    testWidgets('a word that has GONE keeps its pointer rather than being '
        'handed a unit', (tester) async {
      filterForuiSemanticsAssertions();
      ComponentQuantity? saved;
      await tester.pumpWidget(
        _host(
          target: _aioliWordGone,
          initialQuantity: 3,
          initialMeasureId: 'm-blob',
          onDone: (q) => saved = q,
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('word gone'), findsOneWidget);
      expect(find.text('nothing to change it to'), findsOneWidget);
      expect(
        find.text(ComponentQuantityEditor.kGoneWordKeepsItsPointer),
        findsOneWidget,
      );
      expect(find.text('cup'), findsNothing);
      // The honest line, not a number: `3 — its measure is gone`.
      expect(find.text('3 — its measure is gone'), findsOneWidget);

      await tester.tap(find.text('Done'));
      await tester.pumpAndSettle();
      expect(saved!.unit, isNull);
      expect(saved!.quantity, 3);
    });

    testWidgets('a word the recipe can no longer HOLD still prints the word '
        'beside its refusal', (tester) async {
      // The step-4 bug, at the sheet: the label is read off the recipe's live
      // measures, so an alive-but-unresolvable word reads "3 blob —
      // unresolved — …" rather than a bare "3 — unresolved".
      filterForuiSemanticsAssertions();
      await tester.pumpWidget(
        _host(
          // Makes a MASS, and the blob is said in ml. No density for a recipe.
          target: const SubRecipeTarget(
            id: 'aioli',
            title: 'Romesco Aioli',
            yieldQty: 250,
            yieldUnit: g,
            measures: [_blob],
          ),
          initialQuantity: 3,
          initialMeasureId: 'm-blob',
          onDone: (_) {},
        ),
      );
      await tester.pumpAndSettle();

      expect(
        find.text(
          '3 blob — unresolved — the yield is in mass, this line in volume',
        ),
        findsOneWidget,
      );
    });
  });

  testWidgets('a line that already says optional opens with the switch on', (
    tester,
  ) async {
    filterForuiSemanticsAssertions();
    ComponentQuantity? saved;
    await tester.pumpWidget(
      _host(
        target: _aioli,
        initialQuantity: 1,
        initialOptional: true,
        onDone: (q) => saved = q,
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Done'));
    await tester.pumpAndSettle();
    expect(saved!.optional, isTrue);
  });
}
