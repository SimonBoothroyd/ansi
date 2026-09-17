/// What the ingredient page says about a row while it is being **read** — one
/// line per fact, in the words the form's own fields and entries already use.
///
/// Pure functions, apart from the widgets, because the page has two postures
/// over one route and the fastest way to make them disagree is to let each
/// write its own sentence. Every line here is a stored fact restated, never a
/// new one: the macro line is the picker row's ([formatMacroLine]), the density
/// is the density entry's own headline plus the sentence it was entered as
/// (read back through [volumeWeightFromDensity]), the piece weight is the
/// piece-weight entry's sentence with its number in place, and the admitted
/// units are the chips' own labels off [allowedUnitsFor].
///
/// **Honest numbers (invariant 3).** A row with no macros reads `needs macros`
/// — the words the dock and the manager's stub band already use — never four
/// zeros. A row whose macros are a machine's and unconfirmed states them: the
/// status strip above says they are left out of totals, which is the fact the
/// page owes a reader, and hiding numbers the editing posture shows would be
/// the two postures telling two stories.
library;

import '../../../core/money.dart';
import '../../../core/result/result.dart';
import '../../../core/units/macros.dart';
import '../../../core/units/measure.dart';
import '../../../core/units/units.dart';
import '../../../core/words.dart';
import '../../../shared/format.dart';
import '../domain/allowed_units.dart';
import '../domain/ingredient.dart';
import '../domain/price.dart';
import '../domain/serving_measure.dart';
import 'macros_format.dart';

/// The volume unit a stored density is read back in on a row that names no
/// friendlier one. A ratio is not something a kitchen holds, and `cup` is the
/// measure a person can picture.
const kDensityReadingUnit = cup;

/// `60 kcal · 1P 0F 15C /100 g`, or `needs macros` on a row that has none.
///
/// **A row that states a serving leads with the label's own line** —
/// `190 kcal · 7P 16F 7C per 2 tbsp` — because that is the line a person can
/// check against the jar in their hand without a calculator. The per-100
/// figures then read as the aside they are ([per100Fact]).
String macrosFact(Ingredient ingredient, {Measure? serving}) {
  final figures = macrosFactFigures(ingredient, serving: serving);
  if (figures == null) return 'needs macros';
  return '${formatMacroLine(figures.macros)} ${figures.per}';
}

/// The same fact as its two parts — the figures, and the tail that says what
/// they are per — for the posture that draws it as one dense line, energy as
/// a glyph. Null on a row with no panel, where [macrosFact]'s words are the
/// whole answer.
({Macros macros, String per})? macrosFactFigures(
  Ingredient ingredient, {
  Measure? serving,
}) {
  final macros = ingredient.macros;
  if (macros == null) return null;
  final printed = servingPrintedMacros(ingredient, serving: serving);
  if (printed == null || serving == null) {
    return (macros: macros, per: macroBasisSuffix(ingredient.macrosBasis));
  }
  return (
    macros: printed,
    per: 'per ${serving.label.substring(kServingMeasurePrefix.length)}',
  );
}

/// The label's figures, reversed out of the stored per-100 and the serving —
/// `642 kcal/100 ml × 29.57 ml` back to the 190 the jar prints.
///
/// It is the entry arithmetic run backwards, unrounded, which is exactly why
/// the serving is kept: nothing is re-derived from a rounded figure and
/// nothing is invented. Null on a row with no macros or no serving.
Macros? servingPrintedMacros(Ingredient ingredient, {Measure? serving}) {
  final macros = ingredient.macros;
  if (macros == null || serving == null || !(serving.amount > 0)) return null;
  if (serving.basis != ingredient.macrosBasis) return null;
  return macros.scaledBy(serving.amount / 100);
}

/// `per 100 ml · 642 kcal · 23.7P 54.1F 23.7C` — the muted line under a
/// label-led macro fact, for the reader who wants to see what the totals use.
/// Null where the fact already says it.
String? per100Fact(Ingredient ingredient, {Measure? serving}) {
  final macros = ingredient.macros;
  if (macros == null ||
      servingPrintedMacros(ingredient, serving: serving) == null) {
    return null;
  }
  return 'per 100 ${ingredient.macrosBasis.dbValue} · '
      '${formatMacroLine(macros)}';
}

/// The row's category, in the picker's own word for a row without one — a
/// category-less row is a real and honest answer, not a gap.
String categoryFact(Ingredient ingredient) {
  final category = ingredient.category;
  return category == null || category.isEmpty ? 'no category' : category;
}

/// What a line may say about this row — the admission chips, as their labels.
String allowedUnitsFact(Ingredient ingredient) =>
    allowedUnitsFor(ingredient).map((u) => u.label).join(' · ');

/// The stated density, as the sentence it was entered as and the number it is
/// stored as: `1 cup weighs 156.15 g · 0.66 g/ml`. A row with none says what
/// the density entry's own headline says.
///
/// **A row whose serving is a volume reads the density back in that unit** —
/// `2 tbsp weighs 32 g` — with the g/ml as the aside ([densityAsideFact]),
/// because that is the sentence the pack printed and the one that was typed.
/// A row with no serving reads it in its own default unit where that is a
/// volume ([densityReading]). The stored fact is unchanged either way: one
/// ratio, said in the unit the person is holding.
String densityFact(Ingredient ingredient, {Measure? serving}) {
  final density = ingredient.densityGPerMl;
  if (density == null) return 'none yet — unlocks volume⇄weight';
  final read = densityReading(ingredient, serving: serving);
  final grams = densityReadingWeight(ingredient, serving: serving);
  final stated = '${formatDensity(density)} g/ml';
  if (grams == null) return stated;
  final phrase = formatServingPhrase(read.amount, read.unit);
  final sentence = '$phrase weighs ${formatQuantityIn(grams, g)} g';
  // `1 ml weighs 1.08 g` IS `1.08 g/ml`, so a row read in millilitres has no
  // aside to carry — it would print the same number twice in one line.
  if (read.unit == ml && read.amount == 1) return sentence;
  return read.fromServing ? sentence : '$sentence · $stated';
}

/// `1.08 g/ml` — the aside under a serving-shaped density sentence, or null
/// where [densityFact] already carries the number.
String? densityAsideFact(Ingredient ingredient, {Measure? serving}) {
  final density = ingredient.densityGPerMl;
  if (density == null ||
      !densityReading(ingredient, serving: serving).fromServing) {
    return null;
  }
  return '${formatDensity(density)} g/ml';
}

/// **Which amount and unit this row's density is SAID in** — the one
/// derivation the fact sheet reads a stored density back through and the
/// density entry opens its sentence on, so a number entered as "1 tsp weighs
/// 5 g" never reads back as a cup and never reopens as one.
///
/// In order of how much the row itself has said:
/// 1. its own **serving**, when that is a volume — the sentence the pack
///    printed and the one that was typed;
/// 2. its **default unit**, when that is a volume — the word this row is
///    counted in, so the reading is in the unit a line will say;
/// 3. [kDensityReadingUnit] — the cup a person can picture, for a row that
///    names nothing friendlier.
///
/// The `fromServing` field says whether the first leg won: that is the
/// reading the fact sheet leads with, moving the `g/ml` into an aside beneath
/// it.
({double amount, Unit unit, bool fromServing}) densityReading(
  Ingredient ingredient, {
  Measure? serving,
}) {
  final stated = serving == null
      ? null
      : servingFromMeasureLabel(serving.label);
  if (stated != null && stated.unit.family == UnitFamily.volume) {
    return (amount: stated.amount, unit: stated.unit, fromServing: true);
  }
  final byDefault = ingredient.defaultUnit;
  if (byDefault.family == UnitFamily.volume) {
    return (amount: 1, unit: byDefault, fromServing: false);
  }
  return (amount: 1, unit: kDensityReadingUnit, fromServing: false);
}

/// What a stored density comes to in the unit this row says it in — the
/// weight slot of the entry's sentence, and the grams the fact sheet prints.
/// Null on a row with no density, or one whose reading unit cannot carry it.
double? densityReadingWeight(Ingredient ingredient, {Measure? serving}) {
  final density = ingredient.densityGPerMl;
  if (density == null) return null;
  final read = densityReading(ingredient, serving: serving);
  final perUnit = volumeWeightFromDensity(read.unit, density);
  return perUnit == null ? null : perUnit * read.amount;
}

/// The stated piece weight as the piece-weight entry's own sentence — `1 piece
/// weighs 200 g` — or null on a row that states none, where there is no
/// sentence to say.
String? pieceWeightFact(Ingredient ingredient) {
  final weight = ingredient.pieceBasisAmount;
  if (weight == null) return null;
  final basis = ingredient.macrosBasis.baseUnit;
  return '1 piece weighs ${formatQuantityIn(weight, basis)} ${basis.label}'
      '${pieceWeightSourceSuffix(ingredient.pieceSource)}';
}

/// ` · borrowed from onion, medium` for a seeded weight; nothing for a typed
/// one — "yours" is the default reading of a row you own. A curated seed
/// number reads **estimate**, the same word the measures list gives it.
///
/// Shared with the piece-weight entry's own headline, so the number reads the
/// same whether the page is being edited or read.
String pieceWeightSourceSuffix(String? source) {
  if (source == null || source == 'manual') return '';
  if (source == 'seed:typical') return ' · estimate';
  return ' · $source';
}

/// The other names this row answers to, joined — empty when it has none.
String aliasesFact(Iterable<IngredientAlias> aliases) =>
    aliases.map((a) => a.text).join(' · ');

/// One measure, in the measures editor's own words: `onion, medium · 110 g`.
/// The provenance word rides beside it on the row rather than inside this
/// string, exactly as the editor draws it.
String measureFact(Measure measure) {
  final basis = measure.basis.baseUnit;
  return '${measure.label} · ${formatQuantityIn(measure.amount, basis)} '
      '${basis.label}';
}

// --- The price group's sentences ---------------------------------------------
//
// One rule, three surfaces: the group's Latest line, its Before rows and the
// price sheet's own header all restate the same stored facts, so a wording
// that changes changes once.

/// What the cents bought, as the person said it: `bag (454 g)` where the pack
/// was named as a measure, `454 g` where it was typed as a plain amount.
///
/// The weight is always there, because the weight is the fact — the label is
/// how it was said, and a measure deleted since leaves the number standing.
String pricePackPhrase(PriceObservation price) {
  final basis = price.basis.baseUnit;
  final weight =
      '${formatQuantityIn(price.packBasisAmount, basis)} ${basis.label}';
  final label = price.packLabel;
  return label == null || label.isEmpty ? weight : '$label ($weight)';
}

/// The **latest** price as the group's one line — `77¢ / 100 g · $3.49 for bag
/// (454 g) · TJ's · 13 Sep`.
///
/// The per-100 figure leads because it is the one a recipe reads; everything
/// after it is what was paid, restated, so a figure that looks wrong is
/// traceable to the purchase that made it.
String latestPriceFact(PriceObservation price) {
  final paid = formatMoney(price.paidCents);
  final head = switch (price.per100) {
    Ok(:final value) => '${formatPricePer100(value)} · ',
    // A stored price that cannot be read is not shown as a zero: the line
    // leads with what was paid, and the derivation is simply absent.
    Err() => '',
  };
  return '$head$paid for ${pricePackPhrase(price)} · ${price.store} · '
      '${formatDayMonth(price.purchasedAt)}';
}

/// One **earlier** price, as the history row's own two parts: what it came to
/// and what was paid (`72¢ / 100 g · $3.29 · bag (454 g)`), and where and when
/// it was seen (`TJ's · 23 Aug`).
({String paid, String seen}) earlierPriceFact(PriceObservation price) {
  final head = switch (price.per100) {
    Ok(:final value) => '${formatPricePer100(value)} · ',
    Err() => '',
  };
  return (
    paid: '$head${formatMoney(price.paidCents)} · ${pricePackPhrase(price)}',
    seen: '${price.store} · ${formatDayMonth(price.purchasedAt)}',
  );
}

/// What the price sheet says over its fields about the price it is replacing —
/// `latest 72¢ / 100 g · TJ's · Aug` — or null on a row nobody has priced,
/// where there is nothing to replace and nothing to say.
///
/// The month alone, not the day: the sheet is about the price being entered,
/// and the last one is context rather than a record.
String? latestPriceAside(PriceObservation? price) {
  if (price == null) return null;
  final head = switch (price.per100) {
    Ok(:final value) => formatPricePer100(value),
    Err() => formatMoney(price.paidCents),
  };
  return 'latest $head · ${price.store} · '
      '${formatMonthShort(price.purchasedAt)}';
}

/// Why a price cannot be read from what has been typed — the sentence the
/// sheet's dock states in place of the figure, and the reason Done is refused.
///
/// Every one of them names a way out, because a refusal a person can act on
/// beats one they can only stare at. The codes are the unit system's own and
/// the price domain's; an unfamiliar one says the plain thing rather than
/// printing a code at somebody.
String priceRefusal(Failure failure, Ingredient ingredient) {
  final basis = ingredient.macrosBasis.baseUnit;
  return switch (failure.code) {
    'unit/no_density' =>
      'this row has no density, so a volume pack cannot be weighed — set one '
          'on the ingredient, or say the pack in ${basis.label}',
    'unit/incompatible' =>
      'this row does not say what one piece weighs — set a piece weight, or '
          'say the pack in ${basis.label}',
    'unit/imprecise' =>
      'an imprecise word cannot be priced — say the pack in ${basis.label}',
    'price/no_pack' => 'say what the money bought',
    'price/nothing_paid' => 'say what you paid',
    _ => failure.message,
  };
}
