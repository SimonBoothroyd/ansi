import 'dart:ui';

/// Design tokens from the design board
/// (docs/product-specs/design-board.html). Pure colour constants with no
/// widget imports; `ansi_theme.dart` maps them into a Forui theme.
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

  // A frozen hold. Not on the freshness scale: freezing pauses aging.
  static const frozen = Color(0xFF83B4D2);

  // The caution family: the amber wash, its border and its ink, shared by
  // every warning.
  static const caution = Color(0xFFFBF3E3);
  static const cautionLine = Color(0xFFF0DCB0);
  static const cautionInk = Color(0xFF7A5A16);

  // The chill family: the freezer note's blue. A hold, not a warning.
  static const chill = Color(0xFFEAF1F5);
  static const chillLine = Color(0xFFD2E2EC);
  static const chillInk = Color(0xFF3B6076);

  // The alarm family: the wash behind a refusal. Its ink is [gone].
  static const alarm = Color(0xFFFBEEEA);
  static const alarmLine = Color(0xFFE7C3BA);
}

/// The confetti's eight colours, used only by the burst that plays when the
/// last shopping row is ticked. [herb] and [herbDeep] are the palette's own
/// greens.
abstract final class AnsiConfetti {
  static const herb = AnsiColors.herb;
  static const tomato = Color(0xFFD9482B);
  static const butter = Color(0xFFE8B531);
  static const blueberry = Color(0xFF4B6FCB);
  static const carrot = Color(0xFFE07A2E);
  static const plum = Color(0xFF8B4B9E);
  static const herbDeep = AnsiColors.herbDeep;
  static const beet = Color(0xFFC93A6E);

  /// Every colour a piece may take, in the order the board lists them.
  static const all = <Color>[
    herb,
    tomato,
    butter,
    blueberry,
    carrot,
    plum,
    herbDeep,
    beet,
  ];
}

/// Corner radii, by the shape a thing is: a pill, a card, or a note box.
abstract final class AnsiRadii {
  static const pill = 999.0;
  static const card = 12.0;
  static const box = 10.0;
}

/// The voice a callout speaks in: a caution, a hold, or a refusal.
enum AnsiTone {
  caution(AnsiColors.caution, AnsiColors.cautionLine, AnsiColors.cautionInk),
  chill(AnsiColors.chill, AnsiColors.chillLine, AnsiColors.chillInk),
  alarm(AnsiColors.alarm, AnsiColors.alarmLine, AnsiColors.gone);

  const AnsiTone(this.fill, this.line, this.ink);

  final Color fill;
  final Color line;
  final Color ink;
}
