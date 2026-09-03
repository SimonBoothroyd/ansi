/// How a barcode draft lands on an ingredient — PURE DART (invariant 2).
///
/// Two surfaces take an [IngredientDraft]: the New-ingredient sheet (the row
/// does not exist yet) and the flesh-out form (it does, and a human may
/// already have typed into it — plan 0025 #8). Both apply it through
/// [applyDraft], so there is one answer to "what does a scan overwrite":
///
/// - **A draft fills what is EMPTY and leaves what a human typed alone.** A
///   name already in the field, a macro panel already entered, a provenance a
///   lookup already stamped — none of it is replaced by a shop's label.
/// - **Provenance becomes `off:<barcode>` only where the row had none.**
///   `manual` counts as none: it is the stamp for "nobody looked anything up",
///   which is exactly what a scan has just changed. A USDA id or `seed` is a
///   source and stays.
/// - **Nothing here confirms the row** (plan 0020 D1/D5). The application is
///   values for fields; `status` is untouched and the human confirms.
/// - **A pack size is an OFFER, never a write.** The draft's "400 ml" becomes
///   a ready-made measure only when the person ticks or taps it — and only
///   when it converts honestly into the row's own basis (a measure stores its
///   amount in the basis unit, ADR-0008, and a barcode carries no density).
///
/// What was skipped is reported by name, so the host can say so instead of
/// leaving the user to wonder why the panel on the card is not in the fields.
library;

import '../../../core/result/result.dart';
import '../../../core/units/macros.dart';
import '../../../core/units/units.dart';
// The hand-off type is pure Dart and lives behind the barcode module's door;
// this is the one file outside that directory allowed to name it directly,
// because the door itself (`barcode_add.dart`) imports Flutter and a domain
// file may not.
import '../barcode/ingredient_draft.dart';

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

/// What the host currently holds for the row the draft is landing on.
///
/// Every value is "as the human sees it right now": the sheet passes what is
/// typed into it, the form passes its unsaved draft. Null / empty means the
/// slot is free.
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
    this.source,
    this.packMeasure,
  });

  /// The name to put in the field, or null when the human's stays.
  final String? name;

  /// The panel to put in the fields, with [macrosBasis]. Null when the
  /// human's panel stays, and null when the draft has none: an absent panel
  /// is a fact about Open Food Facts, never a row of zeros.
  final Macros? macros;

  /// The basis the landing panel reads in — set with [macros], or with
  /// [servingPanel] (the serving's own basis, the row's default when OFF
  /// named none); null when neither lands.
  final MacrosBasis? macrosBasis;

  /// A panel printed per serving to land on the host's per-serving mode
  /// (plan 0027 M-D5) — the same slot [macros] fills, so the same rule: null
  /// when the human's panel stays. [macros] is null whenever this is set;
  /// the per-100 reading is the host's to derive, in front of the person.
  final DraftServingPanel? servingPanel;

  /// The provenance to write (`off:<barcode>`), or null to keep the stored one.
  final String? source;

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
  if (draft.macros != null || draft.servingPanel != null) {
    if (target.hasMacros) {
      skipped.add(DraftSkip.macros);
    } else {
      macros = draft.macros;
      macrosBasis = draft.macrosBasis;
      servingPanel = draft.servingPanel;
    }
  }

  // Only a barcode draft that actually found something carries a source
  // worth stamping; the not-found exit's `manual` says nothing new.
  String? source;
  if (draft.source == DraftSource.barcode && draft.barcode != null) {
    if (hasLookupProvenance(target.source)) {
      skipped.add(DraftSkip.provenance);
    } else {
      source = draft.sourceValue;
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
    source: source,
    packMeasure: packAmount == null
        ? null
        : PackMeasureOffer(amountInBasis: packAmount, basis: keptBasis),
    skipped: skipped,
  );
}

/// Whether [source] records that something looked this row up — anything but
/// null and `manual`. `seed`, `usda_fdc:<id>` and `off:<barcode>` all do;
/// `import_stub` (the retired commit-time stub) never carried numbers but
/// stays honest about where the row came from, so it counts too.
bool hasLookupProvenance(String? source) =>
    source != null && source.isNotEmpty && source != 'manual';

/// The pack size expressed in [basis]'s base unit, or null when there is no
/// pack size or it cannot be bridged honestly.
///
/// Open Food Facts' free-text `quantity` ("400 ml", "1 kg") is a ready-made
/// measure — but a measure stores its amount in the ingredient's **basis**
/// unit (ADR-0008), and a barcode carries no density. So "400 ml" on a
/// per-100 ml row converts, "1 kg" on a per-100 g row converts, and "400 ml"
/// on a per-100 g row does **not** — the offer is simply absent rather than
/// present and wrong.
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
