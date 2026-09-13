// The macro strip must survive the widest honest figures. A week that plans
// three meals a day reaches five kcal digits and three-digit grams, and the
// band it sits in is only ~316 logical px wide — with fibre on the end when
// every meal stated it.
import 'package:ansi/core/units/macros.dart';
import 'package:ansi/features/planning/presentation/week_macro_widgets.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/macro_line.dart';

/// The band's inner width on a phone, measured from the overflow this test
/// exists to keep fixed.
const _bandWidth = 316.0;

Widget _host(Widget child) => MaterialApp(
  home: Align(
    alignment: Alignment.topLeft,
    child: SizedBox(width: _bandWidth, child: child),
  ),
);

void main() {
  testWidgets('the strip fits the band at four-digit kcal and three-digit '
      'grams', (tester) async {
    await tester.pumpWidget(
      _host(
        const MacroStrip(
          macros: Macros(kcal: 1234, protein: 456, carb: 789, fat: 321),
          size: 13,
        ),
      ),
    );

    expect(tester.takeException(), isNull);
    // The recipe line's grammar, with the week's thousands separator: no `g`,
    // no dividers, the initials against their figures.
    expect(
      macroText('${formatMacroNumber(1234)} kcal · 456P 789C 321F'),
      findsOneWidget,
    );
    expect(
      tester.getSize(find.byType(MacroStrip)).width,
      lessThanOrEqualTo(_bandWidth),
    );
  });

  testWidgets('the strip fits the band at a five-digit week total', (
    tester,
  ) async {
    await tester.pumpWidget(
      _host(
        const MacroStrip(
          macros: Macros(kcal: 24500, protein: 1234, carb: 1680, fat: 890),
          size: 13,
        ),
      ),
    );

    expect(tester.takeException(), isNull);
    expect(
      macroTextContaining('${formatMacroNumber(24500)} kcal'),
      findsOneWidget,
    );
    expect(
      tester.getSize(find.byType(MacroStrip)).width,
      lessThanOrEqualTo(_bandWidth),
    );
  });

  testWidgets('fibre still fits the band at a five-digit week total', (
    tester,
  ) async {
    await tester.pumpWidget(
      _host(
        const MacroStrip(
          macros: Macros(
            kcal: 24500,
            protein: 1234,
            carb: 1680,
            fat: 890,
            fiber: 245,
          ),
          size: 13,
        ),
      ),
    );

    expect(tester.takeException(), isNull);
    // `fibre`, spoken — the sheaf glyph carries the word `F` already spends
    // on fat.
    expect(
      macroTextContaining('· ${formatMacroGrams(245)} fibre'),
      findsOneWidget,
    );
    expect(
      tester.getSize(find.byType(MacroStrip)).width,
      lessThanOrEqualTo(_bandWidth),
    );
  });

  testWidgets('an unstated fibre prints nothing at all', (tester) async {
    await tester.pumpWidget(
      _host(
        const MacroStrip(
          macros: Macros(kcal: 1234, protein: 456, carb: 789, fat: 321),
          size: 13,
        ),
      ),
    );

    expect(macroTextContaining('fibre'), findsNothing);
  });
}
