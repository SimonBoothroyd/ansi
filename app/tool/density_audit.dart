// One-shot audit dump: runs the REAL domain derivation (post-D4c
// `allowedUnitsFor`, `allowedUnitChoicesFor`, import-editor `rankedUnitChips`)
// over a JSON export of the template vocabulary and prints enriched JSON for
// the density/admission audit page. Pure Dart — no Flutter import anywhere on
// this path (domain purity invariant #2 is what makes this script possible).
//
//   dart run tool/density_audit.dart <vocab.json>  > audit.json
import 'dart:convert';
import 'dart:io';

import 'package:ansi/core/units/macros.dart';
import 'package:ansi/core/units/measure.dart';
import 'package:ansi/core/units/units.dart';
import 'package:ansi/features/import/domain/line_validation.dart';
import 'package:ansi/features/ingredients/domain/allowed_units.dart';
import 'package:ansi/features/ingredients/domain/ingredient.dart';

void main(List<String> args) {
  final rows = jsonDecode(File(args.first).readAsStringSync()) as List<dynamic>;
  final out = <Map<String, Object?>>[];
  for (final r in rows.cast<Map<String, dynamic>>()) {
    final basis = r['macros_basis'] == 'ml'
        ? MacrosBasis.perMl
        : MacrosBasis.perG;
    final stored = (r['allowed_units'] as List?)?.cast<String>();
    final ing = Ingredient(
      id: 'audit',
      canonicalName: r['canonical_name'] as String,
      defaultUnit: unitById(r['default_unit'] as String) ?? pieces,
      status: r['status'] == 'stub'
          ? IngredientStatus.stub
          : IngredientStatus.complete,
      category: r['category'] as String?,
      densityGPerMl: (r['density_g_per_ml'] as num?)?.toDouble(),
      macrosBasis: basis,
      allowedUnits: stored?.map(unitById).whereType<Unit>().toList(),
      source: r['source'] as String?,
    );
    final measures = [
      for (final (i, m) in (r['measures'] as List).indexed)
        Measure(
          id: 'm$i',
          label: (m as Map)['label'] as String,
          amount: ((m['amount'] as num?) ?? 0).toDouble(),
          basis: basis,
          sortOrder: (m['sort'] as num?)?.toInt() ?? 0,
        ),
    ];
    final derived = allowedUnitsFor(ing).map((u) => u.id).toList();
    final offer = allowedUnitChoicesFor(ing, measures);
    final chips = acceptableUnitChips(ing, measures);
    final ranked = rankedUnitChips(chips, parsedUnit: null);
    out.add({
      'name': ing.canonicalName,
      'category': ing.category,
      'status': r['status'],
      'source': r['source'],
      'default_unit': ing.defaultUnit.id,
      'density': ing.densityGPerMl,
      'basis': basis == MacrosBasis.perMl ? 'per 100 ml' : 'per 100 g',
      'has_macros': r['has_macros'],
      'stored_units': stored,
      'derived_units': derived,
      'measures': [for (final m in measures) '${m.label} = ${m.amount}'],
      'offer': [
        for (final c in offer.choices)
          switch (c) {
            UnitOption(:final unit) => unit.id,
            MeasureOption(:final measure) => 'M:${measure.label}',
            RecipeMeasureOption(:final measure) => notAWordForAnIngredient(
              measure,
            ),
          },
      ],
      'ranked': [for (final c in ranked) c.token],
    });
  }
  stdout.writeln(const JsonEncoder.withIndent(' ').convert(out));
}
