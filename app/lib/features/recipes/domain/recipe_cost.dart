/// Recipe cost summation. Pure Dart. See ADR-0017.
///
/// A line costs its amount in the ingredient's basis unit ([lineAmountInBasis])
/// times the price per unit of that basis that the row's cost reads
/// (`costPriceOf`: the newest receipt price, else the row's base price). The
/// walk mirrors `summarizeRecipeMacros`, with imprecise and optional lines
/// excluded through [effectiveLines]. An unpriced line is named and makes
/// [RecipeCostSummary.totalCents] null; [RecipeCostSummary.pricedCents] is then
/// a floor. Money and macros share no code
/// (`test/structure/cost_and_macros_stay_apart_test.dart`).
library;

import 'package:meta/meta.dart';

import '../../../core/result/result.dart';
import '../../../core/units/units.dart';
import '../../ingredients/domain/price.dart';
import 'component_math.dart';
import 'effective_lines.dart';
import 'line_basis.dart';
import 'recipe.dart';

/// One vocab ingredient's basis facts and the price its cost reads. A null
/// `price` means nobody has priced the row ([CostLineReason.noPrice]).
typedef IngredientPricing = ({IngredientBasis row, UnitPrice? price});

/// Why one line carries no cost. The first four are gaps
/// ([RecipeCostSummary.unpriced]); the last two are exclusions by rule
/// ([RecipeCostSummary.notCounted]).
enum CostLineReason {
  /// Nothing has been paid for this row and it has no base price — the price
  /// sheet is the fix.
  noPrice,

  /// The line's amount cannot reach the row's basis unit: no density, no piece
  /// weight, no amount, an unsynced measure, or a stub, unknown or retired
  /// ingredient.
  noPathToBasis,

  /// The price was recorded against a different basis than the row states now.
  /// Re-denominating would need an unstated density, so the line waits for a
  /// fresh price.
  priceOffBasis,

  /// A component line whose batch math does not resolve (no yield, a unit in no
  /// yield's family, a missing word, no amount, a cycle, a missing target).
  subRecipeUnresolved,

  /// A component line whose target has unpriced lines of its own.
  subRecipeUnpriced,

  /// `to taste`, `pinch`, `dash`, `handful` — unweighable, so costless by rule.
  imprecise,

  /// An optional line this reading leaves out, via [effectiveLines].
  optional,
}

/// One line with no cost, named. `unit` is the printed imprecise word
/// ("handful") for [CostLineReason.imprecise], null otherwise.
typedef CostLineNote = ({
  String? lineId,
  String name,
  CostLineReason reason,
  String? unit,
});

/// What one line costs, and the price behind it. [cents] is fractional because
/// it is derived; it is rounded once, where printed.
@immutable
class CostLine {
  const CostLine({required this.cents, this.price});

  /// What this line comes to at the recipe's STORED amount.
  final double cents;

  /// The price the figure was read from (pack, provenance, month). Null for
  /// a component line.
  final UnitPrice? price;

  @override
  bool operator ==(Object other) =>
      other is CostLine &&
      other.cents == cents &&
      other.price?.key == price?.key;

  @override
  int get hashCode => Object.hash(cents, price?.key);

  @override
  String toString() => 'CostLine($cents¢)';
}

/// The oldest priced line in a recipe, named — the panel's `OLDEST` row.
typedef OldestPrice = ({String name, UnitPrice price});

/// A recipe's cost. [totalCents] is set only when every counted line is priced,
/// at least one line counts and the serving count is positive; otherwise the
/// summary is [incomplete] and [unpriced] names the gaps.
@immutable
class RecipeCostSummary {
  const RecipeCostSummary({
    this.totalCents,
    this.perServingCents,
    this.pricedCents = 0,
    this.pricedPerServingCents,
    this.lineCosts = const {},
    this.unpriced = const [],
    this.notCounted = const [],
    this.newestPrice,
    this.oldest,
    this.noLines = false,
    this.nothingCountable = false,
  });

  /// What the recipe costs at its stored servings, or null — see [incomplete].
  final double? totalCents;

  /// [totalCents] divided by the serving count. Scale-invariant.
  final double? perServingCents;

  /// What the priced lines come to at the stored amounts; zero when none are. A
  /// floor, not a cost: a surface printing it must say so, and nothing asking
  /// what the recipe costs reads it.
  final double pricedCents;

  /// [pricedCents] over the serving count, or null when that count is not
  /// positive.
  final double? pricedPerServingCents;

  /// Each line's contribution by [LineItem.id], at the stored amounts. A line
  /// is either here or in [unpriced]/[notCounted], never here as a zero.
  final Map<String, CostLine> lineCosts;

  /// Every line the app cannot price, in line order. Non-empty means
  /// [incomplete].
  final List<CostLineNote> unpriced;

  /// Every line excluded by rule (imprecise or optional), in line order. It
  /// never makes the summary [incomplete]; see [nothingCountable].
  final List<CostLineNote> notCounted;

  /// The most recent priced line's date — the panel's `prices from` cell.
  final DateTime? newestPrice;

  /// The oldest priced line, set only when its month differs from
  /// [newestPrice]'s.
  final OldestPrice? oldest;

  /// The recipe has no line items yet.
  final bool noLines;

  /// Every line was excluded by rule, so nothing was costed.
  final bool nothingCountable;

  bool get incomplete => totalCents == null;

  /// Some counted lines are priced and some are not — the one state where
  /// [pricedCents] is worth printing.
  bool get partlyPriced =>
      incomplete && unpriced.isNotEmpty && lineCosts.isNotEmpty;

  @override
  bool operator ==(Object other) =>
      other is RecipeCostSummary &&
      other.totalCents == totalCents &&
      other.perServingCents == perServingCents &&
      other.pricedCents == pricedCents &&
      other.pricedPerServingCents == pricedPerServingCents &&
      _sameLines(other.lineCosts, lineCosts) &&
      _sameNotes(other.unpriced, unpriced) &&
      _sameNotes(other.notCounted, notCounted) &&
      other.newestPrice == newestPrice &&
      other.oldest?.name == oldest?.name &&
      other.oldest?.price.key == oldest?.price.key &&
      other.noLines == noLines &&
      other.nothingCountable == nothingCountable;

  static bool _sameNotes(List<CostLineNote> a, List<CostLineNote> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }

  static bool _sameLines(Map<String, CostLine> a, Map<String, CostLine> b) {
    if (a.length != b.length) return false;
    for (final entry in a.entries) {
      if (b[entry.key] != entry.value) return false;
    }
    return true;
  }

  @override
  int get hashCode => Object.hash(
    totalCents,
    perServingCents,
    pricedCents,
    pricedPerServingCents,
    Object.hashAllUnordered([
      for (final e in lineCosts.entries) Object.hash(e.key, e.value),
    ]),
    Object.hashAll(unpriced),
    Object.hashAll(notCounted),
    newestPrice,
    oldest?.price.key,
    noLines,
    nothingCountable,
  );

  @override
  String toString() => incomplete
      ? 'RecipeCostSummary(incomplete: '
            '${noLines
                ? 'no lines'
                : nothingCountable
                ? 'nothing countable'
                : '${unpriced.length} unpriced'})'
      : 'RecipeCostSummary($totalCents¢, $perServingCents¢/serving)';
}

/// Sums [lines] into a [RecipeCostSummary]. [pricingOf] resolves an ingredient
/// id to its basis facts and latest price; null (unknown row) reads as
/// [CostLineReason.noPathToBasis]. [subRecipeOf] resolves a component's target;
/// when null every component line is unresolved. A [servingsBase] at or below
/// zero yields an incomplete summary.
RecipeCostSummary summarizeRecipeCost({
  required double servingsBase,
  required Iterable<LineItem> lines,
  required IngredientPricing? Function(String ingredientId) pricingOf,
  SubRecipeNode? Function(String subRecipeId)? subRecipeOf,
}) => _summarize(
  servingsBase: servingsBase,
  lines: lines,
  pricingOf: pricingOf,
  subRecipeOf: subRecipeOf,
  visited: const <String>{},
).summary;

/// One priced line, with the name the panel would print for it.
typedef _Seen = ({String name, UnitPrice price});

/// The summary, plus every observation that went into it, including a
/// component's, so a parent's `prices from` sees through nested recipes.
typedef _Walk = ({RecipeCostSummary summary, List<_Seen> seen});

_Walk _summarize({
  required double servingsBase,
  required Iterable<LineItem> lines,
  required IngredientPricing? Function(String ingredientId) pricingOf,
  required SubRecipeNode? Function(String subRecipeId)? subRecipeOf,
  required Set<String> visited,
}) {
  var total = 0.0;
  var lineCount = 0;
  var excludedByRule = 0;
  final unpriced = <CostLineNote>[];
  final notCounted = <CostLineNote>[];
  final lineCosts = <String, CostLine>{};
  // Every observation behind the total; `prices from` and `OLDEST` read this
  // set.
  final seen = <_Seen>[];

  String nameOf(LineItem line) => line.subRecipe?.title ?? line.ingredientName;

  void note(
    List<CostLineNote> into,
    LineItem line,
    CostLineReason reason, {
    String? unit,
  }) => into.add((
    lineId: line.id,
    name: nameOf(line),
    reason: reason,
    unit: unit,
  ));

  // Asked first, so an optional line is named once, as optional, never also as
  // unpriced.
  final dropped = {for (final d in effectiveLines(lines).dropped) d.line};

  for (final line in lines) {
    lineCount++;
    if (dropped.contains(line)) {
      excludedByRule++;
      note(notCounted, line, CostLineReason.optional);
      continue;
    }
    final subRecipeId = line.subRecipeId;
    if (subRecipeId != null) {
      final walked = _componentCost(
        subRecipeId: subRecipeId,
        line: line,
        pricingOf: pricingOf,
        subRecipeOf: subRecipeOf,
        visited: visited,
      );
      switch (walked) {
        case _ComponentUnresolved():
          note(unpriced, line, CostLineReason.subRecipeUnresolved);
        case _ComponentUnpriced():
          note(unpriced, line, CostLineReason.subRecipeUnpriced);
        case _ComponentCost(:final cents, :final prices):
          total += cents;
          lineCosts[line.id] = CostLine(cents: cents);
          seen.addAll(prices);
      }
      continue;
    }
    // Imprecise is costless by rule, checked before anything can fail.
    if (line.measure == null && line.unit?.family == UnitFamily.imprecise) {
      excludedByRule++;
      note(notCounted, line, CostLineReason.imprecise, unit: line.unit?.label);
      continue;
    }
    final ingredientId = line.ingredientId;
    final pricing = ingredientId == null ? null : pricingOf(ingredientId);
    if (pricing == null) {
      note(unpriced, line, CostLineReason.noPathToBasis);
      continue;
    }
    final amount = lineAmountInBasis(line, pricing.row);
    if (amount == null) {
      note(unpriced, line, CostLineReason.noPathToBasis);
      continue;
    }
    final price = pricing.price;
    if (price == null) {
      note(unpriced, line, CostLineReason.noPrice);
      continue;
    }
    if (price.basis != pricing.row.basis) {
      note(unpriced, line, CostLineReason.priceOffBasis);
      continue;
    }
    // The price's own refusals (empty pack, nothing paid) pass through.
    final per100 = price.per100;
    if (per100 is! Ok<PricePer100>) {
      note(unpriced, line, CostLineReason.noPrice);
      continue;
    }
    final cents = per100.value.cents * amount / 100;
    total += cents;
    lineCosts[line.id] = CostLine(cents: cents, price: price);
    seen.add((name: nameOf(line), price: price));
  }

  final noLines = lineCount == 0;
  final nothingCountable = !noLines && excludedByRule == lineCount;
  final incomplete =
      noLines || nothingCountable || unpriced.isNotEmpty || !(servingsBase > 0);

  _Seen? newest;
  _Seen? oldest;
  for (final s in seen) {
    if (newest == null || s.price.asOf.isAfter(newest.price.asOf)) {
      newest = s;
    }
    if (oldest == null || s.price.asOf.isBefore(oldest.price.asOf)) {
      oldest = s;
    }
  }
  final monthsDiffer =
      newest != null &&
      oldest != null &&
      !_sameMonth(newest.price.asOf, oldest.price.asOf);

  return (
    seen: seen,
    summary: RecipeCostSummary(
      totalCents: incomplete ? null : total,
      perServingCents: incomplete ? null : total / servingsBase,
      // Stated whether or not the recipe's total is.
      pricedCents: total,
      pricedPerServingCents: servingsBase > 0 ? total / servingsBase : null,
      lineCosts: lineCosts,
      unpriced: List.unmodifiable(unpriced),
      notCounted: List.unmodifiable(notCounted),
      newestPrice: newest?.price.asOf,
      oldest: monthsDiffer ? oldest : null,
      noLines: noLines,
      nothingCountable: nothingCountable,
    ),
  );
}

bool _sameMonth(DateTime a, DateTime b) =>
    a.year == b.year && a.month == b.month;

/// What one component line contributes, or which reason it costs.
sealed class _ComponentResult {
  const _ComponentResult();
}

final class _ComponentCost extends _ComponentResult {
  const _ComponentCost(this.cents, this.prices);
  final double cents;

  /// The target's own priced lines, so the parent's `prices from` and `OLDEST`
  /// see through the component.
  final List<_Seen> prices;
}

/// The batch math didn't resolve.
final class _ComponentUnresolved extends _ComponentResult {
  const _ComponentUnresolved();
}

/// The share is known; what it is worth is not.
final class _ComponentUnpriced extends _ComponentResult {
  const _ComponentUnpriced();
}

/// The target's WHOLE-recipe cost × the batches this line asks for.
_ComponentResult _componentCost({
  required String subRecipeId,
  required LineItem line,
  required IngredientPricing? Function(String ingredientId) pricingOf,
  required SubRecipeNode? Function(String subRecipeId)? subRecipeOf,
  required Set<String> visited,
}) {
  // A cycle stops the walk here rather than recursing.
  if (visited.contains(subRecipeId)) return const _ComponentUnresolved();
  final node = subRecipeOf?.call(subRecipeId);
  if (node == null) return const _ComponentUnresolved();

  final amount = resolveComponentAmount(
    quantity: line.quantity,
    unit: line.unit,
    yields: node.yields,
    recipeMeasureId: line.recipeMeasureId,
    measures: node.measures,
  );
  if (amount is! ResolvedComponentAmount) return const _ComponentUnresolved();

  final walked = _summarize(
    servingsBase: node.servingsBase,
    lines: node.lines,
    pricingOf: pricingOf,
    subRecipeOf: subRecipeOf,
    visited: {...visited, subRecipeId},
  );
  final cost = walked.summary.totalCents;
  if (cost == null) return const _ComponentUnpriced();
  // Nested lines keep their own names: `OLDEST` names the line that carries the
  // price, not the component line.
  return _ComponentCost(cost * amount.batches, walked.seen);
}
