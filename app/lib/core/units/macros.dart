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
/// ingredient. Mirrors the server's `{kcal, protein, carb, fat}` jsonb, plus
/// the optional `fiber` key described on [fiber].
@immutable
class Macros {
  const Macros({
    required this.kcal,
    required this.protein,
    required this.carb,
    required this.fat,
    this.fiber,
  });

  /// Parses the vocab row's serialized jsonb, or null when it is absent or
  /// malformed — a row without complete macros is treated exactly like a
  /// stub (invariant 3: no zeros invented for missing keys).
  ///
  /// The `fiber` key is read when it is there and a number, and its absence
  /// costs the row nothing: the four are the panel, fibre is a fifth fact a
  /// source either states or does not ([fiber]).
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
    final fiber = decoded['fiber'];
    return Macros(
      kcal: kcal.toDouble(),
      protein: protein.toDouble(),
      carb: carb.toDouble(),
      fat: fat.toDouble(),
      fiber: fiber is num ? fiber.toDouble() : null,
    );
  }

  /// The per-100 macros a label printed per serving asserts.
  ///
  /// A US Nutrition Facts panel reads "1 Tbsp (14 g) · 100 kcal"; the row
  /// stores per 100 of its [basis], so the [printed] figures are scaled
  /// by `100 / serving`. [serving] is the serving's amount in [basis]'s base
  /// unit (14 for a 14 g serving on a per-100 g row). The result is
  /// **unrounded** on purpose (M-D3): the label's own rounding scales with
  /// it, and rounding again would compound a rounding that was never ours.
  ///
  /// Returns null — never a fabricated number (invariant 3) — when [serving]
  /// is not a positive finite amount: a zero or missing serving weight has
  /// no per-100 reading at all.
  static Macros? per100From({
    required double serving,
    required MacrosBasis basis,
    required Macros printed,
  }) {
    if (!(serving > 0) || !serving.isFinite) return null;
    return printed.scaledBy(100 / serving);
  }

  final double kcal;

  /// Grams of protein / carbohydrate / fat.
  final double protein;
  final double carb;
  final double fat;

  /// Grams of dietary fibre — **optional**, and the only one of the five that
  /// is. The four above are all-or-none ([tryParse]); a source states fibre or
  /// it does not, and a row without it is complete, not a stub.
  ///
  /// Null therefore means "not stated", never "none": the sum rule in
  /// [operator +] is that a total carries fibre only when EVERY addend did,
  /// because adding a stated 3 g to an unstated figure would print a fibre
  /// total that is short by an unknown amount — the fabricated number
  /// invariant 3 forbids.
  final double? fiber;

  /// The `macros` jsonb shape — the four keys always, `fiber` only when it is
  /// stated, so a row that has never had fibre round-trips byte-identically.
  Map<String, double> toJson() => {
    'kcal': kcal,
    'protein': protein,
    'carb': carb,
    'fat': fat,
    if (fiber != null) 'fiber': fiber!,
  };

  /// Adds two macro sets. Fibre survives only when both addends state it —
  /// see [fiber].
  Macros operator +(Macros other) {
    final theirs = other.fiber;
    final mine = fiber;
    return Macros(
      kcal: kcal + other.kcal,
      protein: protein + other.protein,
      carb: carb + other.carb,
      fat: fat + other.fat,
      fiber: mine == null || theirs == null ? null : mine + theirs,
    );
  }

  /// This macro set scaled by [factor] (e.g. a 250 g line of a per-100 g
  /// ingredient is `× 2.5`). An unstated fibre stays unstated — scaling
  /// nothing gives nothing.
  Macros scaledBy(double factor) => Macros(
    kcal: kcal * factor,
    protein: protein * factor,
    carb: carb * factor,
    fat: fat * factor,
    fiber: fiber == null ? null : fiber! * factor,
  );

  @override
  bool operator ==(Object other) =>
      other is Macros &&
      other.kcal == kcal &&
      other.protein == protein &&
      other.carb == carb &&
      other.fat == fat &&
      other.fiber == fiber;

  @override
  int get hashCode => Object.hash(kcal, protein, carb, fat, fiber);

  @override
  String toString() =>
      'Macros($kcal kcal, ${protein}P ${fat}F ${carb}C'
      '${fiber == null ? '' : ', ${fiber}fibre'})';
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
