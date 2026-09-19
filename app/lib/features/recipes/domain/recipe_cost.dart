/// Recipe cost summation — PURE DART (invariant 2), and the macro summation's
/// twin. It feeds the recipe panel's Cost reading, the per-line figures under
/// it, the week's band and the shop's rows.
///
/// **A cost is a unit price, never an allocation** (ADR-0017). A line costs
/// the amount it asks for, in the ingredient's basis unit, times the latest
/// price the household paid per unit of that basis. Nothing is assigned from a
/// receipt to a meal, because that would need an inventory and ADR-0007
/// deliberately keeps none.
///
/// It is the SAME walk as `summarizeRecipeMacros`, line for line, and that is
/// the point — the two readings of the panel have to agree about which lines
/// they are reading:
///
/// - the grams come from [lineAmountInBasis], the one conversion both share,
///   so a line can never weigh one thing for its macros and another for its
///   cost;
/// - an **imprecise** line (`to taste`, `pinch`, `handful`) and an
///   **optional** line are excluded BY RULE, by exactly the macro rule and
///   through the same [effectiveLines] seam, and are NAMED in
///   [RecipeCostSummary.notCounted] — never in [RecipeCostSummary.unpriced],
///   which is a different claim about a different kind of
///   gap;
/// - a **sub-recipe component** contributes its target's whole-recipe cost ×
///   the batches it asks for, and only when both halves are honest;
/// - a recipe with no lines, or one whose every line is excluded by rule, has
///   no cost at all — `$0.00` there would be a fabrication (invariant 3).
///
/// What is new is the refusal, and it has one shape: a line the app cannot
/// price is **unpriced**, named, and takes the recipe's figure with it. A line
/// with no price yet, a line whose amount never reached the basis (a volume
/// line on a gram row with no density), a component that does not resolve —
/// all of them are a gap in the total, and a total that quietly skipped them
/// would understate what a week costs by exactly the things nobody has priced.
///
/// What the priced lines DO come to is still worth knowing, so it is reported
/// separately, as [RecipeCostSummary.pricedCents]. It is a **floor**, never a
/// cost: [RecipeCostSummary.totalCents] stays null while anything is unpriced,
/// so every reading that asks for the cost — the week, the shop, a parent
/// recipe's component share — is unchanged by it, and a surface that prints
/// the floor has to say in words that it is one.
///
/// **Money and macros never meet.** Nothing in this file knows what a calorie
/// is, nothing in `recipe_macros.dart` knows what a cent is, and
/// `test/structure/cost_and_macros_stay_apart_test.dart` holds that line. They
/// share the walk, not the figures.
///
/// Like the macro summation, [RecipeCostSummary.lineCosts] is at the recipe's
/// STORED amounts — a surface showing a scaled list multiplies by its own
/// factor, exactly as it scales the amount printed beside them — while
/// [RecipeCostSummary.perServingCents] is scale-invariant, because scaling
/// moves the lines and the servings together.
library;

import 'package:meta/meta.dart';

import '../../../core/result/result.dart';
import '../../../core/units/units.dart';
import '../../ingredients/domain/price.dart';
import 'component_math.dart';
import 'effective_lines.dart';
import 'line_basis.dart';
import 'recipe.dart';

/// What the cost summation needs to know about one vocab ingredient: the
/// dimension its amounts live in, and the latest price paid for it.
///
/// `price` is null for a row nobody has priced — which is an honest state, not
/// a zero — and the line it belongs to becomes [CostLineReason.noPrice].
typedef IngredientPricing = ({IngredientBasis row, PriceObservation? price});

/// Why one line carries no cost.
///
/// The first four are gaps that take the recipe's figure with them
/// ([RecipeCostSummary.unpriced]); the last two are exclusions BY RULE, shared
/// with the macro summation, and named apart
/// ([RecipeCostSummary.notCounted]).
enum CostLineReason {
  /// Nothing has ever been paid for this row — the price sheet is the fix.
  noPrice,

  /// The line's amount never reached the row's basis unit: a cross-basis line
  /// on a row with no density, a bare count on a row with no piece weight, a
  /// line with no amount at all, a measure this device has not synced, or an
  /// ingredient that is a stub, unknown or retired. The price exists (or does
  /// not); what is missing is the path from the line to it.
  noPathToBasis,

  /// The price was recorded against a different basis than the row states
  /// today — a per-100 g price on a row that has since become per-100 ml.
  /// Re-denominating it would need a density nobody stated for that pack, so
  /// the line waits for a fresh price rather than guessing.
  priceOffBasis,

  /// A component line whose batch math does not resolve (no yield, a unit in
  /// no yield's family, no amount, a cycle, a missing target).
  subRecipeUnresolved,

  /// A component line whose target has unpriced lines of its own: the share is
  /// knowable, what it is worth is not.
  subRecipeUnpriced,

  /// `to taste`, `pinch`, `dash`, `handful` — unweighable by nature, so
  /// costless by rule rather than by failure. Named in
  /// [RecipeCostSummary.notCounted].
  imprecise,

  /// The recipe marks the line optional and this reading leaves it out, by the
  /// [effectiveLines] seam the macro summation shares. Named in
  /// [RecipeCostSummary.notCounted].
  optional,
}

/// One line with no cost, named — the cost twin of a macro note. `unit` is the
/// line's own printed imprecise word ("handful"), carried for
/// [CostLineReason.imprecise] and null otherwise.
typedef CostLineNote = ({
  String? lineId,
  String name,
  CostLineReason reason,
  String? unit,
});

/// What one line costs, and the price that says so.
///
/// [cents] is a real number of cents rather than an integer because it is
/// derived, not paid: rounding it per line would put a rounding inside every
/// sum above it. It is rounded once, at the edge, where it is printed.
@immutable
class CostLine {
  const CostLine({required this.cents, this.price});

  /// What this line comes to at the recipe's STORED amount.
  final double cents;

  /// The observation the figure was read from — the pack, the store and the
  /// month, so a figure that looks wrong is traceable to the receipt line that
  /// made it. Null for a component line, whose cost is a recipe's rather than
  /// a pack's.
  final PriceObservation? price;

  @override
  bool operator ==(Object other) =>
      other is CostLine &&
      other.cents == cents &&
      other.price?.lineId == price?.lineId;

  @override
  int get hashCode => Object.hash(cents, price?.lineId);

  @override
  String toString() => 'CostLine($cents¢)';
}

/// The oldest priced line in a recipe, named — the panel's `OLDEST` row.
typedef OldestPrice = ({String name, PriceObservation price});

/// The honest cost of a recipe.
///
/// [totalCents] is set only when EVERY counted line carries a price (and there
/// is at least one counted line, and the serving count is positive);
/// otherwise the summary is [incomplete], the cells go, and [unpriced] names
/// what it is waiting on.
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

  /// [totalCents] divided by the recipe's serving count. Scale-invariant, for
  /// the reason the per-serving macros are.
  final double? perServingCents;

  /// What the lines that ARE priced come to, at the stored amounts — always a
  /// figure, and zero when nothing was priced.
  ///
  /// It is a **floor**, not a cost: it equals [totalCents] when the recipe is
  /// whole, and when it is not it is the part of an unknown figure that is
  /// known. Only a surface that prints it in those words may print it; nothing
  /// that asks this summary what the recipe *costs* reads it, which is why
  /// [totalCents] is null rather than partial and why a component whose target
  /// is [incomplete] stays unpriced in its parent rather than contributing a
  /// floor.
  final double pricedCents;

  /// [pricedCents] over the recipe's serving count, or null when that count is
  /// not positive — the floor's per-serving twin, and scale-invariant for the
  /// same reason [perServingCents] is.
  final double? pricedPerServingCents;

  /// What each line contributed, by [LineItem.id], at the STORED amounts. A
  /// line is in exactly one of this and [unpriced]/[notCounted] — never here
  /// as a zero.
  final Map<String, CostLine> lineCosts;

  /// Every line the app cannot price, named, in line order. Non-empty means
  /// [incomplete]: an unpriced line takes the recipe's figure with it.
  final List<CostLineNote> unpriced;

  /// Every line excluded BY RULE — imprecise, or optional — named in line
  /// order. It never makes the summary [incomplete]; the one guard is
  /// [nothingCountable].
  final List<CostLineNote> notCounted;

  /// The most recent priced line's date — the panel's `prices from` cell, and
  /// the answer to "how current is this figure".
  final DateTime? newestPrice;

  /// The oldest priced line, set ONLY when its month differs from
  /// [newestPrice]'s: a July jar under an otherwise-September recipe is named
  /// rather than averaged away. Null when every price is of one month.
  final OldestPrice? oldest;

  /// The recipe has no line items yet.
  final bool noLines;

  /// Every line was excluded by rule, so nothing was costed — the twin of the
  /// macro summation's `nothingWeighable` guard.
  final bool nothingCountable;

  bool get incomplete => totalCents == null;

  /// Some counted lines are priced and some are not — the one state in which
  /// [pricedCents] says something the cells do not.
  ///
  /// False when nothing is priced, where the floor would be a zero standing in
  /// for an absence, and false when everything is, where [totalCents] states
  /// the figure exactly.
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
      other.oldest?.price.lineId == oldest?.price.lineId &&
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
    oldest?.price.lineId,
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

/// Sums [lines] into a [RecipeCostSummary]. [pricingOf] resolves a line's
/// ingredient id to its basis facts and latest price, or null when the row is
/// unknown locally — which reads as [CostLineReason.noPathToBasis], because an
/// unknown row states no basis to convert into.
///
/// [subRecipeOf] resolves a component line's target; leaving it null means
/// components cannot be walked and every component line is unresolved.
///
/// [servingsBase] at or below zero yields an incomplete summary rather than an
/// Infinity per-serving figure.
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
typedef _Seen = ({String name, PriceObservation price});

/// The walk's whole answer: the summary, and every observation that went into
/// it — including those a component contributed, which is how a parent's
/// `prices from` cell sees through a nested recipe rather than stopping at it.
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
  // Every observation that went into the total, so the panel's `prices from`
  // cell and its `OLDEST` row are read off the same set the figure is.
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

  // The same seam, asked first, for the same reason the macro walk asks it
  // first: an optional line is named ONCE, as optional, and never also as
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
    // Unweighable by nature, so costless by rule — asked before anything can
    // fail, exactly as the macro walk asks it.
    if (line.measure == null && line.unit.family == UnitFamily.imprecise) {
      excludedByRule++;
      note(notCounted, line, CostLineReason.imprecise, unit: line.unit.label);
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
    // The derivation's own refusals (a pack of nothing, nothing paid) are the
    // price fact's, not a second opinion about them.
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
    if (newest == null ||
        s.price.purchasedAt.isAfter(newest.price.purchasedAt)) {
      newest = s;
    }
    if (oldest == null ||
        s.price.purchasedAt.isBefore(oldest.price.purchasedAt)) {
      oldest = s;
    }
  }
  final monthsDiffer =
      newest != null &&
      oldest != null &&
      !_sameMonth(newest.price.purchasedAt, oldest.price.purchasedAt);

  return (
    seen: seen,
    summary: RecipeCostSummary(
      totalCents: incomplete ? null : total,
      perServingCents: incomplete ? null : total / servingsBase,
      // The same sum, stated whether or not it is the recipe's: what the
      // priced lines came to is a fact even when the recipe's cost is not.
      pricedCents: total,
      pricedPerServingCents: servingsBase > 0 ? total / servingsBase : null,
      lineCosts: lineCosts,
      unpriced: List.unmodifiable(unpriced),
      notCounted: List.unmodifiable(notCounted),
      newestPrice: newest?.price.purchasedAt,
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

  /// The target's own priced lines, so the parent's `prices from` cell and
  /// `OLDEST` row see through a component rather than stopping at it.
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
  // The nested lines' own names travel with their prices: the `OLDEST` row is
  // about the PRICE, and the thing that carries a July price is the line
  // inside the component, not the component line that asked for it.
  return _ComponentCost(cost * amount.batches, walked.seen);
}
