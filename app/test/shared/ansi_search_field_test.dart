/// The one search field carries the app's type and insets its own magnifier.
///
/// Forui sizes a field off `typography.sm` — 16 on the touch ramp — and hangs a
/// prefix icon on the border. Left alone that is a field whose text is two
/// steps larger than every other sans on the screen, with a magnifier flush to
/// the edge. Both are fixed in the one widget, so every body gets it.
library;

import 'package:ansi/core/theme/ansi_theme.dart';
import 'package:ansi/core/theme/ansi_tokens.dart';
import 'package:ansi/shared/ansi_search_field.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:forui/forui.dart';

import '../helpers/pump_app.dart';

Future<void> _pumpField(WidgetTester tester) async {
  await tester.pumpAnsiApp(
    const Align(
      alignment: Alignment.topLeft,
      child: SizedBox(
        width: 320,
        child: AnsiSearchField(hint: 'Search recipes'),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('the hint and the content are the app sans at the row size', (
    tester,
  ) async {
    await _pumpField(tester);

    final hint = tester.widget<Text>(find.text('Search recipes'));
    expect(hint.style?.fontSize, 14);
    // Forui's own muted ink is kept: this is the app's size applied to Forui's
    // hint, not a replacement that would also flatten the disabled state.
    expect(hint.style?.color, AnsiColors.muted);
  });

  testWidgets('the magnifier is inset by the same padding the text is', (
    tester,
  ) async {
    await _pumpField(tester);

    final padding = ansiThemeData().textFieldStyles.md.contentPadding
        .resolve(TextDirection.ltr)
        .left;
    final field = tester.getRect(find.byType(AnsiSearchField));
    final icon = tester.getRect(find.byIcon(FLucideIcons.search));

    expect(icon.left - field.left, padding);
    // And it is sized off the text beside it rather than off Forui's ramp.
    expect(icon.width, 14);
    // The hint still follows the icon rather than sitting under it.
    expect(
      tester.getRect(find.text('Search recipes')).left,
      greaterThan(icon.right),
    );
  });
}
