/// The app's Forui theme, built from the Mise design tokens.
///
/// The Mise visual identity lives in the [FThemeData] returned by
/// [miseThemeData]; `app.dart` applies it via Forui's `FTheme`. A tiny Material
/// [miseHostTheme] tints the `MaterialApp.router` host (the WidgetsApp
/// go_router needs) so nothing flashes un-themed behind the Forui tree.
///
/// Typography follows the design board's three roles:
/// * **serif** ([miseSerif]) — recipe titles and lowercase group headers,
/// * **sans** (Forui's default) — all interface text,
/// * **mono** ([miseMono]) — data: quantities, units, scale factors, and the
///   letter-spaced uppercase micro-labels ([miseLabel]).
///
/// The exact faces (Spectral / Inter / IBM Plex Mono) are named first in each
/// fallback list; when they aren't bundled the platform's generic families take
/// over, preserving the hierarchy without any runtime font download.
library;

import 'package:flutter/material.dart';
import 'package:forui/forui.dart';

import 'mise_tokens.dart';

/// The real Mise theme: Forui's Zinc light theme recoloured with [MiseColors].
FThemeData miseThemeData() {
  final colors = FColors.zincLight.copyWith(
    background: MiseColors.surface,
    foreground: MiseColors.ink,
    primary: MiseColors.herb,
    primaryForeground: MiseColors.paper,
    secondary: MiseColors.herbSoft,
    secondaryForeground: MiseColors.herbDeep,
    muted: MiseColors.herbSoft,
    mutedForeground: MiseColors.muted,
    border: MiseColors.line,
    card: MiseColors.surface,
  );
  return FThemeData(colors: colors, touch: true, debugLabel: 'Mise');
}

/// A minimal Material theme for the `MaterialApp.router` host so the window
/// paints paper, not white, behind the Forui components.
ThemeData miseHostTheme() => ThemeData(
  scaffoldBackgroundColor: MiseColors.surface,
  canvasColor: MiseColors.surface,
  useMaterial3: true,
);

const List<String> _serifStack = ['Spectral', 'Georgia', 'serif'];
const List<String> _monoStack = ['IBM Plex Mono', 'Menlo', 'monospace'];
// Inter comes from Forui (its default family), not a separate bundle.
const List<String> _sansStack = ['packages/forui/Inter'];

/// A serif style for titles and group headers.
TextStyle miseSerif({
  required double size,
  Color color = MiseColors.ink,
  FontWeight weight = FontWeight.w600,
}) => TextStyle(
  fontFamily: 'Spectral',
  fontFamilyFallback: _serifStack,
  fontSize: size,
  height: 1.15,
  color: color,
  fontWeight: weight,
);

/// A sans style for interface text and ingredient/step body copy.
TextStyle miseSans({
  required double size,
  Color color = MiseColors.ink,
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
TextStyle miseMono({
  required double size,
  Color color = MiseColors.ink,
  FontWeight weight = FontWeight.w400,
  double letterSpacing = 0,
}) => TextStyle(
  fontFamily: 'IBM Plex Mono',
  fontFamilyFallback: _monoStack,
  fontSize: size,
  color: color,
  fontWeight: weight,
  letterSpacing: letterSpacing,
);

/// The letter-spaced uppercase micro-label ("FIND AN INGREDIENT", "SERVES").
TextStyle miseLabel({Color color = MiseColors.muted}) => miseMono(
  size: 11,
  color: color,
  weight: FontWeight.w500,
  letterSpacing: 1.5,
);
