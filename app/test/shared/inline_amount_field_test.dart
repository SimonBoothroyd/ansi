/// The inline amount slot's widths, measured with the real fonts: each named
/// width holds the values it is named for at the field's own text size, so a
/// weight like `40` is never clipped in a sentence that asks for one.
library;

import 'package:ansi/core/theme/ansi_theme.dart';
import 'package:ansi/shared/inline_amount_field.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:forui/forui.dart';

import '../helpers/fonts.dart';
import '../helpers/forui_semantics.dart';

Widget _slot(double width, String text) => MaterialApp(
  home: FTheme(
    data: ansiThemeData(),
    child: FScaffold(
      child: Align(
        alignment: Alignment.topLeft,
        child: InlineAmountField(
          width: width,
          initial: text,
          fractions: true,
          onSubmit: () {},
        ),
      ),
    ),
  ),
);

/// How much wider [text] draws than the slot's text area. Zero or less fits.
Future<double> _overflow(WidgetTester tester, double width, String text) async {
  await tester.pumpWidget(_slot(width, text));
  await tester.pumpAndSettle();
  final editable = tester
      .state<EditableTextState>(find.byType(EditableText))
      .renderEditable;
  return editable.getMaxIntrinsicWidth(double.infinity) - editable.size.width;
}

void main() {
  setUpAll(loadAnsiFonts);

  testWidgets('a weight slot holds a scale reading up to 1234.5', (
    tester,
  ) async {
    filterForuiSemanticsAssertions();
    for (final value in ['40', '156.5', '1234.5']) {
      expect(
        await _overflow(tester, kInlineWeightWidth, value),
        lessThanOrEqualTo(0),
        reason: '“$value” is clipped in a ${kInlineWeightWidth}pt weight slot',
      );
    }
  });

  testWidgets('an amount slot holds a kitchen amount', (tester) async {
    filterForuiSemanticsAssertions();
    for (final value in ['⅔', '1½', '250']) {
      expect(
        await _overflow(tester, kInlineAmountWidth, value),
        lessThanOrEqualTo(0),
        reason: '“$value” is clipped in a ${kInlineAmountWidth}pt amount slot',
      );
    }
  });
}
