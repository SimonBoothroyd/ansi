/// Inline display grouping for the recipe page — PURE DART (invariant 2).
///
/// The recipe page reads `amount · ingredient · notes` on one line per
/// ingredient identity (v3 LOCKED design). When several line items in a group
/// resolve to the SAME ingredient — the reconcile-time "used N ways" identity —
/// the page folds them into ONE [LineUses] row: the ingredient is named once,
/// and each use keeps its own amount and note. Amounts and notes are joined in
/// parallel ("2 cloves + 1 clove" · "finely chopped + sliced"), **never
/// summed** (invariant 3 — a count of cloves is not a mass to add up; the two
/// uses are two distinct call-outs in the method).
///
/// Grouping is by [LineItem.ingredientId] and scoped to a single
/// [IngredientGroup]: two mentions of garlic under "for the sauce" fold; garlic
/// in a separate "to serve" group stays its own row. First-occurrence order is
/// preserved, so the folded row sits where the ingredient first appears.
library;

import 'recipe.dart';

/// One inline recipe-page row: an ingredient identity and its ordered [uses].
///
/// A single-use ingredient has a one-element [uses]; a multi-use identity holds
/// each sibling line in source order. The presentation layer renders the amount
/// column by joining each use's amount with " + " and the note modifier by
/// joining the non-empty notes — an empty note drops its slot rather than
/// leaving a dangling "+".
class LineUses {
  const LineUses({required this.ingredientId, required this.uses})
    : assert(uses.length > 0, 'a display row needs at least one use');

  final String ingredientId;

  /// The sibling line items, in source order. The first carries the display
  /// name ([ingredientName]); every sibling shares the same [ingredientId].
  final List<LineItem> uses;

  /// The ingredient's display name — taken from the first use.
  String get ingredientName => uses.first.ingredientName;

  /// Whether this identity was mentioned more than once in the group.
  bool get isMultiUse => uses.length > 1;

  /// The non-empty notes of each use, in order — parallel to the amounts, with
  /// a missing note omitted (never merged, never summed).
  List<String> get notes => [
    for (final u in uses)
      if (u.note != null && u.note!.trim().isNotEmpty) u.note!.trim(),
  ];
}

/// Folds [items] into inline display rows, one per ingredient identity, in
/// first-occurrence order. Items with the same [LineItem.ingredientId] coalesce
/// into one [LineUses]; every other item is its own single-use row.
List<LineUses> groupLineUses(List<LineItem> items) {
  final order = <String>[];
  final byId = <String, List<LineItem>>{};
  for (final item in items) {
    byId
        .putIfAbsent(item.ingredientId, () {
          order.add(item.ingredientId);
          return <LineItem>[];
        })
        .add(item);
  }
  return [for (final id in order) LineUses(ingredientId: id, uses: byId[id]!)];
}
