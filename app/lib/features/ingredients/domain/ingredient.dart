/// The ingredient vocabulary entity — PURE DART (invariant 2).
///
/// Density/macros are nullable and a `stub` row omits them (invariant 3,
/// honest numbers) — the picker flags stubs instead of showing zeros, and
/// the macro summation excludes them (rendering the recipe `incomplete`).
/// `macros` carries the vocab's per-100 values in `macrosBasis` (per-100 g
/// or per-100 ml — stored with the basis the label read them in, 0011).
library;

import 'package:freezed_annotation/freezed_annotation.dart';

import '../../../core/units/macros.dart';
import '../../../core/units/units.dart';

part 'ingredient.freezed.dart';

enum IngredientStatus { complete, stub }

@freezed
abstract class Ingredient with _$Ingredient {
  const factory Ingredient({
    required String id,
    required String canonicalName,
    required Unit defaultUnit,
    required IngredientStatus status,
    String? category,
    double? densityGPerMl,
    Macros? macros,
    @Default(MacrosBasis.perG) MacrosBasis macrosBasis,
  }) = _Ingredient;
}
