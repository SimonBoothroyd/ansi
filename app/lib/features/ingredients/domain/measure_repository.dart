/// Read/write access to an ingredient's named measures — PURE DART
/// (invariant 2).
///
/// Measures ("potato, large = 299 g", step 7.6) are per-household vocab rows,
/// synced like the ingredients they belong to. Pickers watch them so a
/// measure added on one device appears in the other's chip row live. Step 7.7
/// adds the write path: the in-app measure editor authors `manual`-sourced
/// rows and soft-deletes unwanted ones.
///
/// **Duplicate labels merge on read**: no unique index guards `(ingredient_id,
/// label)` — one would make an offline duplicate fail upload and drop the whole
/// crud transaction (the shopping-entry doctrine). Instead every device
/// converges on the same canonical row per label: the *oldest* live one
/// (`created_at`, then `id`). Newer duplicates are hidden, never deleted — a
/// referencing line item still resolves them by id.
library;

import 'package:meta/meta.dart';

import '../../../core/units/measure.dart';

abstract interface class MeasureRepository {
  /// The live measures of [ingredientId], ordered by `sort_order` (then
  /// creation) so the first is the ingredient's primary measure. Duplicate
  /// labels are merged deterministically (see the library doc).
  Stream<List<Measure>> watchMeasures(String ingredientId);

  /// The measures of MANY ingredients in one read, keyed by ingredient id —
  /// same ordering and duplicate-merge rules as [watchMeasures]. An id with
  /// no measures is absent from the map.
  ///
  /// The import review validates a whole recipe's lines at once and must not
  /// fan out to a stream per line: routing that through N autoDispose stream
  /// providers is what let a measure-word unit — "1 clove" of a garlic row that
  /// carries a `clove` measure — validate against an EMPTY measure list and get
  /// flagged "Pick a supported unit".
  Future<Map<String, List<Measure>>> measuresByIngredients(Set<String> ids);

  /// Authors a user measure of [ingredientId]: one [label] is [amount] of
  /// the ingredient's basis unit (g or ml — `macros_basis`, ADR-0008).
  /// Written with `source = 'manual'` after the ingredient's existing
  /// measures (`sort_order`), and returned for immediate selection.
  ///
  /// Throws [ArgumentError] for an empty or volume-unit-named [label]
  /// (density owns volume conversion) or non-positive/NaN [amount] — the
  /// rules hold at the repository, not just the sheet's form.
  Future<Measure> addMeasure({
    required String ingredientId,
    required String label,
    required double amount,
  });

  /// Renames one live measure in place, keeping its id — so every line
  /// already pointing at it keeps pointing at the same thing, which is the
  /// whole reason a rename is not a delete-and-re-add.
  ///
  /// Holds [addMeasure]'s lines on the label, plus two of its own:
  ///
  /// - **A live label may not collide.** Nothing in the schema stops it (the
  ///   unique index is gone, deliberately — an offline duplicate must not fail
  ///   upload), and a collision would simply *hide* the newer row behind the
  ///   merge-on-read rule. A rename is a deliberate act, so it is refused
  ///   where an offline duplicate is tolerated.
  /// - **A rename never crosses the reserved serving prefix**, in either
  ///   direction: the row's one serving is written and read through that
  ///   prefix, so renaming into it would mint a second serving and renaming
  ///   out of it would silently retire the row's stated serving.
  ///
  /// Throws [ArgumentError] for each of those, and for an id naming no live
  /// measure.
  Future<void> renameMeasure(String measureId, String label);

  /// Re-weighs one live measure: [amount] of the ingredient's basis unit for
  /// one of it. Same honesty line as [addMeasure] — a non-positive or NaN
  /// amount could never convert (invariant 3) — and the same id, so the lines
  /// that already say this measure follow the corrected weight.
  Future<void> setMeasureAmount(String measureId, double amount);

  /// Re-stamps `sort_order` so the measures of one ingredient read in the
  /// order [ids] gives, first to last.
  ///
  /// The order is not decoration. The first measure is the ingredient's
  /// **typical** one: it fronts the picker's measure chips, and it is what the
  /// shop's whole-unit hint rounds to for an item whose contributions name no
  /// measure of their own ("674 g ≈ 3 × potato, large → buy 3"). So a
  /// household that mostly buys large potatoes says so by dragging that row to
  /// the top, rather than by a flag that would have to be explained.
  ///
  /// Ids not belonging to the ingredient, or naming no live row, are ignored:
  /// the caller is a list that may have been re-read under it.
  Future<void> reorderMeasures(String ingredientId, List<String> ids);

  /// What still says this measure: how many live rows point at it, and which
  /// recipes they are in.
  ///
  /// The FKs carry no `on delete`, and the delete is a tombstone, so nothing
  /// stops a measure going out from under the lines that name it. What those
  /// lines then do is worse than an error: the macro engine drops them from
  /// the totals and the shop degrades them to a bare count, both silently.
  /// So a delete asks this first and is refused while the answer is not zero
  /// — the same shape a book takes when it still holds recipes.
  Future<MeasureUsage> countLinesUsing(String measureId);

  /// Soft-deletes one measure (tombstone, spec §3). A line item referencing
  /// it degrades to its honest stored count — never an invented amount.
  Future<void> softDeleteMeasure(String measureId);
}

/// What a measure is still used by — the answer [MeasureRepository
/// .countLinesUsing] gives.
///
/// [lines] counts every live row across all three tables that can name a
/// measure (a recipe's line, a shopping contribution, a planned ingredient
/// meal), because all three degrade if the row goes. [recipes] names only the
/// recipes, because those are the ones a person can go and fix.
@immutable
class MeasureUsage {
  const MeasureUsage({required this.lines, required this.recipes});

  static const none = MeasureUsage(lines: 0, recipes: []);

  final int lines;

  /// Every live recipe with a line saying this measure, by title.
  final List<({String id, String title})> recipes;

  bool get any => lines > 0;
}
