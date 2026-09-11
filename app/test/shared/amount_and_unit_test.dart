/// The amount-and-unit control (`lib/shared/amount_and_unit.dart`): the unit
/// half is a chip that opens the pick sheet, and the whole control is one
/// height.
///
/// The owner's question was "why two text boxes for mass and unit, not our
/// nice unit picker?" — so what is asserted here is the answer to it: no
/// select anywhere in the control, the offer arrives as chips, the pick comes
/// back through `onUnit`, and the sheet closes behind it.
library;

import 'package:ansi/core/theme/ansi_theme.dart';
import 'package:ansi/core/units/units.dart';
import 'package:ansi/shared/amount_and_unit.dart';
import 'package:ansi/shared/inline_amount_field.dart';
import 'package:ansi/shared/unit_chip.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:forui/forui.dart';

import '../helpers/forui_semantics.dart';

const _units = [g, kg, oz, ml, tbsp, cup];

/// The control on its own page, reporting what it is asked to change and
/// re-rendering with the pick — the host's job, done minimally.
Widget _host({List<Unit>? units, List<Unit>? picks}) {
  var unit = g;
  return MaterialApp(
    home: FTheme(
      data: ansiThemeData(),
      child: FScaffold(
        child: StatefulBuilder(
          builder: (context, setState) => AmountAndUnitField(
            amountKey: const ValueKey('the-amount'),
            unitKey: const ValueKey('the-unit'),
            amount: '2',
            unit: unit,
            units: units ?? _units,
            onAmount: (_) {},
            onUnit: (u) {
              picks?.add(u);
              setState(() => unit = u);
            },
          ),
        ),
      ),
    ),
  );
}

void main() {
  group('the unit is a chip, not a dropdown', () {
    testWidgets('there is no select in the control at all', (tester) async {
      filterForuiSemanticsAssertions();
      await tester.pumpWidget(_host());
      await tester.pumpAndSettle();

      expect(
        find.byWidgetPredicate((w) => w is FSelect<Unit>),
        findsNothing,
        reason: 'the retired dropdown must not come back through here',
      );
      expect(
        find.descendant(
          of: find.byKey(const ValueKey('the-unit')),
          matching: find.text('g'),
        ),
        findsOneWidget,
      );
    });

    testWidgets('tapping it opens the offer as chips, and the pick comes back '
        'through onUnit and closes the sheet', (tester) async {
      filterForuiSemanticsAssertions();
      final picks = <Unit>[];
      await tester.pumpWidget(_host(picks: picks));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const ValueKey('the-unit')));
      await tester.pumpAndSettle();

      // The host's list, every unit of it, as the dock's own chip.
      expect(find.byType(UnitChip), findsNWidgets(_units.length + 1));
      for (final u in _units) {
        expect(find.text(u.label), findsWidgets, reason: u.id);
      }

      await tester.tap(find.text('tbsp').last);
      await tester.pumpAndSettle();

      expect(picks, [tbsp]);
      // Closed behind the pick, and the chip says what was picked.
      expect(find.text('Unit'), findsNothing);
      expect(find.byType(UnitChip), findsOneWidget);
      expect(
        find.descendant(
          of: find.byKey(const ValueKey('the-unit')),
          matching: find.text('tbsp'),
        ),
        findsOneWidget,
      );
    });

    testWidgets('dismissing it changes nothing', (tester) async {
      filterForuiSemanticsAssertions();
      final picks = <Unit>[];
      await tester.pumpWidget(_host(picks: picks));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const ValueKey('the-unit')));
      await tester.pumpAndSettle();
      await tester.tap(find.byIcon(FLucideIcons.x));
      await tester.pumpAndSettle();

      expect(picks, isEmpty);
      expect(
        find.descendant(
          of: find.byKey(const ValueKey('the-unit')),
          matching: find.text('g'),
        ),
        findsOneWidget,
      );
    });
  });

  testWidgets('both halves sit at the one inline height', (tester) async {
    filterForuiSemanticsAssertions();
    await tester.pumpWidget(_host());
    await tester.pumpAndSettle();

    expect(
      tester.getSize(find.byKey(const ValueKey('the-amount'))).height,
      kInlineControlHeight,
    );
    expect(
      tester.getSize(find.byKey(const ValueKey('the-unit'))).height,
      kInlineControlHeight,
    );
  });
}
