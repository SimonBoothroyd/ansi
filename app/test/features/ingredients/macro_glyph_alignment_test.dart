// A unit glyph must sit ON the digits it follows, at every size and every
// line height the app draws a macro line at.
//
// This is measured, not asserted from the widget tree: the numbers are painted
// ink and so is the glyph, and the only honest question is where their ink
// ends up. Each case renders `1234 <glyph>` in the real faces, reads the
// pixels back, and compares the vertical centre of the digits' ink with the
// vertical centre of the glyph's.
//
// `PlaceholderAlignment.middle` — what this line used to use — centres on the
// font's ascent/descent midpoint instead, which sits above the digits and
// moves with `TextStyle.height`; it measured 0.9 px and 1.4 px out at two of
// the three styles below.
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:ansi/core/theme/ansi_theme.dart';
import 'package:ansi/features/ingredients/presentation/macro_line_text.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/fonts.dart';

/// Pixels per logical pixel in the measured image. Eight puts the answer well
/// inside the tolerance below without making the images slow to scan.
const _ratio = 8;

/// How far apart the two ink centres may sit. It is a rasterising budget, not
/// a design allowance: Flutter centres an [Icon]'s glyph inside a box of its
/// own, and where that lands is quantised. Half a pixel at 11 pt is 0.05 em —
/// under the eye's threshold, and far under the 1.4 px the old alignment was
/// out by.
const _tolerance = 0.75;

/// The three styles a macro line is really drawn in: the recipe's ingredient
/// line, the day card's foot, the week's band.
const _styles = <String, (double, double?)>{
  'ingredient line': (10, 1.3),
  'day foot': (11, null),
  'week band': (13, null),
};

TextStyle _style(double size, double? height) {
  final base = ansiMono(size: size);
  return height == null ? base : base.copyWith(height: height);
}

bool _ink(Uint8List pixels, int width, int x, int y) {
  final i = (y * width + x) * 4;
  // Opaque and not white. The alpha guard matters: the white card's own
  // fractional edge blends to transparent, and unguarded it reads as a column
  // of ink down the whole image.
  return pixels[i + 3] == 255 &&
      (pixels[i] < 250 || pixels[i + 1] < 250 || pixels[i + 2] < 250);
}

/// The vertical centre of the ink in columns `[x0, x1)`, in logical pixels.
double _inkCentre(ui.Image image, Uint8List pixels, int x0, int x1) {
  var top = -1;
  var bottom = -1;
  for (var y = 0; y < image.height; y++) {
    for (var x = x0; x < x1; x++) {
      if (_ink(pixels, image.width, x, y)) {
        if (top == -1) top = y;
        bottom = y;
        break;
      }
    }
  }
  expect(top, isNot(-1), reason: 'no ink at all — did the font load?');
  return (top + bottom + 1) / 2 / _ratio;
}

/// Each contiguous block of inked columns. `1234 <glyph>` draws five: four
/// digits, then the glyph on its own after the space.
List<(int, int)> _columnRuns(ui.Image image, Uint8List pixels) {
  final runs = <(int, int)>[];
  int? start;
  for (var x = 0; x <= image.width; x++) {
    var inked = false;
    for (var y = 0; y < image.height && x < image.width; y++) {
      if (_ink(pixels, image.width, x, y)) {
        inked = true;
        break;
      }
    }
    if (inked && start == null) start = x;
    if (!inked && start != null) {
      runs.add((start, x));
      start = null;
    }
  }
  return runs;
}

/// Renders `1234 <icon>` in [style] and returns how far the glyph's ink
/// centre sits below the digits' — positive is low, negative is high — along
/// with the height of the line box it was drawn in.
Future<(double, double)> _measure(
  WidgetTester tester,
  IconData icon,
  TextStyle style,
) async {
  final key = GlobalKey();
  await tester.pumpWidget(
    Directionality(
      textDirection: TextDirection.ltr,
      child: Align(
        alignment: Alignment.topLeft,
        child: RepaintBoundary(
          key: key,
          child: ColoredBox(
            color: const Color(0xFFFFFFFF),
            child: Padding(
              padding: const EdgeInsets.all(8),
              child: Text.rich(
                TextSpan(
                  children: [
                    TextSpan(text: '1234 ', style: style),
                    macroUnitSpan(icon, label: 'kcal', style: style),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();

  final boundary =
      key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
  final image = (await tester.runAsync(
    () => boundary.toImage(pixelRatio: _ratio.toDouble()),
  ))!;
  final pixels = (await tester.runAsync(
    image.toByteData,
  ))!.buffer.asUint8List();

  final runs = _columnRuns(image, pixels);
  expect(runs.length, greaterThanOrEqualTo(2), reason: 'digits and a glyph');
  final digits = _inkCentre(
    image,
    pixels,
    runs.first.$1,
    runs[runs.length - 2].$2,
  );
  final glyph = _inkCentre(image, pixels, runs.last.$1, runs.last.$2);
  return (glyph - digits, tester.getSize(find.byType(RichText).first).height);
}

void main() {
  setUpAll(() async {
    await loadAnsiFonts();
    await loadLucideIcons();
  });

  for (final entry in _styles.entries) {
    final (size, height) = entry.value;
    final style = _style(size, height);

    testWidgets('the flame sits on the digits — ${entry.key}', (tester) async {
      final (offset, _) = await _measure(tester, kMacroEnergyIcon, style);
      expect(offset.abs(), lessThanOrEqualTo(_tolerance), reason: '$offset px');
    });

    testWidgets('the sheaf sits on the digits — ${entry.key}', (tester) async {
      final (offset, _) = await _measure(tester, kMacroFibreIcon, style);
      expect(offset.abs(), lessThanOrEqualTo(_tolerance), reason: '$offset px');
    });

    testWidgets('the glyph costs the line no height — ${entry.key}', (
      tester,
    ) async {
      final (_, withGlyph) = await _measure(tester, kMacroEnergyIcon, style);
      await tester.pumpWidget(
        Directionality(
          textDirection: TextDirection.ltr,
          child: Align(
            alignment: Alignment.topLeft,
            child: Text('1234', style: style),
          ),
        ),
      );
      // The glyph is dropped in paint, not in layout, so a line carrying one
      // is exactly as tall as the same line without it.
      expect(withGlyph, tester.getSize(find.byType(RichText).first).height);
    });
  }

  testWidgets('the alignment does not move with the line height', (
    tester,
  ) async {
    final offsets = <double>[];
    for (final height in [1.0, 1.3, 1.6]) {
      final (offset, _) = await _measure(
        tester,
        kMacroEnergyIcon,
        _style(11, height),
      );
      offsets.add(offset);
    }
    // Centring on the cap height is independent of `height` by construction;
    // what is left is the rasteriser's own quantisation.
    expect(
      offsets.reduce((a, b) => a > b ? a : b) -
          offsets.reduce((a, b) => a < b ? a : b),
      lessThanOrEqualTo(_tolerance),
      reason: '$offsets',
    );
  });
}
