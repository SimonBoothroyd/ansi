/// How a barcode draft lands on an ingredient — PURE DART (invariant 2).
///
/// The ingredient form takes an [IngredientDraft] whether or not the row
/// exists yet, and whether or not a human has already typed into the fields. It
/// applies every draft through [applyDraft], so there is one answer to "what
/// does a scan overwrite":
///
/// - **A draft fills what is EMPTY and leaves what a human typed alone.** A
///   name already in the field, a macro panel already entered, a provenance a
///   lookup already stamped — none of it is replaced by a shop's label.
/// - **Provenance becomes `off:<barcode>` only where the row had none.**
///   `manual` counts as none: it is the stamp for "nobody looked anything up",
///   which is exactly what a scan has just changed. A USDA id or `seed` is a
///   source and stays. The stamp travels with a **name for the pack**
///   ([DraftApplication.sourceLabel]), because a barcode is a key and nobody
///   reads keys.
/// - **Nothing here confirms the row**. The application is values for fields;
///   `status` is untouched and the human confirms.
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
    this.serving,
    this.source,
    this.sourceLabel,
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

  /// A panel printed per serving to land on the host's per-serving mode — the
  /// same slot [macros] fills, so the same rule: null when the human's panel
  /// stays. [macros] is null whenever this is set; the per-100 reading is the
  /// host's to derive, in front of the person.
  final DraftServingPanel? servingPanel;

  /// The serving a per-100 panel also printed, to seed the row's one `serving`
  /// measure. It rides with [macros] and is dropped on the same terms: a
  /// serving describes the panel it was printed beside, so a panel that was
  /// not taken brings no serving with it.
  final DraftServing? serving;

  /// The provenance to write (`off:<barcode>`), or null to keep the stored one.
  final String? source;

  /// What to call the pack the [source] stamp points at — the row's
  /// `source_label`, so a scanned row can name its food the way a USDA-filled
  /// one names its description. Set only with [source]; null where the draft
  /// named neither a brand nor a product, which means **no line** rather than
  /// a name assembled out of nothing.
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

/// What to call the pack a barcode draft came from, or null when Open Food
/// Facts named neither a brand nor a product.
///
/// The brand and the product name, in the order a shelf prints them —
/// "Kraft mac & cheese". Either alone stands on its own; **neither is not a
/// name**, and null is the honest answer, because the alternative is a row
/// whose provenance reads as a name nobody ever wrote. Nothing is re-cased or
/// re-worded: what the pack says is evidence, the same reason
/// [IngredientDraft.suggestedName] copies it verbatim.
///
/// A product name that already opens with its brand — "Monster Energy" by
/// "Monster" — does not get it a second time. OFF's contributors put the brand
/// in both fields often enough that the doubled reading would be the common
/// one, not the exception.
String? packLabel(IngredientDraft draft) {
  final brand = draft.brand?.trim() ?? '';
  final product = draft.productName?.trim() ?? '';
  if (product.isEmpty) return brand.isEmpty ? null : brand;
  if (brand.isEmpty) return product;
  if (product.toLowerCase().startsWith(brand.toLowerCase())) return product;
  return '$brand $product';
}

/// Whether [source] records that something looked this row up — anything but
/// null and `manual`. `seed`, `usda_fdc:<id>` and `off:<barcode>` all do, and
/// so does `import_stub` on the rows in the wild that still carry it: it never
/// meant numbers, but it does say where the row came from.
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
