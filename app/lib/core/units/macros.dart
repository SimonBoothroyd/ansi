/// Macro-nutrient values and their stored basis — PURE DART (invariant 2),
/// beside `units.dart`/`measure.dart` as part of the honest-numbers
/// vocabulary (spec §4, step 7.7).
///
/// The vocab stores macros **with the basis the label read them in**
/// (per-100 g or per-100 ml — `ingredient.macros_basis`, migration 0011):
/// liquid labels read per 100 ml and densities are sparse, so converting at
/// entry can't be the design. Consumers bridge at computation time instead —
/// a quantity in the basis's own family computes directly; cross-basis needs
/// the ingredient's density; otherwise the total is honestly `incomplete`
/// (invariant 3 — never a fabricated number).
library;

import 'dart:convert';

import 'package:meta/meta.dart';

import 'units.dart';

/// Energy + macro-nutrients of 100 units (g or ml — see [MacrosBasis]) of an
/// ingredient. Mirrors the server's `{kcal, protein, carb, fat}` jsonb.
@immutable
class Macros {
  const Macros({
    required this.kcal,
    required this.protein,
    required this.carb,
    required this.fat,
  });

  /// Parses the vocab row's serialized jsonb, or null when it is absent or
  /// malformed — a row without complete macros is treated exactly like a
  /// stub (invariant 3: no zeros invented for missing keys).
  static Macros? tryParse(String? json) {
    if (json == null || json.isEmpty) return null;
    final Object? decoded;
    try {
      decoded = jsonDecode(json);
    } on FormatException {
      return null;
    }
    if (decoded is! Map<String, dynamic>) return null;
    final kcal = decoded['kcal'];
    final protein = decoded['protein'];
    final carb = decoded['carb'];
    final fat = decoded['fat'];
    if (kcal is! num || protein is! num || carb is! num || fat is! num) {
      return null;
    }
    return Macros(
      kcal: kcal.toDouble(),
      protein: protein.toDouble(),
      carb: carb.toDouble(),
      fat: fat.toDouble(),
    );
  }

  final double kcal;

  /// Grams of protein / carbohydrate / fat.
  final double protein;
  final double carb;
  final double fat;

  Macros operator +(Macros other) => Macros(
    kcal: kcal + other.kcal,
    protein: protein + other.protein,
    carb: carb + other.carb,
    fat: fat + other.fat,
  );

  /// This macro set scaled by [factor] (e.g. a 250 g line of a per-100 g
  /// ingredient is `× 2.5`).
  Macros scaledBy(double factor) => Macros(
    kcal: kcal * factor,
    protein: protein * factor,
    carb: carb * factor,
    fat: fat * factor,
  );

  @override
  bool operator ==(Object other) =>
      other is Macros &&
      other.kcal == kcal &&
      other.protein == protein &&
      other.carb == carb &&
      other.fat == fat;

  @override
  int get hashCode => Object.hash(kcal, protein, carb, fat);

  @override
  String toString() => 'Macros($kcal kcal, ${protein}P ${fat}F ${carb}C)';
}

/// The per-100 basis a vocab row's [Macros] were entered in.
enum MacrosBasis {
  /// Per 100 g — every USDA prefill row, and the default.
  perG('g'),

  /// Per 100 ml — liquid labels.
  perMl('ml');

  const MacrosBasis(this.dbValue);

  /// The persisted `ingredient.macros_basis` value.
  final String dbValue;

  /// The catalog unit 100 of which the macros describe — the conversion
  /// target when a line's quantity joins a macro total.
  Unit get baseUnit => this == MacrosBasis.perG ? g : ml;

  /// Parses the stored value; anything unexpected falls back to per-100 g
  /// (the column's default and check constraint make this unreachable in
  /// practice).
  static MacrosBasis fromDb(String? value) =>
      value == 'ml' ? MacrosBasis.perMl : MacrosBasis.perG;
}
