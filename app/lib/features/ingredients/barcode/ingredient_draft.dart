/// The barcode path's hand-off type — PURE DART (invariant 2).
///
/// An [IngredientDraft] is a *sketch*, never a row. Plan 0020 D1 settles that
/// an Open Food Facts lookup **prefills a draft and never completes an
/// ingredient**: OFF is volunteer-entered, so a product with a blank or
/// absurd panel is ordinary. Everything a lookup could not establish stays
/// null here — never zero, never guessed (invariant 3, honest numbers) — and
/// the human confirms what survives into the row (D5: macros gate `complete`,
/// and confirming is a human act).
///
/// The type is deliberately decoupled from the manager's form: plain fields,
/// no Flutter, no repository. The form reads them as initial values.
library;

import 'package:meta/meta.dart';

import '../../../core/units/macros.dart';
import '../../../core/units/units.dart';

/// Where a draft's fields came from — the provenance the form annotates and
/// the ingredient row's `source` column ultimately records.
enum DraftSource {
  /// An Open Food Facts product read, keyed by barcode.
  barcode,

  /// Nothing was looked up: the user is filling the form in by hand. A
  /// not-found scan lands here too, keeping the code it scanned.
  manual,
}

/// Why a draft carries no [IngredientDraft.macros].
///
/// The message is the honest sentence the form shows in place of the numbers.
/// It exists because "blank" alone reads as "we forgot to ask".
enum DraftMacrosGap {
  /// Macros are present — nothing to explain.
  none(null),

  /// The product is in Open Food Facts but nobody has entered its panel.
  noPanel('Open Food Facts has no nutrition panel for this product.'),

  /// The panel Open Food Facts holds is per *serving*. Converting it to a
  /// per-100 basis needs the serving's mass, and OFF's `serving_size` is
  /// free text ("1 serving (16 fl oz)") — so the fields stay blank rather
  /// than divided by a guess (plan 0020 D1).
  perServingPanel(
    'Open Food Facts holds this panel per serving, not per 100 — and its '
    'serving size is free text, so a per-100 figure would be a guess.',
  );

  const DraftMacrosGap(this.message);

  /// The sentence to show under the blank macro fields, or null when the
  /// macros are there.
  final String? message;
}

/// A pack size read from Open Food Facts' free-text `quantity` ("400 ml",
/// "1 kg"), parsed only when it lands cleanly on a catalog [Unit].
///
/// Offered to the form as a ready-made measure ("can = 400 ml"), which the
/// board draws as an **opt-in tick** — this type never writes anything.
@immutable
class DraftPackSize {
  const DraftPackSize(this.amount, this.unit);

  final double amount;
  final Unit unit;

  @override
  bool operator ==(Object other) =>
      other is DraftPackSize && other.amount == amount && other.unit == unit;

  @override
  int get hashCode => Object.hash(amount, unit);

  @override
  String toString() => 'DraftPackSize($amount ${unit.id})';
}

/// A prefilled, unsaved ingredient — the barcode path's only output.
class IngredientDraft {
  const IngredientDraft({
    required this.suggestedName,
    this.source = DraftSource.manual,
    this.barcode,
    this.productName,
    this.brand,
    this.macros,
    this.macrosBasis = MacrosBasis.perG,
    this.macrosGap = DraftMacrosGap.none,
    this.densityGPerMl,
    this.packSize,
  });

  /// The draft a failed or skipped lookup lands on: nothing filled in, but
  /// the scanned [barcode] kept so the form can record what was in hand.
  /// This is the "add it by hand" exit from the not-found state.
  const IngredientDraft.blank({String? barcode})
    : this(suggestedName: '', barcode: barcode);

  /// What to put in the canonical-name field. A *starting point* — the board
  /// is explicit that "the product name is a starting point; yours is the
  /// name your recipes will read". It is [productName] trimmed, falling back
  /// to [brand] and then to the empty string; nothing is re-cased or
  /// re-worded, because a shop's name for a thing is evidence, not a guess.
  final String suggestedName;

  final DraftSource source;

  /// The code this draft came from, present even when the lookup found
  /// nothing (the not-found exit keeps it).
  final String? barcode;

  /// Open Food Facts' `product_name`, verbatim — shown on the result card
  /// beside the name the user is choosing.
  final String? productName;

  /// The first of OFF's comma-separated `brands`. OFF stores a list because
  /// contributors add the parent company too ("Nutella, Ferrero, Yum yum");
  /// only the first is the brand a shopper would name.
  final String? brand;

  /// Per-100 macros in [macrosBasis], or null. All four values or none —
  /// the same all-or-nothing rule [Macros.tryParse] applies to a vocab row,
  /// so a half-filled panel never becomes three real numbers and a zero.
  final Macros? macros;

  /// The basis the panel was read in, carried straight through rather than
  /// converted (7.7: macros are stored as the label reads). A `100ml` panel
  /// gives [MacrosBasis.perMl].
  final MacrosBasis macrosBasis;

  /// Why [macros] is null. [DraftMacrosGap.none] whenever it is not.
  final DraftMacrosGap macrosGap;

  /// Always null from a barcode lookup: Open Food Facts holds no density,
  /// and one is not derivable from a pack size. The field exists so the
  /// form's initial value has somewhere to come from, not so a mapper can
  /// invent it.
  final double? densityGPerMl;

  /// The pack size, when OFF's free-text `quantity` parsed. Null otherwise.
  final DraftPackSize? packSize;

  /// The value for the ingredient row's `source` column (plan 0020 D1:
  /// `off:<barcode>`), or `manual`.
  String get sourceValue => switch (source) {
    DraftSource.barcode when barcode != null => 'off:$barcode',
    DraftSource.barcode || DraftSource.manual => 'manual',
  };

  /// The credit line the form must show beside anything Open Food Facts
  /// supplied. Its database is ODbL; the board has carried this line since
  /// the original "Barcode add" frame. Null for a manual draft.
  String? get attribution =>
      source == DraftSource.barcode ? 'Open Food Facts · ODbL' : null;

  @override
  String toString() =>
      'IngredientDraft($suggestedName, source: $sourceValue, '
      'macros: $macros/${macrosBasis.dbValue}, gap: ${macrosGap.name})';
}
