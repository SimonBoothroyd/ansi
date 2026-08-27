/// The ingredient vocabulary entity — PURE DART (invariant 2).
///
/// Step 2 uses only the read-only slice needed to attach an ingredient to a
/// recipe line (the inline picker). The full "create new / stub queue" feature
/// is deferred (see the step-2 exec plan). Density/macros are nullable and a
/// `stub` row omits them (invariant 3, honest numbers) — carried here so the
/// picker can flag stubs, though step 2 does nothing else with them.
library;

import 'package:freezed_annotation/freezed_annotation.dart';

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
  }) = _Ingredient;
}
