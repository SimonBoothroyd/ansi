/// Parsing the extraction's `yield_raw` into a prefilled MAKES row. Pure Dart.
///
/// Only a plain `amount + unit` is accepted: "MAKES: 8 SLIDERS" prefills `8
/// piece`, "MAKES 1 CUP" prefills `1 cup`, and "MAKES ENOUGH FOR A CROWD"
/// prefills nothing. Every derived batch, shopping quantity and macro share
/// divides by the yield, so when in doubt this refuses and leaves the fields
/// empty.
library;

import '../../../core/units/unit_words.dart';
import '../../../core/units/units.dart';

/// A prefilled yield: what one batch makes, as one denomination. A second
/// denomination is added in the editor afterwards.
typedef YieldPrefill = ({double qty, Unit unit});

/// The prefixes a printed yield line wears, stripped case-insensitively along
/// with a following colon. `serves` is not here: servings have their own field.
const kYieldPrefixes = <String>['makes', 'yields', 'yield'];

/// Words a yield cannot be stated in, which must refuse rather than fall
/// through to the count fallback: `batch` is circular, and an imprecise word
/// carries no number.
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

/// Words that name a portion: "makes 4 servings" is the servings fact, so it is
/// refused rather than prefilled as `4 piece`.
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
/// 1. Strip a leading `MAKES`/`YIELDS`-style prefix and its colon.
/// 2. What is left must be a number, optionally followed by one word.
/// 3. That word is a catalog unit if [unitFromWord] knows it ("1 CUP" → `1
///    cup`), otherwise a count noun ("8 SLIDERS" → `8 piece`).
/// 4. Anything else refuses: extra words, a portion word
///    ([kYieldPortionWords]), a refused word ([kYieldRefusedWords]), no number,
///    a non-positive amount.
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
    // An unknown word after a number is the page naming what it makes, which is
    // a count: `piece`.
    return (qty: qty, unit: pieces);
  }
  // `batch` and imprecise units cannot be measured against, so they refuse.
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
