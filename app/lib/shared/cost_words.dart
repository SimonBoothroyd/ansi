/// The one vocabulary for a cost. Pure Dart; the money twin of
/// `incomplete_macros.dart`.
///
/// A figure read off one price prints plain. A figure summed over many
/// prices wears `≈`. A sum with a known gap prints `at least …` and never
/// `≈`: the arithmetic is exact, the gap is what is unknown.
library;

import '../core/money.dart';
import '../core/result/result.dart';
import '../core/words.dart';
import '../features/ingredients/domain/cost_price.dart';
import '../features/ingredients/domain/price.dart';
import '../features/recipes/domain/recipe_cost.dart';
import '../features/shopping/domain/shopping_cost.dart';

/// `≈ $71`: a whole list's estimate, to the dollar ([formatMoneyWhole]).
String approxMoneyWhole(double cents) => '≈ ${formatMoneyWhole(cents)}';

/// What one line prints when it has no cost.
String costLineNote(CostLineReason reason) => switch (reason) {
  CostLineReason.noPrice => 'no price yet',
  // The macro reading's words for the same fix (`incompleteLineNote`).
  CostLineReason.unknownIngredient => 'not in your foods yet',
  CostLineReason.removedIngredient => 'ingredient removed · pick again',
  CostLineReason.noAmount => 'no amount',
  CostLineReason.needsWeight => 'needs a piece weight',
  CostLineReason.needsDensity => 'needs a density',
  CostLineReason.priceOffBasis => 'priced in another unit',
  CostLineReason.subRecipeUnresolved => 'sub-recipe has no yield',
  CostLineReason.subRecipeUnpriced => 'sub-recipe unpriced',
  CostLineReason.imprecise || CostLineReason.optional => 'not counted',
};

/// `$1.29 a can`, `$1.10 / 100 g`: the unit price behind a line's figure.
///
/// A named pack prints as that pack; a pack typed as a plain amount reads
/// per 100 of the basis.
String unitPriceWord(UnitPrice price) {
  final label = price.packLabel;
  if (label != null) return '${formatMoney(price.paidCents)} a $label';
  return switch (price.per100) {
    Ok(:final value) => formatPricePer100(value),
    // Unreachable: a price is built only with a positive pack and payment.
    Err() => 'no price yet',
  };
}

/// `TJ's, Sep`: where and when the price was paid. A base price names its
/// store the same way, and `base price, Sep` where it names none.
String priceProvenance(UnitPrice price) => switch (price) {
  PriceObservation(:final store, :final purchasedAt) =>
    '$store, ${formatMonthShort(purchasedAt)}',
  BasePrice(:final store, :final setAt) =>
    '${store ?? 'base price'}, ${formatMonthShort(setAt)}',
};

/// `$13.16 · $1.10 / 100 g · TJ's, Sep`: a line's figure at the amount
/// shown, its unit price and its provenance.
///
/// [factor] is the page's servings scaler. A component line has no pack, so
/// it prints its figure alone.
String lineCostText(CostLine line, {double factor = 1}) {
  final cents = formatMoneyRounded(line.cents * factor);
  final price = line.price;
  if (price == null) return cents;
  return '$cents · ${unitPriceWord(price)} · ${priceProvenance(price)}';
}

/// `Chopped tomatoes, Cucumber · needs a piece weight`: the panel's
/// `UNPRICED` row. Null when nothing is unpriced.
///
/// The label already says a line has no price, so a plain
/// [CostLineReason.noPrice] prints the name alone; any other reason says
/// what the fix is. A name twice for the same reason is one fix and prints
/// once.
String? unpricedNames(RecipeCostSummary summary) {
  final names = <String>{
    for (final n in summary.unpriced)
      n.reason == CostLineReason.noPrice
          ? n.name
          : '${n.name} · ${costLineNote(n.reason)}',
  };
  return names.isEmpty ? null : names.join(', ');
}

/// `at least $1.65 a serving · at least $6.60 the recipe`: what a partly
/// priced recipe's priced lines come to.
///
/// Null unless [RecipeCostSummary.partlyPriced]. Each figure carries its own
/// `at least`, so neither reads as the actual cost.
String? costFloor(RecipeCostSummary summary) {
  if (!summary.partlyPriced) return null;
  final perServing = summary.pricedPerServingCents;
  final recipe =
      'at least ${formatMoneyRounded(summary.pricedCents)} the recipe';
  if (perServing == null) return recipe;
  return 'at least ${formatMoneyRounded(perServing)} a serving · $recipe';
}

/// `Smoked paprika · Whole Foods, Jul`: the panel's `OLDEST` row, drawn only
/// when the oldest price's month differs from the newest's.
String? oldestPriceLine(RecipeCostSummary summary) {
  final oldest = summary.oldest;
  return oldest == null
      ? null
      : '${oldest.name} · ${priceProvenance(oldest.price)}';
}

/// `Parsley · handful, Kosher Salt · to taste`: the imprecise lines a cost
/// total left out, in the macro reading's grammar. Ask reads it; the panel
/// names none.
String? impreciseCostNames(RecipeCostSummary summary) {
  final names = [
    for (final n in summary.notCounted)
      if (n.reason == CostLineReason.imprecise)
        '${n.name} · ${n.unit ?? 'imprecise'}',
  ];
  return names.isEmpty ? null : names.join(', ');
}

/// `Lime, Coriander`: the optional lines under a cost total.
String? optionalCostNames(RecipeCostSummary summary) {
  final names = [
    for (final n in summary.notCounted)
      if (n.reason == CostLineReason.optional) n.name,
  ];
  return names.isEmpty ? null : names.join(', ');
}

/// Why a cost summary has no figure, in one line.
String costRefusal(RecipeCostSummary summary) {
  if (summary.noLines) return 'no ingredients yet';
  if (summary.nothingCountable) return 'nothing to price yet';
  final n = summary.unpriced.length;
  if (n > 0) return '$n ${plural(n, 'line')} unpriced';
  return 'servings not set';
}

/// `at least $71`: a summed figure with a known gap, to the dollar. Never
/// combined with `≈`.
String atLeastMoneyWhole(double cents) => 'at least ${formatMoneyWhole(cents)}';

/// The week band's cost line: `≈ $71 to cook`, or `at least $71 to cook ·
/// 3 lines unpriced` when a meal was left out.
///
/// [cents] is what the priced meals come to; [unpriced] counts the distinct
/// lines that kept a meal out. A meal with one unpriced line drops out whole
/// (`sumPlannedCost`). Null when there is neither.
String? weekCostLine({double? cents, int unpriced = 0}) {
  final figure = cents == null
      ? null
      : unpriced > 0
      ? atLeastMoneyWhole(cents)
      : approxMoneyWhole(cents);
  final parts = [
    if (figure != null) '$figure to cook',
    if (unpriced > 0) '$unpriced ${plural(unpriced, 'line')} unpriced',
  ];
  return parts.isEmpty ? null : parts.join(' · ');
}

/// The shop's trip estimate: `≈ $58 at the cheapest`, or `at least $58 at
/// the cheapest · 2 rows unpriced`.
///
/// Sums the figures the rows print, each at the Shop's price (`shopPriceOf`).
/// The words stand when some rows fell back to an older price, because each
/// row says which price it read ([shopRowCost]). Counts unticked rows only.
/// Null when nothing on the list can be priced, because `≈ $0` would read as a
/// free trip.
String? tripEstimate(TripCost trip) {
  final cents = trip.cents;
  if (cents == null) return null;
  final unpriced = trip.unpriced;
  if (unpriced == 0) return '${approxMoneyWhole(cents)} at the cheapest';
  return '${atLeastMoneyWhole(cents)} at the cheapest · $unpriced '
      '${plural(unpriced, 'row')} unpriced';
}

/// A Shop row's figure, plain and to the cent because it is read off one
/// price, with where that price was seen:
///
/// - the cheapest in the window names its store: `$1.80 at Aldi`;
/// - an older receipt adds its month, because it is not the window's:
///   `$2.42 at TJ's, Jun`;
/// - a base price names its store and month, `$2.42 at Aldi, Sep`, or says
///   what it is where it names none: `$2.42 · base price, Sep`.
///
/// A receipt that kept no store word names none; no store is made up.
String shopRowCost(double cents, ShopPrice shop) {
  final money = formatMoneyRounded(cents);
  final price = shop.price;
  final month = formatMonthShort(price.asOf);
  String at(String store) =>
      store.trim().isEmpty ? money : '$money at ${store.trim()}';
  return switch (price) {
    PriceObservation(:final store) =>
      shop.choice == ShopPriceChoice.cheapestSeen
          ? at(store)
          : '${at(store)}, $month',
    BasePrice(:final store) =>
      store == null ? '$money · base price, $month' : '${at(store)}, $month',
  };
}
