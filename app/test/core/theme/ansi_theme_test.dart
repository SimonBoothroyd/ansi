// The bottom bar's selected contrast (plan 0025 D7d).
//
// With the week switcher as every tab's title, the lit tab in the bar carries
// the whole "where am I", so its colour is a fact worth pinning: the selected
// item steps herb → herbDeep, the unselected stays muted. The ratios below are
// WCAG 2.x relative-luminance contrast (sRGB → linear, (L1 + 0.05) / (L2 +
// 0.05)) against the bar's ground, `AnsiColors.surface`, and are recorded in
// the test names so a palette change has to say what it did to them.
import 'dart:math' as math;

import 'package:ansi/core/theme/ansi_theme.dart';
import 'package:ansi/core/theme/ansi_tokens.dart';
import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:forui/forui.dart';

double _linear(double channel) => channel <= 0.03928
    ? channel / 12.92
    : math.pow((channel + 0.055) / 1.055, 2.4).toDouble();

double _luminance(Color c) =>
    0.2126 * _linear(c.r) + 0.7152 * _linear(c.g) + 0.0722 * _linear(c.b);

/// The WCAG contrast ratio, always ≥ 1 (lighter over darker).
double _contrast(Color a, Color b) {
  final la = _luminance(a);
  final lb = _luminance(b);
  return (math.max(la, lb) + 0.05) / (math.min(la, lb) + 0.05);
}

void main() {
  final selected = _contrast(AnsiColors.herbDeep, AnsiColors.surface);
  final unselected = _contrast(AnsiColors.muted, AnsiColors.surface);
  final between = _contrast(AnsiColors.herbDeep, AnsiColors.muted);
  final before = _contrast(AnsiColors.herb, AnsiColors.surface);
  final betweenBefore = _contrast(AnsiColors.herb, AnsiColors.muted);

  test('selected herbDeep on surface is 9.34:1 — AAA at any size (≥ 7:1)', () {
    expect(selected, closeTo(9.34, 0.01));
    expect(selected, greaterThanOrEqualTo(7));
  });

  test('unselected muted on surface is 4.97:1 — AA, unchanged by D7d', () {
    expect(unselected, closeTo(4.97, 0.01));
    expect(unselected, greaterThanOrEqualTo(4.5));
  });

  test("selected vs unselected is 1.88:1 (≥ 1.8:1), up from herb's 1.31:1", () {
    expect(between, closeTo(1.88, 0.01));
    expect(between, greaterThanOrEqualTo(1.8));
    // The state the owner found too close, for the record.
    expect(before, closeTo(6.50, 0.01));
    expect(betweenBefore, closeTo(1.31, 0.01));
  });

  test('the theme resolves the selected bar item to herbDeep and leaves the '
      'unselected one muted, weights untouched', () {
    final item = ansiThemeData().bottomNavigationBarStyle.itemStyle;

    final selectedIcon = item.iconStyle.resolve({FTappableVariant.selected});
    final selectedText = item.textStyle.resolve({FTappableVariant.selected});
    expect(selectedIcon.color, AnsiColors.herbDeep);
    expect(selectedText.color, AnsiColors.herbDeep);
    // Only the colour steps; Forui's own selected weight stays.
    expect(selectedIcon.weight, 700);
    expect(selectedText.fontWeight, FontWeight.bold);

    final restIcon = item.iconStyle.resolve(const {});
    final restText = item.textStyle.resolve(const {});
    expect(restIcon.color, AnsiColors.muted);
    expect(restText.color, AnsiColors.muted);
  });
}
