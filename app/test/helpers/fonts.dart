/// Loads the app's real fonts into a widget test.
///
/// **Why any test would want this.** `flutter test` ships no fonts: every
/// glyph is drawn by a fallback whose advance is one em, so `weighs` measures
/// 78 pt where IBM Plex Mono draws it at 43. A layout assertion made under
/// that font is not a fact about the app — it is a fact about a square
/// typeface, and it fails on rows that fit a real phone perfectly.
///
/// So a test that asserts a LAYOUT (does this sentence hold one run at 402 pt?)
/// loads the real faces first and measures the real thing. A test that merely
/// asserts what is on screen does not need this and should not pay for it.
library;

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

/// The faces the app actually draws with: the bundled mono (quantities, units,
/// micro-labels) and Forui's Inter (interface text, so button widths are
/// real). Spectral is deliberately absent — no layout test measures a serif
/// title, and every face loaded costs every test in the file.
const _faces = {
  'IBM Plex Mono': 'assets/fonts/IBMPlexMono-Regular.ttf',
  'packages/forui/Inter': 'packages/forui/assets/fonts/inter/Inter-Regular.ttf',
};

/// Registers [_faces] with the test binding. Call from `setUpAll`.
Future<void> loadAnsiFonts() async {
  TestWidgetsFlutterBinding.ensureInitialized();
  for (final face in _faces.entries) {
    final loader = FontLoader(face.key)..addFont(rootBundle.load(face.value));
    await loader.load();
  }
}

/// Forui's Lucide icon font, so a test that MEASURES an icon (a unit glyph
/// among figures) gets the real glyph rather than a fallback's blank box.
Future<void> loadLucideIcons() async {
  TestWidgetsFlutterBinding.ensureInitialized();
  final loader = FontLoader('packages/forui_assets/ForuiLucideIcons')
    ..addFont(rootBundle.load('packages/forui_assets/assets/lucide.ttf'));
  await loader.load();
}
