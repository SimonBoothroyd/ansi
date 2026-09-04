/// Parsing the extraction's `yield_raw` into a prefilled MAKES row — PURE DART
/// (invariant 2), and deliberately the smallest parser that could work.
///
/// Extraction already captures what the page printed about what it makes
/// (`"MAKES: 8 SLIDERS"`), and until 8.6 commit dropped it on the floor. The
/// board's frame (h) rules what may come back out of it: **a plain
/// `amount + unit` and nothing else**. "MAKES: 8 SLIDERS" prefills `8 piece`,
/// "MAKES 1 CUP" prefills `1 cup`, and "MAKES ENOUGH FOR A CROWD" prefills
/// NOTHING — the fields stay empty over the still-visible source line and wait
/// for a human (the attempt-then-flag pattern 0014 ruled for servings, on the
/// same screen).
///
/// Why so little: a yield is not display text. Every derived batch, cook
/// session, shopping quantity and macro share downstream divides by it (D2), so
/// a wrong yield poisons numbers all over the app silently, while an empty
/// field is honest and one tap from right. When in doubt this refuses.
library;

import '../../../core/units/unit_words.dart';
import '../../../core/units/units.dart';

/// A prefilled yield: what one batch makes, as one denomination. The review
/// screen carries only the first (frame h draws one row there); a second
/// denomination is added in the editor afterwards.
typedef YieldPrefill = ({double qty, Unit unit});

/// The prefixes a printed yield line wears, stripped case-insensitively along
/// with a following colon — "MAKES: 8 SLIDERS", "Yields 12 muffins".
///
/// `serves` is NOT here: that is the servings fact, which has its own field.
const kYieldPrefixes = <String>['makes', 'yields', 'yield'];

/// Words that name a unit a yield cannot be stated IN, so they must refuse
/// rather than fall through to the count fallback below.
///
/// `batch` is what a yield is measured *against* ("makes 1 batch" says
/// nothing), and an imprecise word carries no number to divide by. Both would
/// otherwise read as plain count nouns — "makes 2 pinch" is not 2 pieces.
const kYieldRefusedWords = <String>[
  'batch',
  'batches',
  'pinch',
  'pinches',
  'dash',
  'dashes',
  'handful',
  'handfuls',
  'taste',
];

/// Words that name a PORTION, not a yield denomination: "makes 4 servings" is
/// the servings fact wearing a MAKES prefix, and prefilling it as `4 piece`
/// would state something the page never said. Refused, not guessed.
const kYieldPortionWords = <String>[
  'serving',
  'servings',
  'serve',
  'serves',
  'portion',
  'portions',
  'person',
  'people',
];

/// The vulgar fractions a printed amount uses, and what they are worth.
const _fractionGlyphs = <String, double>{
  '¼': 0.25,
  '½': 0.5,
  '¾': 0.75,
  '⅓': 1 / 3,
  '⅔': 2 / 3,
  '⅕': 0.2,
  '⅖': 0.4,
  '⅗': 0.6,
  '⅘': 0.8,
  '⅙': 1 / 6,
  '⅛': 0.125,
  '⅜': 0.375,
  '⅝': 0.625,
  '⅞': 0.875,
};

/// What [raw] says one batch makes, or null when it does not plainly say.
///
/// The whole rule:
///
/// 1. strip a leading `MAKES`/`YIELDS`-style prefix and its colon;
/// 2. what is left must be a number, optionally followed by ONE word;
/// 3. that word is a catalog unit if [unitFromWord] knows it ("1 CUP" →
///    `1 cup`), and otherwise a plain count noun — the page's own name for the
///    thing it makes ("8 SLIDERS" → `8 piece`), which is what makes the board's
///    sausage answer fall out;
/// 4. anything else — extra words, a portion word ([kYieldPortionWords]), an
///    imprecise or `batch` word ([kYieldRefusedWords]), no number, a
///    non-positive amount — refuses.
///
/// Nothing is invented at any step: every accepted parse states a number the
/// page printed, in a family the page's own word names.
YieldPrefill? parseYieldRaw(String? raw) {
  final text = (raw ?? '').trim();
  if (text.isEmpty) return null;

  final stripped = _stripPrefix(text);
  // Punctuation the printed line trails ("Makes 1 cup.") is noise, not words.
  final words = stripped
      .replaceAll(RegExp(r'[.,;]+$'), '')
      .split(RegExp(r'\s+'))
      .where((w) => w.isNotEmpty)
      .toList();
  if (words.isEmpty || words.length > 2) return null;

  final qty = _number(words.first);
  if (qty == null || qty <= 0) return null;
  if (words.length == 1) return (qty: qty, unit: pieces);

  final word = words[1].toLowerCase().replaceAll(RegExp('[^a-z]'), '');
  if (word.isEmpty) return null;
  if (kYieldPortionWords.contains(word)) return null;
  if (kYieldRefusedWords.contains(word)) return null;

  final unit = unitFromWord(word);
  if (unit == null) {
    // An unknown word after a number is the page naming what it makes —
    // "8 SLIDERS", "12 muffins". That is a COUNT of the yield, which is
    // exactly what `piece` means; the noun itself is display text the source
    // line still shows.
    return (qty: qty, unit: pieces);
  }
  // A yield is what other amounts are measured AGAINST, so the two families
  // that cannot be measured against refuse: `batch` is circular and imprecise
  // words carry no number to divide by.
  if (unit.family == UnitFamily.imprecise || unit.family == UnitFamily.batch) {
    return null;
  }
  return (qty: qty, unit: unit);
}

/// [text] with one leading MAKES-style prefix (and its colon) removed.
String _stripPrefix(String text) {
  final lower = text.toLowerCase();
  for (final prefix in kYieldPrefixes) {
    if (!lower.startsWith(prefix)) continue;
    final rest = text.substring(prefix.length).trimLeft();
    // "makes" must be a whole word: "makesomething" is not a prefix.
    if (rest.isNotEmpty && RegExp('[a-zA-Z]').hasMatch(rest[0])) continue;
    return rest.startsWith(':') ? rest.substring(1).trim() : rest.trim();
  }
  return text;
}

/// [word] as a number: `8`, `1.5`, `1,5`, `1/2`, `½`, `1½`. Null when it is
/// not one — which is the parser's whole refusal path.
double? _number(String word) {
  final text = word.replaceAll(',', '.');
  final plain = double.tryParse(text);
  if (plain != null) return plain;

  final slash = RegExp(r'^([0-9]+)/([0-9]+)$').firstMatch(text);
  if (slash != null) {
    final denominator = double.parse(slash.group(2)!);
    if (denominator == 0) return null;
    return double.parse(slash.group(1)!) / denominator;
  }

  // A vulgar fraction, alone ("½") or after a whole number ("1½").
  final glyph = text.isEmpty ? null : _fractionGlyphs[text[text.length - 1]];
  if (glyph == null) return null;
  final whole = text.substring(0, text.length - 1);
  if (whole.isEmpty) return glyph;
  final leading = double.tryParse(whole);
  return leading == null ? null : leading + glyph;
}
