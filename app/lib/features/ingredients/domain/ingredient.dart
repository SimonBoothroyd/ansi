/// The ingredient vocabulary entity. Pure Dart.
///
/// Density and macros are nullable and a `stub` row omits them: the picker
/// flags stubs instead of showing zeros, and macro totals exclude them.
/// `macros` holds per-100 values in `macrosBasis` (per 100 g or per 100 ml).
library;

import 'package:freezed_annotation/freezed_annotation.dart';

import '../../../core/units/macros.dart';
import '../../../core/units/units.dart';
import 'density_said.dart';

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

    /// The sentence [densityGPerMl] was said as ("⅓ cup weighs 40 g"), as
    /// stored. Read it through [densitySaidOf], which drops one that no longer
    /// states the stored number. Null when the density came from a door that
    /// said no sentence.
    DensitySaid? densitySaid,
    Macros? macros,
    @Default(MacrosBasis.perG) MacrosBasis macrosBasis,

    /// The explicit allowed-unit list (ADR-0008), parsed from the row's
    /// `allowed_units` jsonb with unknown ids dropped. Null for a legacy or
    /// unsynced row; pickers then derive `defaultAllowedUnitSet`.
    List<Unit>? allowedUnits,

    /// What one of this ingredient weighs, in the row's basis unit (ADR-0015).
    /// It unlocks `piece` as density unlocks the volume units. Null means
    /// `piece` is not sayable; a piece-default row with a null is named on the
    /// form and refused at Save.
    double? pieceBasisAmount,

    /// Where [pieceBasisAmount] came from: `manual`, `borrowed from <label>`
    /// for a seeded copy of a curated size, or `seed:typical`. Shown, never
    /// interpreted. Null when there is no weight.
    String? pieceSource,

    /// Distinct live measure labels, for the picker row's "N measures" hint.
    /// Populated by list reads; 0 otherwise.
    @Default(0) int measureCount,

    /// The row's provenance stamp: `seed`, `manual`, `import_stub`,
    /// `usda_fdc:<fdc_id>`, `off:<barcode>`, [labelPhotoSource], or
    /// [usdaDeclinedSource]. Shown, never treated as truth; a
    /// machine-supplied one still waits for a human confirm. Null when the
    /// caller did not select it.
    String? source,

    /// The food the row was filled from, named: `usda_food.description` for a
    /// pick, the pack's brand and product for a scan. Lets every surface say
    /// which food filled the row, offline. Survives a decline. Null when
    /// nothing filled the row, and null on a photographed label, which names
    /// no food — the person had already named the row.
    String? sourceLabel,

    /// How much of the query the matched USDA description covered, 0..1 (the
    /// idf-weighted coverage `probe_usda` returns). Stored so `UsdaMatchFit`
    /// reads the same offline. Shown, never acted on. Null on a barcode row;
    /// cleared by a decline.
    double? sourceScore,

    /// Whether a human has overridden the macros, macros basis or density a
    /// lookup filled in, on a row whose [source] is a lookup stamp. Renames,
    /// unit toggles, measures and aliases never set it. A fresh pick clears it.
    @Default(false) bool sourceEdited,
  }) = _Ingredient;
}

/// Whether [source] is a lookup's stamp: a USDA pick (`usda_fdc:<id>`), a
/// barcode read (`off:<barcode>`) or a photographed label. Only these rows can
/// be flagged [Ingredient.sourceEdited].
bool isLookupFilled(String? source) =>
    isUsdaPrefilled(source) || isBarcodeFilled(source) || isLabelFilled(source);

/// The line the ingredients list and the import review print under a
/// machine-filled row's name, or null. Not used by the picker.
///
/// Reads `usda · «description»` for a pick and `barcode · «brand and product»`
/// for a scan; the key inside the stamp is never printed. A photographed label
/// names no food, so it prints the kind alone. A row with no label, or a
/// declined one, gets no line.
String? sourceProvenanceLine(Ingredient ingredient) {
  final edited = ingredient.sourceEdited ? 'edited · ' : '';
  if (isLabelFilled(ingredient.source)) return '${edited}label photo';
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

/// Whether [source] marks a row filled from USDA (`usda_fdc:<fdc_id>`): a
/// person picked that food from the search. The list's stub band and the form's
/// provenance line read this rather than guessing from the macros.
bool isUsdaPrefilled(String? source) =>
    source?.startsWith('usda_fdc:') ?? false;

/// Whether [source] marks a row filled from a barcode scan (`off:<barcode>`).
/// Surfaces print [Ingredient.sourceLabel], never the code.
bool isBarcodeFilled(String? source) => source?.startsWith('off:') ?? false;

/// The `source` a nutrition label read from a photograph leaves behind. It
/// carries no key, because a photo identifies nothing that could be looked up
/// again — the figures are the whole of what it brought.
const labelPhotoSource = 'label_photo';

/// Whether [source] marks a row filled from a photographed nutrition label.
bool isLabelFilled(String? source) => source == labelPhotoSource;

/// The `source` a person's *Not this food* leaves behind. Distinct from
/// `manual` so the form's provenance line can say a USDA pick was unlinked.
const usdaDeclinedSource = 'usda_declined';

/// Whether [source] is [usdaDeclinedSource].
bool isUsdaDeclined(String? source) => source == usdaDeclinedSource;

/// The FDC id inside a `usda_fdc:<id>` stamp, or null for any other [source].
/// The form's provenance card prints it only on a row with no
/// [Ingredient.sourceLabel].
int? usdaFdcId(String? source) {
  if (source == null || !isUsdaPrefilled(source)) return null;
  return int.tryParse(source.substring('usda_fdc:'.length));
}

/// One alternate name for an ingredient ("mangoes", "ataulfo"). The search
/// cascade matches these as well as [Ingredient.canonicalName].
class IngredientAlias {
  const IngredientAlias({
    required this.id,
    required this.text,
    required this.source,
  });

  final String id;
  final String text;

  /// `seed`, `manual` (typed here) or `import_correction` (learned from an
  /// import). Rendered so a user can tell their own alias from a learned one.
  final String source;
}
