/// Macro-nutrient values and their stored basis. Pure Dart.
///
/// Macros are stored in the basis the label read them in (per 100 g or per 100
/// ml, `ingredient.macros_basis`). Consumers bridge at computation time: the
/// basis family computes directly, the other needs the ingredient's density,
/// and otherwise the total is incomplete.
library;

import 'dart:convert';

import 'package:meta/meta.dart';

import 'units.dart';

/// Energy and macro-nutrients of 100 units (g or ml, see [MacrosBasis]) of an
/// ingredient. Mirrors the server's `{kcal, protein, carb, fat}` jsonb plus the
/// optional [fiber].
@immutable
class Macros {
  const Macros({
    required this.kcal,
    required this.protein,
    required this.carb,
    required this.fat,
    this.fiber,
  });

  /// Parses the row's serialized jsonb, or null when it is absent or malformed;
  /// no zeros are invented for missing keys. `fiber` is read when present and
  /// its absence costs nothing.
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

  /// The per-100 macros asserted by a label [printed] per serving, scaled by
  /// `100 / serving`.
  ///
  /// [serving] is the serving's amount in [basis]'s base unit (14 for a 14 g
  /// serving). The result is unrounded so the label's rounding is not
  /// compounded. Null when [serving] is not positive and finite.
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

  /// Grams of dietary fibre, the only optional figure. Null means "not stated",
  /// never "none", so a sum ([operator +]) carries fibre only when every addend
  /// did.
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

  /// This macro set scaled by [factor] (a 250 g line of a per-100 g ingredient
  /// is `× 2.5`). An unstated fibre stays unstated.
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

  /// Parses the stored value; anything unexpected falls back to per-100 g.
  static MacrosBasis fromDb(String? value) =>
      value == 'ml' ? MacrosBasis.perMl : MacrosBasis.perG;
}
