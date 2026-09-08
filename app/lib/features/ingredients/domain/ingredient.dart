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
    /// `usda_fdc:<fdc_id>` for a USDA pick, `off:<barcode>` for a scan, or
    /// [usdaDeclinedSource] for a person's "not this food"). Shown, never
    /// interpreted as truth: it says where the numbers came from, and a
    /// machine-supplied one still waits for a human confirm. Null on a row read
    /// by a caller that didn't select it.
    String? source,

    /// The food the row was filled from, **named** — `usda_food.description`
    /// for a pick, the pack's brand and product name for a scan — written
    /// beside [source] so every surface can say WHICH food filled the row,
    /// offline. It is what the ids in [source] are for a reader: the stamp is a
    /// key, this is the answer. Survives a decline, so the form can name the
    /// food that was refused. Null on rows filled before the column existed and
    /// on rows nothing filled, and null is a real answer — a surface then says
    /// nothing rather than inventing a name.
    String? sourceLabel,

    /// How much of the query the matched food's description covered, 0..1 —
    /// the idf-weighted coverage `probe_usda` returns, not a graded confidence.
    /// Stored so `UsdaMatchFit` reads the same offline as it did online. Shown,
    /// never acted on. A USDA fact only: a scan matches nothing, so a barcode
    /// row carries a [sourceLabel] and no score. Cleared by a decline.
    double? sourceScore,

    /// Whether a human has overridden the numbers the lookup filled in
    /// (migration 0034) — **macros, macros basis or density**,
    /// on a row whose [source] is a lookup stamp.
    ///
    /// It exists because [source] is patch-shaped and survives a form save, so
    /// without it a row goes on naming a USDA food whose figures are no longer
    /// on it. The fence is what keeps it honest: it means *the numbers are no
    /// longer the source's*, so a rename, a unit toggle, a measure or an alias
    /// must never set it — none of those contradicts the source. A fresh pick
    /// clears it, because the numbers are the new food's.
    @Default(false) bool sourceEdited,
  }) = _Ingredient;
}

/// Whether [source] is a machine **lookup's** stamp — a USDA pick
/// (`usda_fdc:<id>`) or a barcode read (`off:<barcode>`).
///
/// The predicate [Ingredient.sourceEdited]'s fence is keyed on: those are the
/// two provenances that assert "these numbers came from somewhere else", so
/// they are the two a human edit can contradict. `seed`, `manual`,
/// `import_stub`, [usdaDeclinedSource] and a null all carry no such claim, and
/// a row wearing one is never flagged.
bool isLookupFilled(String? source) =>
    isUsdaPrefilled(source) || isBarcodeFilled(source);

/// The one line the ingredients list and the import review's identity cell
/// print under a machine-filled row's name, or null
/// where there is nothing true to say.
///
/// One rule, two surfaces — rendering it twice in two places is how the same
/// row starts telling two stories. Deliberately absent from the ingredient
/// **picker**: that is a search surface, and a description under every row is
/// noise while you are typing.
///
/// The word before the label is **where the name came from**, not what the
/// stamp encodes: `usda · «description»` for a pick, `barcode · «brand and
/// product»` for a scan. Neither prints the key inside the stamp — an FDC id
/// and a GTIN are lookups into databases the reader does not have.
///
/// **No label, no line**: a row filled before the label column existed carries
/// a stamp and no name, and it says nothing rather than inventing one — the
/// same rule the form's provenance card holds. A declined row says nothing
/// either: its numbers are gone, so there is no fill to name.
String? sourceProvenanceLine(Ingredient ingredient) {
  final label = ingredient.sourceLabel;
  if (label == null || label.isEmpty) return null;
  final String kind;
  if (isUsdaPrefilled(ingredient.source)) {
    kind = 'usda';
  } else if (isBarcodeFilled(ingredient.source)) {
    kind = 'barcode';
  } else {
    return null;
  }
  // `edited ·` LEADS the line, so a scan down the list shows which rows are no
  // longer the machine's before it shows whose food they were.
  return '${ingredient.sourceEdited ? 'edited · ' : ''}$kind · $label';
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

/// Whether [source] marks a row filled from a barcode scan — `off:<barcode>`.
///
/// Like a USDA stamp it means **a person scanned that pack**; and like one, the
/// code inside it is never what a surface prints. What the row says out loud is
/// [Ingredient.sourceLabel] — the brand and product name the scan wrote beside
/// the stamp.
bool isBarcodeFilled(String? source) => source?.startsWith('off:') ?? false;

/// The `source` a person's *Not this food* leaves behind.
///
/// Its own value rather than a reset to `manual`, because it is how a row says
/// "a person unlinked a USDA pick here" — a distinct fact from "nobody ever
/// linked one", and one the form's provenance line reads.
const usdaDeclinedSource = 'usda_declined';

/// Whether [source] is [usdaDeclinedSource].
bool isUsdaDeclined(String? source) => source == usdaDeclinedSource;

/// The FDC id inside a `usda_fdc:<id>` stamp, or null for any other [source].
///
/// A **fallback name**, not a caption: no surface prints it beside the food's
/// own name, because a reader has no FoodData Central to look it up in. The
/// form's provenance card falls back to it only on a row that carries no
/// [Ingredient.sourceLabel], where it is the one true thing left to say.
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
