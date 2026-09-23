/// What the ingredient page says about a row while it is being read: one line
/// per stored fact, in the words the form's fields already use.
///
/// Pure functions, so the page's reading and editing postures cannot disagree.
/// A row with no macros reads `needs macros`, never zeros; unconfirmed machine
/// macros are still shown, and the status strip says they are left out of
/// totals.
library;

import '../../../core/money.dart';
import '../../../core/result/result.dart';
import '../../../core/units/macros.dart';
import '../../../core/units/measure.dart';
import '../../../core/units/number_format.dart';
import '../../../core/units/units.dart';
import '../../../core/words.dart';
import '../../../shared/format.dart';
import '../domain/allowed_units.dart';
import '../domain/ingredient.dart';
import '../domain/price.dart';
import '../domain/price_repository.dart';
import '../domain/serving_measure.dart';
import 'macros_format.dart';

/// The volume unit a stored density is read back in when the row names no
/// friendlier one.
const kDensityReadingUnit = cup;

/// `60 kcal · 1P 0F 15C /100 g`, or `needs macros` on a row with none. A row
/// that states a serving leads with the label's line (`190 kcal · 7P 16F 7C per
/// 2 tbsp`); the per-100 figures follow as [per100Fact].
String macrosFact(Ingredient ingredient, {Measure? serving}) {
  final figures = macrosFactFigures(ingredient, serving: serving);
  if (figures == null) return 'needs macros';
  return '${formatMacroLine(figures.macros)} ${figures.per}';
}

/// The same fact as its two parts, the figures and what they are per, for the
/// posture that draws it as one dense line. Null on a row with no panel.
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

/// The label's figures, reversed out of the stored per-100 and the serving,
/// unrounded. Null on a row with no macros or no serving.
Macros? servingPrintedMacros(Ingredient ingredient, {Measure? serving}) {
  final macros = ingredient.macros;
  if (macros == null || serving == null || !(serving.amount > 0)) return null;
  if (serving.basis != ingredient.macrosBasis) return null;
  return macros.scaledBy(serving.amount / 100);
}

/// `per 100 ml · 642 kcal · 23.7P 54.1F 23.7C`: the muted line under a
/// label-led macro fact. Null where the fact already says it.
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

/// The stated density as the sentence it was entered as and the stored number:
/// `1 cup weighs 156.15 g · 0.66 g/ml`. A row with none says what the density
/// entry's headline says. A row whose serving is a volume reads it in that
/// unit, with the g/ml as [densityAsideFact].
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

/// Which amount and unit this row's density is said in, read by both the fact
/// sheet and the density entry: the row's serving when it is a volume, else its
/// default unit when that is a volume, else [kDensityReadingUnit].
/// `fromServing` says whether the first leg won; the fact sheet then moves the
/// `g/ml` into an aside.
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

/// What a stored density weighs in the unit this row says it in. Null on a row
/// with no density, or whose reading unit cannot carry it.
double? densityReadingWeight(Ingredient ingredient, {Measure? serving}) {
  final density = ingredient.densityGPerMl;
  if (density == null) return null;
  final read = densityReading(ingredient, serving: serving);
  final perUnit = volumeWeightFromDensity(read.unit, density);
  return perUnit == null ? null : perUnit * read.amount;
}

/// The stated piece weight as a sentence, `1 piece weighs 200 g`, or null on a
/// row that states none.
String? pieceWeightFact(Ingredient ingredient) {
  final weight = ingredient.pieceBasisAmount;
  if (weight == null) return null;
  final basis = ingredient.macrosBasis.baseUnit;
  return '1 piece weighs ${formatQuantityIn(weight, basis)} ${basis.label}'
      '${pieceWeightSourceSuffix(ingredient.pieceSource)}';
}

/// ` · borrowed from onion, medium` for a seeded weight; nothing for a typed
/// one. A curated seed number reads "estimate". Shared with the piece-weight
/// entry's headline.
String pieceWeightSourceSuffix(String? source) {
  if (source == null || source == 'manual') return '';
  if (source == 'seed:typical') return ' · estimate';
  return ' · $source';
}

/// The other names this row answers to, joined — empty when it has none.
String aliasesFact(Iterable<IngredientAlias> aliases) =>
    aliases.map((a) => a.text).join(' · ');

/// One measure in the measures editor's words: `onion, medium · 110 g`. The
/// provenance word is drawn beside it, not inside this string.
String measureFact(Measure measure) {
  final basis = measure.basis.baseUnit;
  return '${measure.label} · ${formatQuantityIn(measure.amount, basis)} '
      '${basis.label}';
}

// --- The price group's sentences ---------------------------------------------
//
// Shared by the group's Latest line, its Before rows and the price sheet's
// header.

/// What the cents bought, in the words it was bought in: `1 lb`, `bag (454 g)`,
/// or `454 g`. A count above one leads (`8 × block (16 oz)`). The basis weight
/// follows a measure's word in brackets unless the word already states a size
/// ([measureWordWithSize]), and stands alone on a line that kept no entered
/// pack.
String pricePackPhrase(UnitPrice price) {
  final basis = price.basis.baseUnit;
  // How many of that pack the line rang up, in front of everything else, so
  // `$23.92 for 8 × block (16 oz)` reads back to the figure beside it.
  final times = countTimes(price.count);
  final weight =
      '${formatQuantityIn(price.packBasisAmount, basis)} ${basis.label}';
  final label = price.packLabel;
  if (label != null && label.isNotEmpty) {
    // A measure count leads only when it is not one: `bag (454 g)`, `2 bag (908
    // g)`. A pack stated in a unit counts nothing.
    final count = price.packUnit == null ? price.packAmount : null;
    final head = count == null || count == 1
        ? label
        : '${formatAmount(count)} $label';
    return '$times${measureWordWithSize(head, price.packBasisAmount, basis)}';
  }
  final amount = price.packAmount;
  final unit = price.packUnit;
  if (amount == null || unit == null) return '$times$weight';
  return '$times${formatAmountIn(amount, unit)} ${unit.label}';
}

/// The latest price as one line: `77¢ / 100 g · $3.49 for bag (454 g) · TJ's ·
/// 13 Sep`. The per-100 figure leads; the rest restates the purchase it came
/// from.
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

/// One earlier price in two parts: what it came to and what was paid (`72¢ /
/// 100 g · $3.29 · bag (454 g)`), and where and when (`TJ's · 23 Aug`).
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

/// What the shut `On receipts` fold says: `3 names · 5 lines`.
String onReceiptsFact(List<ReceiptName> names) {
  final lines = names.fold(0, (sum, name) => sum + name.lineCount);
  return '${names.length} ${plural(names.length, 'name')} · '
      '$lines ${plural(lines, 'line')}';
}

/// One printed name's line: `2 lines · TJ's · 19 Sep`. The date is the newest
/// receipt's, which the row's tap opens. Only the newest store is named, with
/// `+2` for the rest; an unnamed store contributes nothing.
String receiptNameFact(ReceiptName name) => [
  '${name.lineCount} ${plural(name.lineCount, 'line')}',
  if (storeWordsFact(name.stores) case final where?) where,
  formatDayMonth(name.lastSeen),
].join(' · ');

/// The store clause of [receiptNameFact] — `TJ's`, or `TJ's +2` — and null
/// where no receipt carrying the name names a store at all.
String? storeWordsFact(List<String> stores) {
  if (stores.isEmpty) return null;
  final rest = stores.length - 1;
  return rest == 0 ? stores.first : '${stores.first} +$rest';
}

/// What the price sheet says about the price it is replacing: `latest 72¢ / 100
/// g · TJ's · Aug`. Null on an unpriced row. The month alone, as context.
String? latestPriceAside(PriceObservation? price) {
  if (price == null) return null;
  final head = switch (price.per100) {
    Ok(:final value) => formatPricePer100(value),
    Err() => formatMoney(price.paidCents),
  };
  return 'latest $head · ${price.store} · '
      '${formatMonthShort(price.purchasedAt)}';
}

/// The base price as one line: `$3.32 / 100 g · $1.99 for bunch (60 g) · TJ's
/// · set 13 Sep`, in [latestPriceFact]'s order. The store is left out where
/// it names none; `set` says the day is when it was typed, not a shop.
String basePriceFact(BasePrice price) {
  final head = switch (price.per100) {
    Ok(:final value) => '${formatPricePer100(value)} · ',
    Err() => '',
  };
  return [
    '$head${formatMoney(price.cents)} for ${pricePackPhrase(price)}',
    ?price.store,
    'set ${formatDayMonth(price.setAt)}',
  ].join(' · ');
}

/// What the price sheet says when opened on the stored base price: `editing
/// $1.99 · TJ's · set 13 Sep`.
String editedBasePriceAside(BasePrice price) => [
  'editing ${formatMoney(price.cents)}',
  ?price.store,
  'set ${formatDayMonth(price.setAt)}',
].join(' · ');

/// Why a price cannot be read from what has been typed: the sentence the
/// sheet's dock shows in place of the figure. Each names a way out; an
/// unfamiliar code reads as a plain sentence, never as the code.
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
