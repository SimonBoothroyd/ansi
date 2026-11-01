/// What last week's shop left behind, and which recipes would use the most of
/// it. Pure Dart.
///
/// **Spare food** is per ingredient, in the row's basis unit (g or ml): what
/// was in the house for the week less what its cooked meals used —
/// `need − toBuy + bought − usedCooked`. `need − toBuy` is what was already
/// at home; `bought − toBuy` is what the pack or a whole count added beyond
/// the need (4 onions for 3½, a 500 g bag for 200 g); and a batch nobody
/// ticked was never cooked, so its demand is in `need` but not in
/// `usedCooked`. Only fresh food counts ([kFreshCategories]); anything that
/// cannot reach the basis unit is left out, never guessed (invariant 3).
///
/// **A recipe scores** by what the amounts it would use cost: for each spare
/// ingredient, the smaller of its amount and what is spare, times the row's
/// price per basis unit. Not the pack price paid, so a bulk jar adds what a
/// spoonful costs, and cheap long-keepers fall away on their own. The best
/// three are offered, each scoring at least half the best ([rankUseUp]).
library;

import 'package:meta/meta.dart';

import '../../../core/units/units.dart';

/// The categories whose food is offered back: the ones that go off.
const kFreshCategories = {'produce', 'dairy', 'proteins', 'protein'};

/// Whether [category] is fresh food, by the household's own category word.
bool isFresh(String? category) =>
    kFreshCategories.contains(category?.trim().toLowerCase());

/// One ingredient's week, in its basis unit: the inputs [spareOf] reads.
typedef SpareInput = ({
  String ingredientId,
  String name,
  String? category,

  /// The row's basis unit, g or ml, every amount here is in.
  Unit unit,

  /// What last week's meals asked for, all of them.
  double need,

  /// What the list left to buy once what was at home came off.
  double toBuy,

  /// What was bought: the receipt's packs, else the shop's own rounding.
  double bought,

  /// What the meals that were cooked (and the bare items) used.
  double usedCooked,

  /// What one basis unit costs, in cents, or null when nothing prices it.
  double? centsPerUnit,
});

/// One fresh ingredient with food to spare.
@immutable
class SpareFood {
  const SpareFood({
    required this.ingredientId,
    required this.name,
    required this.unit,
    required this.amount,
    required this.bought,
    required this.used,
    this.centsPerUnit,
  });

  final String ingredientId;
  final String name;

  /// The row's basis unit, g or ml, [amount], [bought] and [used] are in.
  final Unit unit;

  /// What is spare, in the row's basis unit.
  final double amount;

  /// What was in the house for the week, and what its cooked meals used.
  final double bought;
  final double used;

  final double? centsPerUnit;

  /// What the spare is worth at the row's price, or 0 when unpriced.
  double get cents => amount * (centsPerUnit ?? 0);

  @override
  bool operator ==(Object other) =>
      other is SpareFood &&
      other.ingredientId == ingredientId &&
      other.name == name &&
      other.unit == unit &&
      other.amount == amount &&
      other.bought == bought &&
      other.used == used &&
      other.centsPerUnit == centsPerUnit;

  @override
  int get hashCode =>
      Object.hash(ingredientId, name, amount, bought, used, centsPerUnit);

  @override
  String toString() => 'SpareFood($name, $amount spare)';
}

/// The fresh food [rows] leave spare, most valuable first. Less than a gram
/// (or millilitre) is nothing.
List<SpareFood> spareOf(Iterable<SpareInput> rows) {
  final spare = <SpareFood>[];
  for (final r in rows) {
    if (!isFresh(r.category)) continue;
    final inHouse = r.need - r.toBuy + r.bought;
    final left = inHouse - r.usedCooked;
    if (left < 1) continue;
    spare.add(
      SpareFood(
        ingredientId: r.ingredientId,
        name: r.name,
        unit: r.unit,
        amount: left,
        bought: inHouse,
        used: r.usedCooked,
        centsPerUnit: r.centsPerUnit,
      ),
    );
  }
  return spare..sort((a, b) {
    final c = b.cents.compareTo(a.cents);
    return c != 0 ? c : b.amount.compareTo(a.amount);
  });
}

/// A recipe as the ranking reads it: what one batch of it uses of each
/// ingredient, in the basis unit, and how many it serves.
typedef RecipeUse = ({
  String recipeId,
  String title,
  double servingsBase,
  Map<String, double> perBatch,
});

/// One spare ingredient a suggestion uses, and how much of it.
typedef SpareUse = ({
  String ingredientId,
  String name,
  double amount,
  Unit unit,
});

/// A recipe worth cooking to use up [uses], scored by what they cost.
@immutable
class UseUpSuggestion {
  const UseUpSuggestion({
    required this.recipeId,
    required this.title,
    required this.score,
    required this.uses,
  });

  final String recipeId;
  final String title;

  /// Cents of spare food the recipe would use.
  final double score;

  /// The spare food it uses, most valuable first.
  final List<SpareUse> uses;

  @override
  String toString() => 'UseUpSuggestion($title, $score)';
}

/// Every recipe in [recipes] that uses any of [spare], scored and ordered,
/// best first, for a meal of [portions]. Unpriced food is named but scores
/// nothing.
List<UseUpSuggestion> scoreUseUp({
  required Iterable<RecipeUse> recipes,
  required List<SpareFood> spare,
  required double portions,
}) {
  final byId = {for (final s in spare) s.ingredientId: s};
  final scored = <UseUpSuggestion>[];
  for (final recipe in recipes) {
    if (recipe.servingsBase <= 0) continue;
    final scale = portions / recipe.servingsBase;
    final uses = <(SpareUse, double)>[];
    for (final MapEntry(key: id, value: perBatch) in recipe.perBatch.entries) {
      final s = byId[id];
      if (s == null || perBatch <= 0) continue;
      final amount = perBatch * scale < s.amount ? perBatch * scale : s.amount;
      uses.add((
        (ingredientId: id, name: s.name, amount: amount, unit: s.unit),
        amount * (s.centsPerUnit ?? 0),
      ));
    }
    if (uses.isEmpty) continue;
    uses.sort((a, b) => b.$2.compareTo(a.$2));
    scored.add(
      UseUpSuggestion(
        recipeId: recipe.recipeId,
        title: recipe.title,
        score: uses.fold(0, (sum, u) => sum + u.$2),
        uses: [for (final (use, _) in uses) use],
      ),
    );
  }
  return scored..sort((a, b) {
    final c = b.score.compareTo(a.score);
    return c != 0 ? c : a.title.compareTo(b.title);
  });
}

/// The suggestions to offer from [scored] (best first, [scoreUseUp]): at most
/// [count], each scoring something and at least half the best.
List<UseUpSuggestion> rankUseUp(List<UseUpSuggestion> scored, {int count = 3}) {
  if (scored.isEmpty || scored.first.score <= 0) return const [];
  final floor = scored.first.score / 2;
  return [
    for (final s in scored.take(count))
      if (s.score >= floor) s,
  ];
}
