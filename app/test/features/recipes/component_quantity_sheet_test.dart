/// The component quantity sheet (step 8.6 / D2, board frame d): batch math on
/// the chips, the target recipe's own words leading the row (ADR-0018), and the
/// honest no-yield state.
library;

import 'package:ansi/core/theme/ansi_theme.dart';
import 'package:ansi/core/units/recipe_measure.dart';
import 'package:ansi/core/units/units.dart';
import 'package:ansi/features/ingredients/presentation/unit_chips.dart';
import 'package:ansi/features/recipes/data/recipe_providers.dart';
import 'package:ansi/features/recipes/domain/recipe.dart';
import 'package:ansi/features/recipes/presentation/component_quantity_sheet.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:forui/forui.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

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

/// A second word, so the offer's order can be read: the words lead in the order
/// they are given, behind the whole-batch one where there is one.
const _ladle = RecipeMeasure(
  id: 'm-ladle',
  recipeId: 'aioli',
  label: 'ladle',
  amount: 60,
  unit: ml,
);

const _aioliWithWord = SubRecipeTarget(
  id: 'aioli',
  title: 'Romesco Aioli',
  yieldQty: 1,
  yieldUnit: cup,
  measures: [_blob, _ladle],
);

/// The same recipe after the word was retired — the line still points at it.
const _aioliWordGone = _aioli;

/// A bread whose own word IS the whole batch: a loaf is 900 g and a batch makes
/// 900 g, so the word leads even `batch` (ADR-0018 rule 8).
const _loaf = RecipeMeasure(
  id: 'm-loaf',
  recipeId: 'bread',
  label: 'loaf',
  amount: 900,
  unit: g,
);

const _bread = SubRecipeTarget(
  id: 'bread',
  title: 'Sourdough Loaf',
  yieldQty: 900,
  yieldUnit: g,
  measures: [_loaf],
);

/// A chip in the row, by label — `find.text` alone would also match the
/// sentence beside the number, which says `blob (50 ml)`.
Finder _chip(String label) =>
    find.descendant(of: find.byType(UnitChipRow), matching: find.text(label));

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
    // The door behind the `+` is the TARGET recipe's measures list, which is
    // its own control and is not hosted here yet.
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
        '2 tbsp — unresolved — the yield is in weight, this line in '
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
      find.textContaining('left out of macros and the shop list'),
      findsOneWidget,
    );

    await tester.tap(find.byType(FSwitch));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Done'));
    await tester.pumpAndSettle();
    expect(saved!.optional, isTrue);
  });

  testWidgets('a measure with no number holds Done shut — the row the server '
      'refuses never leaves this sheet', (tester) async {
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

    for (final nothing in ['', '0']) {
      await tester.enterText(find.byType(TextField).first, nothing);
      await tester.pumpAndSettle();
      expect(
        find.text(ComponentQuantityEditor.kMeasuredLineNeedsANumber),
        findsOneWidget,
        reason: nothing.isEmpty ? 'blank' : 'zero',
      );
      await tester.tap(find.text('Done'));
      await tester.pumpAndSettle();
      expect(saved, isNull);
    }

    await tester.enterText(find.byType(TextField).first, '2');
    await tester.pumpAndSettle();
    expect(
      find.text(ComponentQuantityEditor.kMeasuredLineNeedsANumber),
      findsNothing,
    );
    await tester.tap(find.text('Done'));
    await tester.pumpAndSettle();
    expect(saved!.quantity, 2);
    expect(saved!.recipeMeasureId, 'm-blob');
  });

  testWidgets('a line said in a UNIT still needs no number — “cup” is a '
      'sentence, “blob” is a count', (tester) async {
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

    await tester.enterText(find.byType(TextField).first, '');
    await tester.pumpAndSettle();
    await tester.tap(find.text('Done'));
    await tester.pumpAndSettle();

    expect(saved!.quantity, isNull);
    expect(saved!.unit, cup);
  });

  group('the recipe’s own words lead the row', () {
    testWidgets('a fresh amount opens on the whole-batch word, with batch '
        'right behind it', (tester) async {
      filterForuiSemanticsAssertions();
      ComponentQuantity? saved;
      await tester.pumpWidget(_host(target: _bread, onDone: (q) => saved = q));
      await tester.pumpAndSettle();

      expect(find.text('loaf (900 g)'), findsOneWidget);
      expect(_chip('batch'), findsOneWidget);

      // A measure counts something, so the number comes first — see the
      // amountless refusal above.
      await tester.enterText(find.byType(TextField).first, '1');
      await tester.pumpAndSettle();
      await tester.tap(find.text('Done'));
      await tester.pumpAndSettle();
      expect(saved!.recipeMeasureId, 'm-loaf');
      expect(saved!.unit, isNull);
    });

    testWidgets('…and on the first word where none is the whole batch', (
      tester,
    ) async {
      filterForuiSemanticsAssertions();
      ComponentQuantity? saved;
      await tester.pumpWidget(
        _host(target: _aioliWithWord, onDone: (q) => saved = q),
      );
      await tester.pumpAndSettle();

      expect(find.text('blob (50 ml)'), findsOneWidget);
      for (final label in ['blob', 'ladle', 'batch', 'cup', 'ml']) {
        expect(_chip(label), findsOneWidget, reason: 'chip "$label" missing');
      }

      await tester.enterText(find.byType(TextField).first, '1');
      await tester.pumpAndSettle();
      await tester.tap(find.text('Done'));
      await tester.pumpAndSettle();
      expect(saved!.recipeMeasureId, 'm-blob');
    });

    testWidgets('a line being edited opens on its OWN stored word', (
      tester,
    ) async {
      filterForuiSemanticsAssertions();
      ComponentQuantity? saved;
      await tester.pumpWidget(
        _host(
          target: _aioliWithWord,
          initialQuantity: 3,
          initialMeasureId: 'm-ladle',
          onDone: (q) => saved = q,
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('ladle (60 ml)'), findsOneWidget);
      expect(find.textContaining('3 ladle = '), findsOneWidget);

      await tester.tap(find.text('Done'));
      await tester.pumpAndSettle();
      expect(saved!.recipeMeasureId, 'm-ladle');
      expect(saved!.unit, isNull, reason: 'the word IS the denomination');
      expect(saved!.quantity, 3);
    });

    testWidgets('choosing a word clears the unit, and choosing a unit clears '
        'the word', (tester) async {
      filterForuiSemanticsAssertions();
      ComponentQuantity? saved;
      await tester.pumpWidget(
        _host(
          target: _aioliWithWord,
          initialQuantity: 0.25,
          initialUnit: cup,
          onDone: (q) => saved = q,
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(_chip('blob'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Done'));
      await tester.pumpAndSettle();
      expect(saved!.recipeMeasureId, 'm-blob');
      expect(saved!.unit, isNull);

      await tester.tap(_chip('tbsp'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Done'));
      await tester.pumpAndSettle();
      expect(saved!.unit, tbsp);
      expect(
        saved!.recipeMeasureId,
        isNull,
        reason: 'one number cannot be counted twice',
      );
    });

    testWidgets('the QUANTITY is editable without touching the word', (
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

      await tester.enterText(find.byType(TextField).first, '5');
      await tester.pumpAndSettle();
      await tester.tap(find.text('Done'));
      await tester.pumpAndSettle();

      expect(saved!.quantity, 5);
      expect(saved!.recipeMeasureId, 'm-blob');
      expect(saved!.unit, isNull, reason: 'the number moved, the word did not');
    });

    testWidgets('a word the recipe can no longer HOLD is offered only as the '
        'stored choice, marked, and still reads as itself', (tester) async {
      // The word is alive and the share has gone — a `makes` restated into
      // another family under it. The chip is outside the honest filter (a tap
      // on it could only produce this refusal, and the fix is MAKES), but the
      // line that already says it must never render an orphaned value.
      filterForuiSemanticsAssertions();
      ComponentQuantity? saved;
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
          onDone: (q) => saved = q,
        ),
      );
      await tester.pumpAndSettle();

      expect(
        find.text(
          '3 blob — unresolved — the yield is in weight, this line in volume',
        ),
        findsOneWidget,
      );
      expect(_chip('blob'), findsOneWidget);
      expect(find.text('not in filter'), findsOneWidget);

      // And it is re-selectable after a detour through a unit.
      await tester.tap(_chip('kg'));
      await tester.pumpAndSettle();
      await tester.tap(_chip('blob'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Done'));
      await tester.pumpAndSettle();
      expect(saved!.recipeMeasureId, 'm-blob');
      expect(saved!.unit, isNull);
    });

    testWidgets('a word that has GONE lights no chip and keeps the number', (
      tester,
    ) async {
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

      expect(
        find.text(ComponentQuantityEditor.kGoneWordKeepsItsNumber),
        findsOneWidget,
      );
      // The honest line, not a number: `3 — its measure is gone`.
      expect(find.text('3 — its measure is gone'), findsOneWidget);
      // Nothing claims to be what this line says — and the offer is the
      // ordinary one, because a unit tapped here is a repair, not a loss.
      expect(_chip('cup'), findsOneWidget);
      expect(find.text('not in filter'), findsNothing);

      await tester.tap(find.text('Done'));
      await tester.pumpAndSettle();
      expect(
        saved!.recipeMeasureId,
        'm-blob',
        reason: 'the pointer is kept while nobody has picked anything',
      );
      expect(saved!.unit, isNull);
      expect(saved!.quantity, 3);

      // …and a tap on a chip IS the repair.
      await tester.tap(_chip('cup'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Done'));
      await tester.pumpAndSettle();
      expect(saved!.unit, cup);
      expect(saved!.recipeMeasureId, isNull);
    });

    testWidgets('a recipe that says no yield coins no words either', (
      tester,
    ) async {
      filterForuiSemanticsAssertions();
      await tester.pumpWidget(
        _host(
          // A word cannot be held to a batch that has no size — and the offer
          // says so by holding only `batch`.
          target: const SubRecipeTarget(
            id: 'aioli',
            title: 'Romesco Aioli',
            measures: [_blob],
          ),
          initialQuantity: 1,
          onDone: (_) {},
        ),
      );
      await tester.pumpAndSettle();

      expect(_chip('batch'), findsOneWidget);
      expect(_chip('blob'), findsNothing);
    });
  });

  testWidgets('a line written in the merge-hidden twin of a word still reads '
      'as that word', (tester) async {
    // Two phones offline both coined `blob`; the merge hides the newer row
    // rather than deleting it, and this line points at the hidden one. The
    // watch hands out the merged offer only, so resolving against it alone
    // would call a live word gone.
    filterForuiSemanticsAssertions();
    const twin = RecipeMeasure(
      id: 'm-blob-2',
      recipeId: 'aioli',
      label: 'blob',
      amount: 50,
      unit: ml,
    );
    ComponentQuantity? saved;
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          recipeMeasuresProvider(
            'aioli',
          ).overrideWith((ref) => Stream.value(const [_blob])),
        ],
        child: MaterialApp(
          home: FTheme(
            data: ansiThemeData(),
            child: FScaffold(
              child: ComponentQuantityEditor(
                // The loaded target carries the offer and the hidden twin
                // behind it, which is what `loadRecipeMeasures` hands out.
                target: const SubRecipeTarget(
                  id: 'aioli',
                  title: 'Romesco Aioli',
                  yieldQty: 1,
                  yieldUnit: cup,
                  measures: [_blob, twin],
                ),
                initialQuantity: 3,
                initialMeasureId: 'm-blob-2',
                mayCoinWords: true,
                onDone: (q) => saved = q,
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(
      find.text(ComponentQuantityEditor.kGoneWordKeepsItsNumber),
      findsNothing,
    );
    expect(find.textContaining('3 blob = '), findsOneWidget);
    // One chip for the word, and it is the row this line means.
    expect(_chip('blob'), findsOneWidget);
    expect(find.text('not in filter'), findsNothing);

    await tester.tap(find.text('Done'));
    await tester.pumpAndSettle();
    expect(saved!.recipeMeasureId, 'm-blob-2');
    expect(saved!.unit, isNull);
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
