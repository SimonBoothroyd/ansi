/// Read/write access to an ingredient's named measures ("potato, large = 299
/// g"). Pure Dart.
///
/// Measures are per-household vocab rows, synced and watched like ingredients.
///
/// Duplicate labels merge on read. No unique index guards `(ingredient_id,
/// label)`, because an offline duplicate would fail upload and drop the whole
/// crud transaction. Every device converges on the oldest live row per label
/// (`created_at`, then `id`); newer duplicates are hidden, never deleted, so a
/// line referencing one still resolves.
library;

import 'package:meta/meta.dart';

import '../../../core/units/measure.dart';

abstract interface class MeasureRepository {
  /// The live measures of [ingredientId], ordered by `sort_order` then
  /// creation, so the first is the primary measure. Duplicate labels are merged
  /// (see the library doc).
  Stream<List<Measure>> watchMeasures(String ingredientId);

  /// The measures of many ingredients in one read, keyed by ingredient id, with
  /// [watchMeasures]'s ordering and merge rules. An id with no measures is
  /// absent. The import review uses this instead of a stream per line:
  /// unlistened autoDispose stream providers completed empty and flagged valid
  /// measure units.
  Future<Map<String, List<Measure>>> measuresByIngredients(Set<String> ids);

  /// Authors a user measure of [ingredientId]: one [label] is [amount] of the
  /// ingredient's basis unit (g or ml, ADR-0008). Written with `source =
  /// 'manual'` after the existing measures, and returned for immediate
  /// selection.
  ///
  /// Throws [ArgumentError] for an empty or volume-unit-named [label] (density
  /// owns volume conversion) or a non-positive or NaN [amount].
  Future<Measure> addMeasure({
    required String ingredientId,
    required String label,
    required double amount,
  });

  /// Renames one live measure in place, keeping its id so lines pointing at it
  /// follow.
  ///
  /// Holds [addMeasure]'s label rules, plus:
  ///
  /// - A live label may not collide. The schema allows it, but the
  ///   merge-on-read rule would hide the newer row.
  /// - A rename never crosses the reserved serving prefix in either direction:
  ///   it would mint a second serving or retire the row's stated one.
  ///
  /// Throws [ArgumentError] for each, and for an id naming no live measure.
  Future<void> renameMeasure(String measureId, String label);

  /// Re-weighs one live measure: [amount] of the basis unit for one of it.
  /// Keeps the id; throws [ArgumentError] for a non-positive or NaN amount.
  Future<void> setMeasureAmount(String measureId, double amount);

  /// Re-stamps `sort_order` so the ingredient's measures read in the order
  /// [ids] gives.
  ///
  /// The first measure is the ingredient's typical one: it fronts the picker's
  /// chips, and the shop's whole-unit hint rounds to it ("674 g ≈ 3 × potato,
  /// large → buy 3"). Ids that do not belong to the ingredient, or name no live
  /// row, are ignored.
  Future<void> reorderMeasures(String ingredientId, List<String> ids);

  /// What still uses this measure: how many live rows point at it, and which
  /// recipes they are in. The delete is a tombstone with no FK guard, and
  /// orphaned lines silently drop out of macro totals and degrade to a bare
  /// count in the shop, so a delete is refused while this is not zero.
  Future<MeasureUsage> countLinesUsing(String measureId);

  /// Soft-deletes one measure (tombstone, spec §3). A line item referencing
  /// it degrades to its honest stored count — never an invented amount.
  Future<void> softDeleteMeasure(String measureId);
}

/// What a measure is still used by; see [MeasureRepository.countLinesUsing].
/// [lines] counts live rows across the three tables that can name a measure
/// (recipe lines, shopping contributions, planned ingredient meals). [recipes]
/// names only the recipes, which a person can go and fix.
@immutable
class MeasureUsage {
  const MeasureUsage({required this.lines, required this.recipes});

  static const none = MeasureUsage(lines: 0, recipes: []);

  final int lines;

  /// Every live recipe with a line saying this measure, by title.
  final List<({String id, String title})> recipes;

  bool get any => lines > 0;
}
