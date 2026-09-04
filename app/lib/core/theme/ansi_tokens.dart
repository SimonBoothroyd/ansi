import 'dart:ui';

/// Design tokens from the "Ansi" design board (docs/product-specs/design-board.html).
/// Pure colour constants — no Flutter widget imports — so they can be mapped
/// into a Forui theme in `ansi_theme.dart` without coupling.
abstract final class AnsiColors {
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

  // The caution family: the board's amber wash, its border and its ink. One
  // family, so a gap warning, a stalled-sync banner and an `incomplete` badge
  // are visibly the same voice rather than three shades of nearly-amber.
  static const caution = Color(0xFFFBF3E3);
  static const cautionLine = Color(0xFFF0DCB0);
  static const cautionInk = Color(0xFF7A5A16);

  // The chill family: the freezer note's blue. Not a warning — a hold.
  static const chill = Color(0xFFEAF1F5);
  static const chillLine = Color(0xFFD2E2EC);
  static const chillInk = Color(0xFF3B6076);

  // The alarm family: the wash behind a refusal. Its ink is [gone], the
  // freshness scale's own red, because the thing being reported is the same.
  static const alarm = Color(0xFFFBEEEA);
  static const alarmLine = Color(0xFFE7C3BA);
}

/// Corner radii, by the shape a thing is: a pill, a card, or a box that holds
/// a note. Three numbers so a fourth is a decision rather than a typo.
abstract final class AnsiRadii {
  static const pill = 999.0;
  static const card = 12.0;
  static const box = 10.0;
}

/// The voice a callout speaks in — a caution, a hold, or a refusal.
enum AnsiTone {
  caution(AnsiColors.caution, AnsiColors.cautionLine, AnsiColors.cautionInk),
  chill(AnsiColors.chill, AnsiColors.chillLine, AnsiColors.chillInk),
  alarm(AnsiColors.alarm, AnsiColors.alarmLine, AnsiColors.gone);

  const AnsiTone(this.fill, this.line, this.ink);

  final Color fill;
  final Color line;
  final Color ink;
}
