import 'package:ansi/core/theme/ansi_theme.dart';
import 'package:ansi/core/units/units.dart';
import 'package:ansi/features/recipes/domain/method_step.dart';
import 'package:ansi/features/recipes/domain/recipe.dart';
import 'package:ansi/shared/method_step_text.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:forui/forui.dart';

LineItem _li(String id, String name, {double? qty, Unit unit = g}) => LineItem(
  id: id,
  ingredientId: 'ing-$id',
  ingredientName: name,
  unit: unit,
  quantity: qty,
);

final _lines = {
  'onion': _li('onion', 'onion', qty: 1, unit: pieces),
  'celery': _li('celery', 'celery', qty: 2, unit: pieces),
  'pepper': _li('pepper', 'green bell pepper', qty: 1, unit: pieces),
  'butter': _li('butter', 'butter', qty: 50),
  // The owner's real catch-all collective, off a cookbook photo (plan 0020 J1).
  'kale': _li('kale', 'Kale', qty: 1, unit: cup),
  'avocado': _li('avocado', 'Avocado', qty: 1, unit: pieces),
  'garlic': _li('garlic', 'Garlic', qty: 2, unit: pieces),
  'lemon': _li('lemon', 'Lemon Juice', qty: 2, unit: tbsp),
  'yeast': _li('yeast', 'Nutritional Yeast', qty: 1, unit: tbsp),
  'oil': _li('oil', 'Olive Oil', qty: 1, unit: tbsp),
  'salt': _li('salt', 'Salt', qty: 1),
};

const _blankCollectiveRefs = [
  'kale',
  'avocado',
  'garlic',
  'lemon',
  'yeast',
  'oil',
  'salt',
];

Widget _host(MethodStep step) => MaterialApp(
  home: FTheme(
    data: ansiThemeData(),
    child: FScaffold(
      child: MethodStepText(step: step, lineById: _lines),
    ),
  ),
);

/// Every chip label in the rendered step, in paint order.
List<String> _chipLabels(WidgetTester tester) => tester
    .widgetList<MethodChip>(find.byType(MethodChip))
    .map((c) => c.label)
    .toList();

void main() {
  testWidgets('a collective chip renders its label then every constituent', (
    tester,
  ) async {
    const step = MethodStep(
      tokens: [
        MethodText(s: 'Sweat the '),
        MethodRef(refs: ['onion', 'celery', 'pepper'], label: 'onion mixture'),
        MethodText(s: '.'),
      ],
    );

    await tester.pumpWidget(_host(step));

    expect(_chipLabels(tester), [
      'onion mixture',
      'onion',
      'celery',
      'green bell pepper',
    ]);
    // The parenthesised run is real text, so the line breaker can wrap it.
    expect(find.textContaining(' ('), findsOneWidget);
  });

  testWidgets('the constituents render smaller than the label chip', (
    tester,
  ) async {
    const step = MethodStep(
      tokens: [
        MethodRef(refs: ['onion', 'celery'], label: 'onion mixture'),
      ],
    );

    await tester.pumpWidget(_host(step));

    final chips = tester.widgetList<MethodChip>(find.byType(MethodChip));
    expect(chips.first.textSize, greaterThan(chips.last.textSize));
  });

  testWidgets('a long constituent run wraps instead of overflowing', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    const step = MethodStep(
      tokens: [
        MethodText(s: 'Sweat the '),
        MethodRef(
          refs: ['onion', 'celery', 'pepper', 'butter', 'onion', 'celery'],
          label: 'onion mixture',
        ),
        MethodText(s: ' until soft.'),
      ],
    );

    await tester.pumpWidget(_host(step));

    expect(tester.takeException(), isNull);
    expect(_chipLabels(tester).length, 7);

    // It wrapped: the step is more than one line tall, and no chip was pushed
    // past the right edge (which is what a single packed WidgetSpan would do).
    final host = tester.getRect(find.byType(MethodStepText));
    expect(host.height, greaterThan(16 * 1.5 * 1.5));
    for (var i = 0; i < 7; i++) {
      final chip = tester.getRect(find.byType(MethodChip).at(i));
      expect(chip.right, lessThanOrEqualTo(host.right));
    }
  });

  testWidgets('a single-ref chip is unchanged: one chip, keeping its amount', (
    tester,
  ) async {
    const step = MethodStep(
      tokens: [
        MethodText(s: 'Melt the '),
        MethodRef(refs: ['butter'], label: 'butter'),
        MethodText(s: '.'),
      ],
    );

    await tester.pumpWidget(_host(step));

    expect(_chipLabels(tester), ['butter']);
    expect(find.text('50 g'), findsOneWidget);
    expect(find.textContaining('('), findsNothing);
  });

  testWidgets('a dropped constituent never renders a dangling chip', (
    tester,
  ) async {
    // The import flow can demote a ref: the line it pointed at never landed.
    const step = MethodStep(
      tokens: [
        MethodRef(refs: ['onion', 'ghost', 'celery'], label: 'onion mixture'),
      ],
    );

    await tester.pumpWidget(_host(step));

    expect(_chipLabels(tester), ['onion mixture', 'onion', 'celery']);
    expect(find.text('ingredient'), findsNothing);
  });

  group('a blank-labelled collective renders as a run of chips (J1)', () {
    testWidgets('seven refs wrap across lines at phone width, in order, with '
        'no label chip and no parentheses', (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      const step = MethodStep(
        tokens: [
          MethodText(s: 'Blend the '),
          MethodRef(refs: _blankCollectiveRefs, label: ''),
          MethodText(s: ' until smooth.'),
        ],
      );

      await tester.pumpWidget(_host(step));

      // The shipped bug: ONE chip labelled "Kale, Avocado, Garlic, …", atomic
      // to the line breaker, running off the right of the screen.
      expect(tester.takeException(), isNull);
      expect(_chipLabels(tester), [
        'Kale',
        'Avocado',
        'Garlic',
        'Lemon Juice',
        'Nutritional Yeast',
        'Olive Oil',
        'Salt',
      ]);
      // No label to bracket, so no parentheses either.
      expect(find.textContaining('('), findsNothing);

      // It wrapped, and every chip stayed inside the step.
      final host = tester.getRect(find.byType(MethodStepText));
      expect(host.height, greaterThan(16 * 1.5 * 1.5));
      for (var i = 0; i < _blankCollectiveRefs.length; i++) {
        expect(
          tester.getRect(find.byType(MethodChip).at(i)).right,
          lessThanOrEqualTo(host.right),
        );
      }
    });

    testWidgets('a step-named portion rides on the first chip of the run', (
      tester,
    ) async {
      const step = MethodStep(
        tokens: [
          MethodRef(
            refs: ['onion', 'celery'],
            label: '',
            portion: StepPortion(qualifier: 'half'),
          ),
        ],
      );

      await tester.pumpWidget(_host(step));

      final chips = tester.widgetList<MethodChip>(find.byType(MethodChip));
      expect(chips.map((c) => c.label), ['onion', 'celery']);
      expect(chips.first.amount, 'half');
      expect(chips.last.amount, isNull);
    });

    testWidgets('a blank-labelled ref that resolves to nothing still says '
        '"ingredient" — never a bare number', (tester) async {
      const step = MethodStep(
        tokens: [
          MethodRef(refs: ['ghost', 'phantom'], label: ''),
        ],
      );

      await tester.pumpWidget(_host(step));

      expect(_chipLabels(tester), ['']);
      expect(find.text('ingredient'), findsOneWidget);
    });
  });

  testWidgets('a portion stays on the label chip, not the constituents', (
    tester,
  ) async {
    const step = MethodStep(
      tokens: [
        MethodRef(
          refs: ['onion', 'celery'],
          label: 'onion mixture',
          portion: StepPortion(qualifier: 'half'),
        ),
      ],
    );

    await tester.pumpWidget(_host(step));

    final chips = tester.widgetList<MethodChip>(find.byType(MethodChip));
    expect(chips.first.amount, 'half');
    expect(chips.skip(1).map((c) => c.amount), everyElement(isNull));
  });
}
