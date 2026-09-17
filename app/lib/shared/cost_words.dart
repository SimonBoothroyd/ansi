/// The ONE vocabulary for a cost — PURE DART, the money twin of
/// `incomplete_macros.dart`.
///
/// Five surfaces print a cost: the recipe panel's Cost reading, the figures
/// under each line, the week's band, the shop's sync line and the shop's rows.
/// They have to say the same things in the same words, so they say them from
/// here.
///
/// Two spellings, and they mean different things. **A figure read off one
/// price is printed plain** — `$13.16 · $1.10 / 100 g · TJ's, Sep` — because
/// the chain behind it is right there and a reader can follow it to the
/// receipt line that made it. **A figure summed over many prices wears `≈`**
/// — `≈ $71 to cook`, `≈ $2.42` — because a price is the latest one seen and
/// not a quote, and the sum of a week's worth of them is an estimate of what
/// the trip will come to, never a bill. The panel's cells wear neither: its
/// third cell says `prices from Sep` outright, which is the same caveat said
/// in words rather than in a glyph.
library;

import '../core/money.dart';
import '../core/result/result.dart';
import '../core/words.dart';
import '../features/ingredients/domain/price.dart';
import '../features/recipes/domain/recipe_cost.dart';

/// `≈ $2.42` — an estimate summed over several prices. See the library note.
String approxMoney(double cents) => '≈ ${formatMoneyRounded(cents)}';

/// What ONE line carries when it has no cost, in the words its reason implies
/// — the per-line half of the refusal, and the same shape
/// `incompleteLineNote` gives a macro reason.
String costLineNote(CostLineReason reason) => switch (reason) {
  CostLineReason.noPrice => 'no price yet',
  // Not "no density": the same line may be missing a piece weight or an
  // amount, and the cost panel is not the place that teaches the ingredient
  // form — the macro reading beside it already names the exact fact.
  CostLineReason.noPathToBasis => 'no way to price this amount',
  CostLineReason.priceOffBasis => 'priced in another unit',
  CostLineReason.subRecipeUnresolved => 'sub-recipe has no yield',
  CostLineReason.subRecipeUnpriced => 'sub-recipe unpriced',
  CostLineReason.imprecise || CostLineReason.optional => 'not counted',
};

/// `$1.29 a can`, `$3.99 a jar`, `$1.10 / 100 g` — the unit price a line's
/// figure was read from.
///
/// A pack the household NAMED prints as that pack: you buy a can, and `$1.29
/// a can` is the figure a person can check against a shelf. A pack typed as a
/// plain amount has no word to print, so it reads per 100 of the basis, which
/// is the figure the ingredient page shows.
String unitPriceWord(PriceObservation price) {
  final label = price.packLabel;
  if (label != null) return '${formatMoney(price.paidCents)} a $label';
  return switch (price.per100) {
    Ok(:final value) => formatPricePer100(value),
    // Unreachable from an observation (it is built only from a positive pack
    // and a positive payment), and a refusal is never printed as a number.
    Err() => 'no price yet',
  };
}

/// `TJ's, Sep` — where and when the price was seen.
String priceProvenance(PriceObservation price) =>
    '${price.store}, ${formatMonthShort(price.purchasedAt)}';

/// `$13.16 · $1.10 / 100 g · TJ's, Sep` — a line's whole chain: what it comes
/// to at the amount shown, the unit price behind it, and where that price came
/// from.
///
/// [factor] is the page's servings scaler, the same multiplication the amount
/// beside it went through — the stored figure is never re-derived here.
///
/// A component line has no pack behind it, so it prints its figure alone: what
/// it costs is a recipe's cost, and the chain continues on that recipe's own
/// page.
String lineCostText(CostLine line, {double factor = 1}) {
  final cents = formatMoneyRounded(line.cents * factor);
  final price = line.price;
  if (price == null) return cents;
  return '$cents · ${unitPriceWord(price)} · ${priceProvenance(price)}';
}

/// `Chopped tomatoes · no price yet` — the panel's `UNPRICED` row.
///
/// Null when nothing is unpriced, so a caller draws no row rather than a label
/// with nothing after it.
String? unpricedNames(RecipeCostSummary summary) {
  final names = [
    for (final n in summary.unpriced) '${n.name} · ${costLineNote(n.reason)}',
  ];
  return names.isEmpty ? null : names.join(', ');
}

/// `Smoked paprika · Whole Foods, Jul` — the panel's `OLDEST` row, drawn only
/// when the oldest price's month differs from the newest's.
String? oldestPriceLine(RecipeCostSummary summary) {
  final oldest = summary.oldest;
  return oldest == null
      ? null
      : '${oldest.name} · ${priceProvenance(oldest.price)}';
}

/// `Parsley · handful, Kosher Salt · to taste` — the imprecise lines under a
/// cost total, in exactly the grammar the macro reading prints them in.
String? impreciseCostNames(RecipeCostSummary summary) {
  final names = [
    for (final n in summary.notCounted)
      if (n.reason == CostLineReason.imprecise)
        '${n.name} · ${n.unit ?? 'imprecise'}',
  ];
  return names.isEmpty ? null : names.join(', ');
}

/// `Lime, Coriander` — the optional lines under a cost total.
String? optionalCostNames(RecipeCostSummary summary) {
  final names = [
    for (final n in summary.notCounted)
      if (n.reason == CostLineReason.optional) n.name,
  ];
  return names.isEmpty ? null : names.join(', ');
}

/// Why a cost summary has no figure, in one line — the cost twin of
/// `incompleteNote`, and the words the panel prints where its cells would be.
String costRefusal(RecipeCostSummary summary) {
  if (summary.noLines) return 'no ingredients yet';
  if (summary.nothingCountable) return 'nothing to price yet';
  final n = summary.unpriced.length;
  if (n > 0) return '$n ${plural(n, 'line')} unpriced';
  return 'servings not set';
}

/// `≈ $71 to cook · 3 lines unpriced` — the week band's cost line.
///
/// [cents] is what the priced meals come to; [unpriced] is how many distinct
/// lines kept the rest of the week out of that figure. Null when there is
/// neither — a week that plans nothing says nothing here.
String? weekCostLine({double? cents, int unpriced = 0}) {
  final parts = [
    if (cents != null) '${approxMoney(cents)} to cook',
    if (unpriced > 0) '$unpriced ${plural(unpriced, 'line')} unpriced',
  ];
  return parts.isEmpty ? null : parts.join(' · ');
}

/// `≈ $58 still to buy` — the shop's trip estimate, on the sync line.
///
/// It counts the UNTICKED rows only: what is in the basket has been picked up,
/// and the question the line answers is what is left. Null when nothing on the
/// list can be priced, because `≈ $0` would read as a free trip rather than as
/// an unpriced one.
String? tripEstimate(double? cents) =>
    cents == null ? null : '${approxMoney(cents)} still to buy';
