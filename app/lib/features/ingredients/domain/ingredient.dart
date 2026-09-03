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

    /// The explicit per-ingredient allowed-unit list (ADR-0008, migration
    /// 0012) — parsed from the row's `allowed_units` jsonb, unknown ids
    /// dropped. Null for a legacy/unsynced row: the pickers then fall back
    /// to deriving the same ADR defaults (`defaultAllowedUnitSet`).
    List<Unit>? allowedUnits,

    /// The measure a bare COUNT of this ingredient means — "2 onions" is two
    /// `onion, medium` (0023, seam D1). A curated per-row FACT, not a rule:
    /// it is spent once, visibly, when an import line names a number and no
    /// thing, and nothing downstream interprets it.
    ///
    /// **Null is a real answer.** Broccoli's `whole`/`spear`/`crown` are
    /// three different things and none of them is "a broccoli", so that line
    /// keeps its flag and the user picks (ADR-0010). Null also means "this
    /// row has no measures at all", and "the household cleared it".
    String? defaultMeasureId,

    /// Distinct live measure labels this ingredient carries — the picker
    /// row's "N measures" capability hint (7.7). Populated by list reads;
    /// 0 where a caller didn't ask for it.
    @Default(0) int measureCount,

    /// The row's provenance stamp (`seed`, `manual`, `import_stub`,
    /// `usda_fdc:<fdc_id>` — the server prefill's mark, plan 0020 D7).
    /// Shown, never interpreted as truth: it says where the numbers came
    /// from, and a machine-supplied one still waits for a human confirm
    /// (D5). Null on a row read by a caller that didn't select it.
    String? source,
  }) = _Ingredient;
}

/// Whether [source] marks a row the server's USDA prefill wrote into —
/// `usda_fdc:<fdc_id>` (`match_db.ts`). The list's stub band and the form's
/// "filled in for you" banner both read this rather than guessing from the
/// presence of macros.
bool isUsdaPrefilled(String? source) =>
    source?.startsWith('usda_fdc:') ?? false;

/// One alternate name for an ingredient ("mangoes", "ataulfo") — the search
/// cascade matches these as well as [Ingredient.canonicalName], so the
/// flesh-out form owns them (board: "Also known as").
class IngredientAlias {
  const IngredientAlias({
    required this.id,
    required this.text,
    required this.source,
  });

  final String id;
  final String text;

  /// `seed`, `manual` (typed here), or `import_correction` (lane B's
  /// correction loop). Rendered so a user can tell their own alias from one
  /// an import minted.
  final String source;
}
