// The four-cell macro strip must survive the widest honest figures. A week
// that plans three meals a day reaches five kcal digits and three-digit
// grams, and the band it sits in is only ~316 logical px wide.
import 'package:ansi/core/units/macros.dart';
import 'package:ansi/features/planning/presentation/week_macro_widgets.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

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
        const MacroCells(
          macros: Macros(kcal: 1234, protein: 456, carb: 789, fat: 321),
          size: 14,
        ),
      ),
    );

    expect(tester.takeException(), isNull);
    expect(find.text('${formatMacroNumber(1234)} kcal'), findsOneWidget);
    expect(find.text('${formatMacroNumber(321)} g f'), findsOneWidget);
    expect(
      tester.getSize(find.byType(MacroCells)).width,
      lessThanOrEqualTo(_bandWidth),
    );
  });

  testWidgets('the strip fits the band at a five-digit week total', (
    tester,
  ) async {
    await tester.pumpWidget(
      _host(
        const MacroCells(
          macros: Macros(kcal: 24500, protein: 1234, carb: 1680, fat: 890),
          size: 14,
        ),
      ),
    );

    expect(tester.takeException(), isNull);
    expect(find.text('${formatMacroNumber(24500)} kcal'), findsOneWidget);
    expect(
      tester.getSize(find.byType(MacroCells)).width,
      lessThanOrEqualTo(_bandWidth),
    );
  });
}
