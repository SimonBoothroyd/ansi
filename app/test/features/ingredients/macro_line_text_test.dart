/// Glyphs where the line is dense, words where there is room.
///
/// The two units that never change are also the two longest, so a dense line
/// draws them as a flame and a sheaf. What a screen reader hears must not
/// change with them, which is what the semantics assertions are for — and the
/// surfaces with room (the recipe panel's cells, the form's field labels)
/// must keep the words they have.
library;

import 'package:ansi/core/theme/ansi_theme.dart';
import 'package:ansi/core/units/macros.dart';
import 'package:ansi/features/ingredients/presentation/macro_line_text.dart';
import 'package:ansi/features/recipes/domain/recipe_macros.dart';
import 'package:ansi/features/recipes/presentation/recipe_macro_panel.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:forui/forui.dart';

import '../../helpers/macro_line.dart';

const _macros = Macros(kcal: 197, protein: 2, carb: 3, fat: 20, fiber: 1.5);

Widget _host(Widget child) => MaterialApp(
  home: FTheme(
    data: ansiThemeData(),
    child: Center(child: child),
  ),
);

void main() {
  testWidgets('the dense line draws a flame and a sheaf, and says "kcal" and '
      '"fibre" to a screen reader', (tester) async {
    final semantics = tester.ensureSemantics();
    await tester.pumpWidget(
      _host(MacroLineText(_macros, style: ansiMono(size: 10))),
    );

    expect(find.byIcon(kMacroEnergyIcon), findsOneWidget);
    expect(find.byIcon(kMacroFibreIcon), findsOneWidget);
    // The word is gone from the line…
    expect(find.textContaining('kcal'), findsNothing);
    expect(find.textContaining('fibre'), findsNothing);
    // …and not from what the line SAYS: each glyph carries the word it
    // replaced, so the whole line still reads out with its units.
    expect(
      tester
          .getSemantics(find.byType(MacroLineText))
          .label
          .replaceAll('\n', ''),
      '197 kcal · 2P 20F 3C · 1.5 fibre',
    );
    expect(macroText('197 kcal · 2P 20F 3C · 1.5 fibre'), findsOneWidget);

    semantics.dispose();
  });

  testWidgets('an unstated fibre draws no sheaf — the glyph follows the '
      'figure, and there is no figure', (tester) async {
    await tester.pumpWidget(
      _host(
        MacroLineText(
          const Macros(kcal: 60, protein: 1, carb: 15, fat: 0),
          style: ansiMono(size: 10),
        ),
      ),
    );

    expect(find.byIcon(kMacroEnergyIcon), findsOneWidget);
    expect(find.byIcon(kMacroFibreIcon), findsNothing);
    expect(macroText('60 kcal · 1P 0F 15C'), findsOneWidget);
  });

  testWidgets('the suffix rides after the line, and says what the figures are '
      'per', (tester) async {
    await tester.pumpWidget(
      _host(
        MacroLineText(_macros, style: ansiMono(size: 10), suffix: '/100 g'),
      ),
    );

    expect(
      macroText('197 kcal · 2P 20F 3C · 1.5 fibre /100 g'),
      findsOneWidget,
    );
  });

  testWidgets('the recipe panel’s cells keep their words — there is room for '
      'them, and the owner wants them there', (tester) async {
    await tester.pumpWidget(
      _host(
        const SizedBox(
          width: 360,
          child: RecipeMacroPanel(
            summary: RecipeMacroSummary(perServing: _macros),
          ),
        ),
      ),
    );

    expect(find.text('KCAL'), findsOneWidget);
    expect(find.text('FIBRE'), findsOneWidget);
    expect(find.byIcon(kMacroEnergyIcon), findsNothing);
    expect(find.byIcon(kMacroFibreIcon), findsNothing);
  });
}
