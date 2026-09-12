/// The component quantity sheet (step 8.6 / D2, board frame d): batch math on
/// the chips, the honest no-yield state, and the rules the ingredient sheet
/// does NOT bring with it (no measures chip).
library;

import 'package:ansi/core/theme/ansi_theme.dart';
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
