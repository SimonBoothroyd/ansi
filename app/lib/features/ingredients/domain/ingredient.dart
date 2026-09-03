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
    /// `usda_fdc:<fdc_id>` — the server prefill's mark, plan 0020 D7 — or
    /// [usdaDeclinedSource], a person's "not this food", plan 0027 U-D2).
    /// Shown, never interpreted as truth: it says where the numbers came
    /// from, and a machine-supplied one still waits for a human confirm
    /// (D5). Null on a row read by a caller that didn't select it.
    String? source,

    /// The name of the USDA food the prefill copied from —
    /// `usda_food.description`, written beside [source] by both prefill
    /// writers (migration 0027, plan 0027 U-D1) so the form can say WHICH
    /// food filled the row, offline. Survives a decline: the form names the
    /// food that was refused. Null on rows filled before 0027 and on rows
    /// nothing filled.
    String? sourceLabel,

    /// The trigram score (0.5–1) that earned the match in [sourceLabel],
    /// stored so the band word (`UsdaBand`) is readable offline. Shown, never
    /// acted on — the floor is the server's. Null where the label is null,
    /// and cleared by a decline.
    double? sourceScore,
  }) = _Ingredient;
}

/// Whether [source] marks a row the USDA prefill wrote into —
/// `usda_fdc:<fdc_id>`, stamped by the server trigger and by the app's
/// `applyUsdaProbe` alike. The list's stub band and the form's provenance
/// line both read this rather than guessing from the presence of macros.
bool isUsdaPrefilled(String? source) =>
    source?.startsWith('usda_fdc:') ?? false;

/// The `source` a person's *Not this food* leaves behind (plan 0027 U-D2).
///
/// Its own value rather than a reset to `manual` because the rename
/// trigger's WHEN clause (0015) lists the sources it may refill — `manual`
/// among them — and this one is deliberately not on the list: a food refused
/// once is not offered again by a machine. Only an explicit pick
/// (`applyUsdaProbe` with `explicitPick`) writes over it.
const usdaDeclinedSource = 'usda_declined';

/// Whether [source] is [usdaDeclinedSource].
bool isUsdaDeclined(String? source) => source == usdaDeclinedSource;

/// The FDC id inside a `usda_fdc:<id>` stamp, or null for any other
/// [source] — the number the provenance line prints beside the food's name.
int? usdaFdcId(String? source) {
  if (source == null || !isUsdaPrefilled(source)) return null;
  return int.tryParse(source.substring('usda_fdc:'.length));
}

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
