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
    /// `usda_fdc:<fdc_id>` for a USDA pick, or [usdaDeclinedSource] for a
    /// person's "not this food"). Shown, never interpreted as truth: it says
    /// where the numbers came from, and a machine-supplied one still waits for
    /// a human confirm. Null on a row read by a caller that didn't select it.
    String? source,

    /// The name of the USDA food the row was filled from —
    /// `usda_food.description`, written beside [source] so the form can say
    /// WHICH food filled the row, offline. Survives a decline: the form names
    /// the food that was refused. Null on rows filled before migration 0027 and
    /// on rows nothing filled.
    String? sourceLabel,

    /// How much of the query the matched food's description covered, 0..1 —
    /// the idf-weighted coverage `probe_usda` returns, not a graded confidence.
    /// Stored so `UsdaMatchFit` reads the same offline as it did online. Shown,
    /// never acted on. Null where [sourceLabel] is null, and cleared by a
    /// decline.
    double? sourceScore,
  }) = _Ingredient;
}

/// Whether [source] marks a row filled from USDA — `usda_fdc:<fdc_id>`.
///
/// The stamp means **a person picked that food** from the search; nothing
/// writes it on the row's behalf. Rows carrying it from before migration 0029's
/// automatic prefill are not distinguishable here, which is deliberate — they
/// were not re-matched. The list's stub band and the form's provenance line
/// both read this rather than guessing from the presence of macros.
bool isUsdaPrefilled(String? source) =>
    source?.startsWith('usda_fdc:') ?? false;

/// The `source` a person's *Not this food* leaves behind.
///
/// Its own value rather than a reset to `manual`, because it is how a row says
/// "a person unlinked a USDA pick here" — a distinct fact from "nobody ever
/// linked one", and one the form's provenance line reads.
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
