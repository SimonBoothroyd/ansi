/// How a barcode draft lands on an ingredient, through [applyDraft]. Pure Dart.
///
/// - A draft fills what is empty and leaves what a human typed alone.
/// - Provenance becomes `off:<barcode>` unless the row already names its food
///   ([hasLookupProvenance]); a seed row still holding the seed's numbers stays
///   unattributed.
/// - `status` is untouched, and a pack size is only ever an offer.
///
/// What was skipped is reported by name so the host can say so.
library;

import '../../../core/result/result.dart';
import '../../../core/units/macros.dart';
import '../../../core/units/units.dart';
// This is the one file outside the barcode directory allowed to import the
// hand-off type directly: the module's door (`barcode_add.dart`) imports
// Flutter, which a domain file may not.
import '../barcode/ingredient_draft.dart';
import 'ingredient.dart';

/// A field a draft could have filled and did not, because a human already
/// had. Named so the card can say which.
enum DraftSkip {
  name('the name — yours stays'),
  macros('the macros — the ones already entered stay'),
  provenance('the provenance — this row already names a source');

  const DraftSkip(this.reason);

  /// The clause the card prints after "kept:".
  final String reason;
}

/// What the host currently holds for the row the draft is landing on, as the
/// human sees it now. Null or empty means the slot is free.
class DraftTarget {
  const DraftTarget({
    this.name = '',
    this.hasMacros = false,
    this.macrosBasis = MacrosBasis.perG,
    this.source,
  });

  /// The name in the field, trimmed by the rule; empty means free.
  final String name;

  /// Whether a macro panel is already there — entered, prefilled or saved. A
  /// half-typed panel counts as "there": the rule never overwrites keystrokes.
  final bool hasMacros;

  /// The basis the existing panel is in. Only read when [hasMacros] holds,
  /// because a pack size is bridged into the basis the row will actually keep.
  final MacrosBasis macrosBasis;

  /// The row's stored provenance, or null before it exists.
  final String? source;
}

/// A pack size the draft offers as a measure, already in the row's basis.
class PackMeasureOffer {
  const PackMeasureOffer({required this.amountInBasis, required this.basis});

  /// The amount a "pack" of this product is, in [basis]'s base unit.
  final double amountInBasis;

  /// The basis it was bridged into — the draft's own when the draft's panel
  /// is taken, the row's when the row's panel stays.
  final MacrosBasis basis;
}

/// What [applyDraft] decided. A null member means "leave that alone".
class DraftApplication {
  const DraftApplication({
    required this.skipped,
    this.name,
    this.macros,
    this.macrosBasis,
    this.servingPanel,
    this.serving,
    this.source,
    this.sourceLabel,
    this.packMeasure,
  });

  /// The name to put in the field, or null when the human's stays.
  final String? name;

  /// The panel to put in the fields, with [macrosBasis]. Null when the human's
  /// panel stays or the draft has none.
  final Macros? macros;

  /// The basis the landing panel reads in. Set with [macros] or [servingPanel];
  /// null when neither lands.
  final MacrosBasis? macrosBasis;

  /// A per-serving panel to land on the host's per-serving mode. Null when the
  /// human's panel stays. [macros] is null whenever this is set; the host
  /// derives the per-100 reading.
  final DraftServingPanel? servingPanel;

  /// The serving a per-100 panel also printed, to seed the row's `serving`
  /// measure. It lands only with [macros].
  final DraftServing? serving;

  /// The provenance to write (`off:<barcode>`), or null to keep the stored one.
  final String? source;

  /// What to call the pack the [source] stamp points at: the row's
  /// `source_label`. Set only with [source]; null when the draft named neither
  /// a brand nor a product.
  final String? sourceLabel;

  /// The pack size, offered — see [PackMeasureOffer]. Null when the draft has
  /// none or it cannot be bridged into the basis honestly.
  final PackMeasureOffer? packMeasure;

  /// What a human already had, and so was not touched.
  final List<DraftSkip> skipped;

  /// Whether the draft changed anything at all — false for a not-found scan
  /// landing on a row that already has a name.
  bool get fillsSomething =>
      name != null || macros != null || servingPanel != null || source != null;
}

/// Applies [draft] onto [target] under the rule in this file's header.
DraftApplication applyDraft(
  IngredientDraft draft, {
  required DraftTarget target,
}) {
  final skipped = <DraftSkip>[];

  String? name;
  if (target.name.trim().isEmpty) {
    name = draft.suggestedName.isEmpty ? null : draft.suggestedName;
  } else if (draft.suggestedName.isNotEmpty) {
    skipped.add(DraftSkip.name);
  }

  Macros? macros;
  MacrosBasis? macrosBasis;
  DraftServingPanel? servingPanel;
  DraftServing? serving;
  if (draft.macros != null || draft.servingPanel != null) {
    if (target.hasMacros) {
      skipped.add(DraftSkip.macros);
    } else {
      macros = draft.macros;
      macrosBasis = draft.macrosBasis;
      servingPanel = draft.servingPanel;
      serving = draft.serving;
    }
  }

  // Only a barcode draft that actually found something carries a source
  // worth stamping; the not-found exit's `manual` says nothing new.
  String? source;
  String? sourceLabel;
  if (draft.source == DraftSource.barcode && draft.barcode != null) {
    if (hasLookupProvenance(target.source)) {
      skipped.add(DraftSkip.provenance);
    } else if (target.source == 'seed' && target.hasMacros) {
      // A seed row's numbers are the reference's, so a scan must not put a
      // pack's name over them. Every other unnamed row is named by the pack.
    } else {
      source = draft.sourceValue;
      sourceLabel = packLabel(draft);
    }
  }

  // The basis the row will keep: the draft's when its panel is taken, the
  // row's otherwise. A pack size is only worth offering in that basis.
  final keptBasis = macrosBasis ?? target.macrosBasis;
  final packAmount = packAmountInBasis(draft, keptBasis);

  return DraftApplication(
    name: name,
    macros: macros,
    macrosBasis: macrosBasis,
    servingPanel: servingPanel,
    serving: serving,
    source: source,
    sourceLabel: sourceLabel,
    packMeasure: packAmount == null
        ? null
        : PackMeasureOffer(amountInBasis: packAmount, basis: keptBasis),
    skipped: skipped,
  );
}

/// What to call the pack a barcode draft came from: the brand then the product
/// name, verbatim, as a shelf prints them. Either alone stands; null when there
/// is neither. A product name that already opens with its brand is not given it
/// twice.
String? packLabel(IngredientDraft draft) {
  final brand = draft.brand?.trim() ?? '';
  final product = draft.productName?.trim() ?? '';
  if (product.isEmpty) return brand.isEmpty ? null : brand;
  if (brand.isEmpty) return product;
  if (product.toLowerCase().startsWith(brand.toLowerCase())) return product;
  return '$brand $product';
}

/// Whether [source] names the food the row's numbers came from: a USDA pick
/// (`usda_fdc:<id>`) or a barcode scan (`off:<barcode>`). Every other stamp
/// (`seed`, `import_stub`, `fdc_density:<id>`) says how the row or its density
/// arrived and does not stop a scan from naming the pack.
bool hasLookupProvenance(String? source) =>
    isUsdaPrefilled(source) || isBarcodeFilled(source);

/// The pack size in [basis]'s base unit, or null when there is none or it
/// cannot be bridged. A measure stores its amount in the basis unit (ADR-0008)
/// and a barcode carries no density, so "400 ml" on a per-100 g row yields no
/// offer.
double? packAmountInBasis(IngredientDraft draft, MacrosBasis basis) {
  final pack = draft.packSize;
  if (pack == null) return null;
  final inBasis = convert(
    Quantity(pack.amount, pack.unit),
    to: basis.baseUnit,
    densityGPerMl: draft.densityGPerMl,
  );
  return switch (inBasis) {
    Ok(:final value) when value.amount > 0 => value.amount,
    Ok() || Err() => null,
  };
}
