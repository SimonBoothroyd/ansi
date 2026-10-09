/// Reads stored recipe rows into the domain, the same whichever store they
/// came from (pure Dart).
///
/// The app reads them from its local SQLite; a recipe's share page reads them
/// from Postgres as JSON. The two disagree on representation — SQLite holds a
/// flag as `0`/`1` and a jsonb column as text, Postgres JSON as `true` and an
/// object — and must not disagree on anything else. So the rules a row is read
/// by live here once: a stub ingredient contributes no macros (invariant 3), a
/// line said in a recipe's own word has no unit, an unknown unit id reads as
/// `piece` on a line and drops a recipe measure.
///
/// A line row carries the columns of `recipe_line_item` plus the joined
/// aliases the recipe page's query selects: `ingredient_name`,
/// `ingredient_basis`, `ingredient_macros`, `ingredient_density`,
/// `ingredient_piece_weight`, `ingredient_status`, `ingredient_deleted_at`,
/// `measure_label`, `measure_amount`, `measure_sort`, `measure_source`,
/// `measure_deleted_at`, `sub_title` and the four `sub_yield_*`.
library;

import 'dart:convert';

import '../../../core/units/macros.dart';
import '../../../core/units/measure.dart';
import '../../../core/units/recipe_measure.dart';
import '../../../core/units/units.dart';
import 'component_math.dart';
import 'method_step.dart';
import 'recipe.dart';
import 'recipe_macros.dart';

/// A stored row, as either store hands it over.
typedef StoredRow = Map<String, Object?>;

/// A flag column as a bool. Null (a row from a store that had not yet learned
/// the column) reads as false — the column's own default.
bool rowFlag(Object? value) => value == 1 || value == true;

/// A number column as a double, whether it arrived as a number or as the text
/// a `numeric` can be serialised as. Null and anything unreadable read as null.
double? rowNumber(Object? value) => switch (value) {
  final num n => n.toDouble(),
  final String s => double.tryParse(s),
  _ => null,
};

/// An integer column, read as [rowNumber] reads a number.
int? rowInt(Object? value) => rowNumber(value)?.toInt();

/// A jsonb column decoded: SQLite holds it as text, Postgres JSON as the value
/// itself. Text that is not JSON reads as null.
Object? rowJson(Object? value) {
  if (value is! String) return value;
  try {
    return jsonDecode(value);
  } on FormatException {
    return null;
  }
}

/// The `steps` jsonb: an array of plain-text strings, or an array of tokenized
/// step objects (objects with `tokens`), never both.
(List<String>, List<MethodStep>?) stepsOfColumn(Object? value) {
  final decoded = rowJson(value);
  if (decoded is! List || decoded.isEmpty) return (const [], null);
  if (decoded.first is String) return (decoded.cast<String>(), null);
  return (
    const <String>[],
    [
      for (final e in decoded)
        MethodStep.fromJson((e as Map).cast<String, Object?>()),
    ],
  );
}

/// A recipe row's stated yields, from the four yield columns under [prefix]:
/// `yield_*` on a recipe row, `sub_yield_*` on a line row's joined target.
List<YieldDenomination> yieldsOfRow(StoredRow r, {String prefix = ''}) =>
    yieldDenominations(
      rowNumber(r['${prefix}yield_qty']),
      unitById(r['${prefix}yield_unit'] as String? ?? ''),
      rowNumber(r['${prefix}yield_qty_2']),
      unitById(r['${prefix}yield_unit_2'] as String? ?? ''),
    );

/// What a vocab ingredient contributes to the macro walk, from its row facts.
///
/// [status] is the source of truth for completeness: a stub's macros are
/// excluded even when a value lingers on the row (invariant 3).
IngredientNutrition ingredientNutrition({
  required Object? status,
  required Object? macros,
  required Object? basis,
  required Object? density,
  required Object? pieceWeight,
}) {
  final decoded = rowJson(macros);
  return (
    macros: status == 'complete' && decoded != null
        ? Macros.tryParse(jsonEncode(decoded))
        : null,
    basis: MacrosBasis.fromDb(basis as String?),
    densityGPerMl: rowNumber(density),
    pieceBasisAmount: rowNumber(pieceWeight),
  );
}

/// The nutrition a line row's joined ingredient contributes, or null for a
/// component line, an unknown ingredient or a retired one — whose lines then
/// read as stubs.
IngredientNutrition? nutritionOfLineRow(StoredRow r) {
  if (r['ingredient_id'] == null ||
      r['ingredient_status'] == null ||
      r['ingredient_deleted_at'] != null) {
    return null;
  }
  return ingredientNutrition(
    status: r['ingredient_status'],
    macros: r['ingredient_macros'],
    basis: r['ingredient_basis'],
    density: r['ingredient_density'],
    pieceWeight: r['ingredient_piece_weight'],
  );
}

/// The catalog unit a line row is denominated in, or null when the row names a
/// recipe measure (`recipe_measure_id`).
///
/// The word is asked first, so a row carrying both columns reads as the word. A
/// wordless row with an unknown unit id falls back to `pieces` rather than
/// throwing.
Unit? lineUnitOfRow(StoredRow r) => r['recipe_measure_id'] != null
    ? null
    : unitById(r['unit'] as String? ?? '') ?? pieces;

/// The component target joined onto a line row as `sub_title` /
/// `sub_yield_*`, or null for an ingredient line or a missing target row. Its
/// measures come from [measuresByRecipe], read once for every recipe.
SubRecipeTarget? subRecipeTargetOfRow(
  StoredRow r,
  Map<String, List<RecipeMeasure>> measuresByRecipe,
) {
  final id = r['sub_recipe_id'] as String?;
  final title = r['sub_title'] as String?;
  if (id == null || title == null) return null;
  return SubRecipeTarget(
    id: id,
    title: title,
    yieldQty: rowNumber(r['sub_yield_qty']),
    yieldUnit: unitById(r['sub_yield_unit'] as String? ?? ''),
    yieldQty2: rowNumber(r['sub_yield_qty_2']),
    yieldUnit2: unitById(r['sub_yield_unit_2'] as String? ?? ''),
    measures: measuresByRecipe[id] ?? const <RecipeMeasure>[],
  );
}

/// One line row as a [LineItem].
///
/// The measure resolves only when its row was live; the raw `measure_id` is
/// kept regardless so a save never strips it. A component line's name is its
/// target's title, and a missing target or ingredient reads as unknown and
/// derives nothing.
LineItem lineItemOfRow(
  StoredRow r,
  Map<String, List<RecipeMeasure>> measuresByRecipe,
) {
  final measureId = r['measure_id'] as String?;
  final measureLabel = r['measure_label'] as String?;
  final measureAmount = rowNumber(r['measure_amount']);
  final subRecipeId = r['sub_recipe_id'] as String?;
  return LineItem(
    id: r['id']! as String,
    ingredientId: r['ingredient_id'] as String?,
    subRecipeId: subRecipeId,
    subRecipe: subRecipeTargetOfRow(r, measuresByRecipe),
    ingredientName: subRecipeId != null
        ? r['sub_title'] as String? ?? '(unknown recipe)'
        : r['ingredient_name'] as String? ?? '(unknown ingredient)',
    unit: lineUnitOfRow(r),
    recipeMeasureId: r['recipe_measure_id'] as String?,
    quantity: rowNumber(r['quantity']),
    optional: rowFlag(r['optional']),
    measureId: measureId,
    // Unresolved either way; this tells a deleted measure from one that has
    // not synced yet.
    measureDeleted: r['measure_deleted_at'] != null,
    // The vocab row is joined without the liveness guard so a retired
    // ingredient keeps its last name; this flag marks it as retired.
    ingredientDeleted: r['ingredient_deleted_at'] != null,
    measure: measureId == null || measureLabel == null || measureAmount == null
        ? null
        : Measure(
            id: measureId,
            label: measureLabel,
            amount: measureAmount,
            // The line ingredient's basis denominates its measures (ADR-0008);
            // a tombstoned ingredient falls back per-g.
            basis: MacrosBasis.fromDb(r['ingredient_basis'] as String?),
            sortOrder: rowInt(r['measure_sort']) ?? 0,
            source: r['measure_source'] as String?,
          ),
    note: r['note'] as String?,
  );
}

/// One `recipe_measure` row as the label merge takes it, or null for a row
/// whose `unit` this build does not know (a later build coined it). Dropped
/// rather than given a `pieces` stand-in, which would produce a wrong batch
/// share (ADR-0018); the line naming it reads [ComponentMeasureMissing].
StoredMeasure<RecipeMeasure>? recipeMeasureOfRow(StoredRow r) {
  final recipeId = r['recipe_id'] as String?;
  final unit = unitById(r['unit'] as String? ?? '');
  if (recipeId == null || unit == null) return null;
  return (
    measure: RecipeMeasure(
      id: r['id']! as String,
      recipeId: recipeId,
      label: r['label'] as String? ?? '',
      amount: rowNumber(r['amount']) ?? 0,
      unit: unit,
      sortOrder: rowInt(r['sort_order']) ?? 0,
    ),
    createdAt: r['created_at'],
  );
}

/// Live `recipe_measure` rows by recipe id: the merged offer first, then the
/// merge-hidden duplicates, which a line may still point at
/// ([recipeMeasureById] finds them; the editor's offer does not).
Map<String, List<RecipeMeasure>> recipeMeasuresByRecipe(
  Iterable<StoredRow> rows,
) {
  final byRecipe = <String, List<StoredMeasure<RecipeMeasure>>>{};
  for (final r in rows) {
    final row = recipeMeasureOfRow(r);
    if (row == null) continue;
    (byRecipe[row.measure.recipeId] ??= []).add(row);
  }
  return {
    for (final MapEntry(key: id, value: stored) in byRecipe.entries)
      id: () {
        final merged = mergeByLabel(stored);
        final shown = {for (final m in merged) m.id};
        return [
          ...merged,
          for (final r in stored)
            if (!shown.contains(r.measure.id)) r.measure,
        ];
      }(),
  };
}
