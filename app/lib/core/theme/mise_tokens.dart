import 'dart:ui';

/// Design tokens from the "Mise" design board (docs/product-specs/design-board.html).
/// Pure colour constants — no Flutter widget imports — so they can be mapped
/// into a Forui theme in `mise_theme.dart` without coupling.
abstract final class MiseColors {
  static const surface = Color(0xFFFFFFFF);
  static const paper = Color(0xFFF4F6F1);
  static const ink = Color(0xFF18211C);
  static const muted = Color(0xFF66736A);
  static const line = Color(0xFFE2E7DD);

  static const herb = Color(0xFF2C6A3A);
  static const herbDeep = Color(0xFF21502C);
  static const herbSoft = Color(0xFFE6EFE6);

  // The freshness scale: fresh → aging → gone.
  static const fresh = Color(0xFF4E9E5B);
  static const aging = Color(0xFFE1A63A);
  static const gone = Color(0xFFC64B36);

  // A frozen hold — a light, icy blue in the freezer note's hue, saturated
  // just enough to read on the neutral bar. Not part of the freshness scale:
  // freezing pauses aging rather than advancing it.
  static const frozen = Color(0xFF83B4D2);
}
