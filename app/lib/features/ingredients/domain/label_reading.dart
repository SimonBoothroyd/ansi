/// What one photographed nutrition label said. Pure Dart.
///
/// The Dart half of the contract `supabase/functions/_shared/label_types.ts`
/// holds: every figure is one the label PRINTED, and null means "not printed,
/// or not legible" — never zero, and never something derived. The per-100
/// column exists only where the label prints one (EU packs usually do, US
/// Nutrition Facts panels usually do not); the server never computes it, and
/// neither does this.
library;

import '../../../core/units/macros.dart';
import '../../../core/units/unit_words.dart';
import '../../../core/units/units.dart';

/// The five figures one column of a label states. Null is "not printed".
class LabelMacros {
  const LabelMacros({this.kcal, this.protein, this.carb, this.fat, this.fiber});

  factory LabelMacros.fromJson(Map<String, Object?> json) => LabelMacros(
    kcal: _figure(json['kcal']),
    protein: _figure(json['protein_g']),
    carb: _figure(json['carbohydrate_g']),
    fat: _figure(json['fat_g']),
    fiber: _figure(json['fibre_g']),
  );

  final double? kcal;
  final double? protein;
  final double? carb;
  final double? fat;
  final double? fiber;

  /// True when the label printed none of the five in this column.
  bool get isEmpty =>
      kcal == null &&
      protein == null &&
      carb == null &&
      fat == null &&
      fiber == null;
}

/// The serving size as the label prints it.
class LabelServing {
  const LabelServing({this.amount, this.unitPrinted, this.textPrinted});

  factory LabelServing.fromJson(Map<String, Object?> json) => LabelServing(
    amount: _figure(json['amount']),
    unitPrinted: _text(json['unit_printed']),
    textPrinted: _text(json['text_printed']),
  );

  /// The amount a person would type — 55 of `2/3 cup (55g)`.
  final double? amount;

  /// Its unit in the label's own words (`g`, `ml`, `tbsp`). Kept verbatim
  /// because the catalog may not know it.
  final String? unitPrinted;

  /// The whole serving line as printed, for the person to check against and
  /// for the density sentence's other half.
  final String? textPrinted;

  /// The catalog unit [unitPrinted] names, or null when the label used a word
  /// this kitchen does not keep. Mass and volume only: a serving is a measure,
  /// never a count.
  Unit? get unit {
    final word = unitPrinted;
    if (word == null) return null;
    return unitFromWord(
      word,
      families: const {UnitFamily.mass, UnitFamily.volume},
    );
  }
}

/// A per-100 column, and which 100 it is.
class LabelPer100 {
  const LabelPer100({required this.basis, required this.macros});

  /// Null when the label printed no per-100 column, or printed one whose
  /// heading was neither grams nor millilitres.
  static LabelPer100? fromJson(Map<String, Object?> json) {
    final basis = switch (_text(json['basis'])?.toLowerCase()) {
      'g' => MacrosBasis.perG,
      'ml' => MacrosBasis.perMl,
      _ => null,
    };
    if (basis == null) return null;
    return LabelPer100(basis: basis, macros: LabelMacros.fromJson(json));
  }

  final MacrosBasis basis;
  final LabelMacros macros;
}

/// One label, read.
class LabelReading {
  const LabelReading({
    this.serving = const LabelServing(),
    this.perServing = const LabelMacros(),
    this.per100,
    this.notes = const [],
  });

  factory LabelReading.fromJson(Map<String, Object?> json) => LabelReading(
    serving: LabelServing.fromJson(_object(json['serving'])),
    perServing: LabelMacros.fromJson(_object(json['per_serving'])),
    per100: json['per_100'] == null
        ? null
        : LabelPer100.fromJson(_object(json['per_100'])),
    notes: [
      for (final n in json['notes'] is List ? json['notes']! as List : const [])
        if (_text(n) case final s?) s,
    ],
  );

  final LabelServing serving;
  final LabelMacros perServing;

  /// The per-100 column, where the label printed one. Preferred over deriving
  /// from the serving: it is the label's own number, unrounded.
  final LabelPer100? per100;

  /// What could not be read, in plain words. Empty when it read cleanly.
  final List<String> notes;
}

/// A printed figure, or null. Anything that is not a usable non-negative
/// number reads as unprinted — the server coerces the same way.
double? _figure(Object? v) {
  final n = v is num ? v.toDouble() : double.tryParse('$v');
  if (n == null || !n.isFinite || n < 0) return null;
  return n;
}

String? _text(Object? v) {
  if (v is! String) return null;
  final s = v.trim();
  return s.isEmpty ? null : s;
}

Map<String, Object?> _object(Object? v) =>
    v is Map ? Map<String, Object?>.from(v) : const {};
