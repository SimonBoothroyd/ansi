/// The Shop's notes say everything they hold on a phone: measured in the
/// faces the app draws with, since the test font is twice as wide.
library;

import 'package:ansi/core/theme/ansi_theme.dart';
import 'package:ansi/features/recipes/domain/effective_lines.dart';
import 'package:ansi/features/shopping/domain/shopping.dart';
import 'package:ansi/features/shopping/presentation/shopping_view.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:forui/forui.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

import '../../helpers/fonts.dart';

Future<void> _pump(
  WidgetTester tester,
  Widget echo, {
  required double width,
  double textScale = 1,
}) async {
  tester.view.physicalSize = Size(width, 600);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    ProviderScope(
      child: MaterialApp(
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(textScaler: TextScaler.linear(textScale)),
          child: FTheme(data: ansiThemeData(), child: child!),
        ),
        home: FToaster(
          child: Align(alignment: Alignment.topLeft, child: echo),
        ),
      ),
    ),
  );
}

/// Whether every character of [words] is drawn inside its paragraph.
bool _drawn(WidgetTester tester, String words) {
  for (final p in tester.renderObjectList<RenderParagraph>(
    find.byType(RichText),
  )) {
    final at = p.text.toPlainText().indexOf(words);
    if (at < 0) continue;
    for (var i = at; i < at + words.length; i++) {
      if (words[i - at] == ' ') continue;
      final boxes = p.getBoxesForSelection(
        TextSelection(baseOffset: i, extentOffset: i + 1),
      );
      if (boxes.isEmpty ||
          boxes.first.right > p.size.width + 0.5 ||
          boxes.first.top >= p.size.height) {
        return false;
      }
    }
    return true;
  }
  return false;
}

void main() {
  setUpAll(loadAnsiFonts);

  const names = ['lime', 'coriander', 'red chilli', 'toasted cashews'];
  LeftOutEcho leftOut(String title, {required int count}) => LeftOutEcho(
    note: (
      recipeId: 'r',
      recipeTitle: title,
      names: names.take(count).toList(),
      lineIds: names.take(count).toList(),
      reason: LineDropReason.thisWeek,
    ),
  );

  for (final (width, scale) in [(360.0, 1.0), (402.0, 1.0), (360.0, 1.3)]) {
    group('at $width, text ×$scale', () {
      for (final title in ['Dal', 'Weeknight Chicken Curry']) {
        for (var count = 1; count <= names.length; count++) {
          testWidgets('$title draws all of $count left out', (tester) async {
            await _pump(
              tester,
              leftOut(title, count: count),
              width: width,
              textScale: scale,
            );
            for (final name in names.take(count)) {
              expect(_drawn(tester, name), isTrue, reason: name);
            }
          });
        }
      }

      testWidgets('an unresolved component says where to go', (tester) async {
        await _pump(
          tester,
          const UnresolvedEcho(
            note: (
              recipeId: 'r',
              recipeTitle: 'Weeknight Chicken Curry',
              count: 2,
            ),
          ),
          width: width,
          textScale: scale,
        );
        expect(_drawn(tester, 'see Cook'), isTrue);
      });

      testWidgets('a removed ingredient says where to pick again', (
        tester,
      ) async {
        await _pump(
          tester,
          const RetiredIngredientEcho(
            note: (
              heading: 'Weeknight Chicken Curry',
              ingredientName: 'Sauerkraut',
              site: RetiredIngredientSite.recipeLine,
            ),
          ),
          width: width,
          textScale: scale,
        );
        expect(_drawn(tester, 'pick again in the recipe'), isTrue);
      });
    });
  }
}
