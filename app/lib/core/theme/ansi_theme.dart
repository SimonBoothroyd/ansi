/// The app's Forui theme, built from the Ansi design tokens.
///
/// The Ansi visual identity lives in the [FThemeData] returned by
/// [ansiThemeData]; `app.dart` applies it via Forui's `FTheme`. A tiny Material
/// [ansiHostTheme] tints the `MaterialApp.router` host (the WidgetsApp
/// go_router needs) so nothing flashes un-themed behind the Forui tree.
///
/// Typography follows the design board's three roles:
/// * **serif** ([ansiSerif]) — recipe titles and lowercase group headers,
/// * **sans** (Forui's default) — all interface text,
/// * **mono** ([ansiMono]) — data: quantities, units, scale factors, and the
///   letter-spaced uppercase micro-labels ([ansiLabel]).
///
/// The exact faces (Spectral / Inter / IBM Plex Mono) are named first in each
/// fallback list; when they aren't bundled the platform's generic families take
/// over, preserving the hierarchy without any runtime font download.
library;

import 'package:flutter/material.dart';
import 'package:forui/forui.dart';

import 'ansi_tokens.dart';

/// The real Ansi theme: Forui's Zinc light theme recoloured with [AnsiColors].
FThemeData ansiThemeData() {
  final colors = FColors.zincLight.copyWith(
    background: AnsiColors.surface,
    foreground: AnsiColors.ink,
    primary: AnsiColors.herb,
    primaryForeground: AnsiColors.paper,
    secondary: AnsiColors.herbSoft,
    secondaryForeground: AnsiColors.herbDeep,
    muted: AnsiColors.herbSoft,
    mutedForeground: AnsiColors.muted,
    border: AnsiColors.line,
    card: AnsiColors.surface,
  );
  return FThemeData(colors: colors, touch: true, debugLabel: 'Ansi').copyWith(
    // The bottom bar's selected item steps herb → herbDeep. With the switcher
    // as every tab's title the lit tab carries the whole "where am I", and
    // Forui's default (selected = primary, herb 6.50:1 on the bar's white;
    // unselected = mutedForeground, muted 4.97:1) put the two states only
    // 1.31:1 apart. herbDeep is 9.34:1 on surface and 1.88:1 from muted — the
    // same darkening `secondaryForeground` already uses, so no new colour
    // enters the palette. Only the selected variant's colour changes; its
    // weight (700 / bold) and the unselected state are Forui's.
    // `test/core/theme/ansi_theme_test.dart` measures both.
    bottomNavigationBarStyle: FBottomNavigationBarStyleDelta.delta(
      itemStyle: FBottomNavigationBarItemStyleDelta.delta(
        iconStyle: FVariantsDelta.delta([
          FVariantOperation.exact({
            FTappableVariantConstraint.selected,
          }, const IconThemeDataDelta.delta(color: AnsiColors.herbDeep)),
        ]),
        textStyle: FVariantsDelta.delta([
          FVariantOperation.exact({
            FTappableVariantConstraint.selected,
          }, const TextStyleDelta.delta(color: AnsiColors.herbDeep)),
        ]),
      ),
    ),
  );
}

/// A minimal Material theme for the `MaterialApp.router` host so the window
/// paints paper, not white, behind the Forui components.
ThemeData ansiHostTheme() => ThemeData(
  scaffoldBackgroundColor: AnsiColors.surface,
  canvasColor: AnsiColors.surface,
  useMaterial3: true,
);

const List<String> _serifStack = ['Spectral', 'Georgia', 'serif'];
const List<String> _monoStack = ['IBM Plex Mono', 'Menlo', 'monospace'];
// Inter comes from Forui (its default family), not a separate bundle.
const List<String> _sansStack = ['packages/forui/Inter'];

/// A serif style for titles and group headers.
TextStyle ansiSerif({
  required double size,
  Color color = AnsiColors.ink,
  FontWeight weight = FontWeight.w600,
}) => TextStyle(
  fontFamily: 'Spectral',
  fontFamilyFallback: _serifStack,
  fontSize: size,
  height: 1.15,
  color: color,
  fontWeight: weight,
);

/// The app-bar page title — one consistent serif across every screen's header
/// (design board `.ttl`), so the top bars read as one family. Use it for the
/// `FHeader`/`FHeader.nested` title on every screen. The recipe page is the
/// deliberate exception: a large in-body hero title instead of a bar title.
TextStyle ansiHeaderTitle() => ansiSerif(size: 20);

/// A sans style for interface text and ingredient/step body copy.
TextStyle ansiSans({
  required double size,
  Color color = AnsiColors.ink,
  FontWeight weight = FontWeight.w400,
  double height = 1.3,
}) => TextStyle(
  fontFamilyFallback: _sansStack,
  fontSize: size,
  height: height,
  color: color,
  fontWeight: weight,
);

/// A monospace style for data (quantities, units, scale factors).
TextStyle ansiMono({
  required double size,
  Color color = AnsiColors.ink,
  FontWeight weight = FontWeight.w400,
  double letterSpacing = 0,
}) => ansiMonoInherit(
  size: size,
  letterSpacing: letterSpacing,
).copyWith(color: color, fontWeight: weight);

/// [ansiMono] with no colour and no weight of its own, so both are inherited
/// from an ancestor [DefaultTextStyle].
///
/// A [Text]'s own style wins over the inherited one field by field, so a widget
/// whose selected/unselected colouring is driven from above — a Forui bottom
/// nav item, say — must leave those two fields unset or it opts itself out.
TextStyle ansiMonoInherit({required double size, double letterSpacing = 0}) =>
    TextStyle(
      fontFamily: 'IBM Plex Mono',
      fontFamilyFallback: _monoStack,
      fontSize: size,
      letterSpacing: letterSpacing,
    );

/// The letter-spaced uppercase micro-label ("FIND AN INGREDIENT", "SERVES").
TextStyle ansiLabel({Color color = AnsiColors.muted}) => ansiMono(
  size: 11,
  color: color,
  weight: FontWeight.w500,
  letterSpacing: 1.5,
);
