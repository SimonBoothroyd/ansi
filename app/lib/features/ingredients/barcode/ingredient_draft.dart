/// The barcode path's hand-off type. Pure Dart.
///
/// An [IngredientDraft] is a sketch, never a row: an Open Food Facts lookup
/// prefills a draft and never completes an ingredient. Anything the lookup
/// could not establish stays null, never zero, and a human confirms what
/// reaches the row. Plain fields, no Flutter, no repository.
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

/// Why a draft carries no [IngredientDraft.macros]. The message is the sentence
/// the form shows in place of the numbers.
enum DraftMacrosGap {
  /// Macros are present — nothing to explain.
  none(null),

  /// The product is in Open Food Facts but nobody has entered its panel.
  noPanel('Open Food Facts has no nutrition panel for this product.'),

  /// OFF's panel is per serving; the four printed figures ride in
  /// [IngredientDraft.servingPanel]. OFF's `serving_size` is free text and is
  /// never parsed: the numeric `serving_quantity` prefills the serving row when
  /// present, else the host asks.
  perServingPanel(
    'Open Food Facts holds this panel per serving, not per 100 — type the '
    'serving weight from the pack and the row stores per 100.',
  );

  const DraftMacrosGap(this.message);

  /// The sentence to show under the blank macro fields, or null when the
  /// macros are there.
  final String? message;
}

/// A pack size read from Open Food Facts' free-text `quantity` ("400 ml", "1
/// kg"), parsed only when it lands cleanly on a catalog [Unit]. Offered to the
/// form as an opt-in measure ("can = 400 ml"); this type writes nothing.
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

/// The serving a per-100 label also prints ("0.25 cup (28 g)"), read off OFF's
/// free-text `serving_size`. Not the panel's basis and never a density:
/// [amount] and [unit] convert into the row's basis through the catalog alone.
/// The host seeds the row's `serving` measure from it.
@immutable
class DraftServing {
  const DraftServing({
    required this.amount,
    required this.unit,
    this.printedText,
    this.printed,
  });

  final double amount;

  /// A catalog unit in the panel's own family: a mass for a per-100 g label, a
  /// volume for per-100 ml. A serving that cannot be said in the basis is not
  /// carried.
  final Unit unit;

  /// OFF's `serving_size` verbatim ("1 Cup (237 mL)") — quoted back in the
  /// line that checks the pack's own arithmetic against the app's.
  final String? printedText;

  /// The label's per-serving figures, when OFF carried all four alongside the
  /// per-100 column. Neither reading is derived from the other.
  final Macros? printed;

  @override
  bool operator ==(Object other) =>
      other is DraftServing &&
      other.amount == amount &&
      other.unit == unit &&
      other.printedText == printedText &&
      other.printed == printed;

  @override
  int get hashCode => Object.hash(amount, unit, printedText, printed);

  @override
  String toString() => 'DraftServing($amount ${unit.id} · $printedText)';
}

/// A nutrition panel as a pack prints it per serving: the four figures
/// verbatim, and what OFF knows about the serving. Never converted here; the
/// form's per-serving mode runs [Macros.per100From].
@immutable
class DraftServingPanel {
  const DraftServingPanel({
    required this.printed,
    this.servingAmount,
    this.servingBasis,
    this.servingSize,
  });

  /// kcal · protein · carb · fat, per serving, as printed. All four or the
  /// panel is not carried at all — [Macros.tryParse]'s rule.
  final Macros printed;

  /// OFF's numeric `serving_quantity`, in [servingBasis]'s base unit. Null
  /// means the person types it from the pack.
  final double? servingAmount;

  /// The basis `serving_quantity_unit` names (g → per-100 g, ml → per-100
  /// ml). Null with [servingAmount] null, or when OFF's unit is neither.
  final MacrosBasis? servingBasis;

  /// OFF's `serving_size` verbatim ("1 Tbsp (14 g)") — shown beside the
  /// serving row as what the pack calls it, never parsed.
  final String? servingSize;

  @override
  bool operator ==(Object other) =>
      other is DraftServingPanel &&
      other.printed == printed &&
      other.servingAmount == servingAmount &&
      other.servingBasis == servingBasis &&
      other.servingSize == servingSize;

  @override
  int get hashCode =>
      Object.hash(printed, servingAmount, servingBasis, servingSize);

  @override
  String toString() =>
      'DraftServingPanel($printed per $servingAmount '
      '${servingBasis?.dbValue ?? '?'} · $servingSize)';
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
    this.servingPanel,
    this.serving,
    this.densityGPerMl,
    this.packSize,
  });

  /// The draft a failed or skipped lookup lands on: nothing filled in, but the
  /// scanned [barcode] kept.
  const IngredientDraft.blank({String? barcode})
    : this(suggestedName: '', barcode: barcode);

  /// What to put in the canonical-name field as a starting point: [productName]
  /// trimmed, falling back to [brand], then empty. Never re-cased or re-worded.
  final String suggestedName;

  final DraftSource source;

  /// The code this draft came from, present even when the lookup found
  /// nothing (the not-found exit keeps it).
  final String? barcode;

  /// Open Food Facts' `product_name`, verbatim — shown on the result card
  /// beside the name the user is choosing.
  final String? productName;

  /// The first of OFF's comma-separated `brands`; contributors append parent
  /// companies after it.
  final String? brand;

  /// Per-100 macros in [macrosBasis], or null. All four values or none, as in
  /// [Macros.tryParse].
  final Macros? macros;

  /// The basis the panel was read in, carried through unconverted. A `100ml`
  /// panel gives [MacrosBasis.perMl].
  final MacrosBasis macrosBasis;

  /// Why [macros] is null. [DraftMacrosGap.none] whenever it is not.
  final DraftMacrosGap macrosGap;

  /// The panel as printed per serving, when [macrosGap] is
  /// [DraftMacrosGap.perServingPanel] and OFF carried all four figures.
  /// [macros] stays null alongside it.
  final DraftServingPanel? servingPanel;

  /// The serving a per-100 panel also printed, when `serving_size` says one in
  /// the panel's family. Null on a per-serving panel, where the serving is
  /// [servingPanel]'s.
  final DraftServing? serving;

  /// Always null from a barcode lookup: Open Food Facts holds no density. The
  /// field gives the form's initial value a source.
  final double? densityGPerMl;

  /// The pack size, when OFF's free-text `quantity` parsed. Null otherwise.
  final DraftPackSize? packSize;

  /// The value for the ingredient row's `source` column (`off:<barcode>`), or
  /// `manual`.
  String get sourceValue => switch (source) {
    DraftSource.barcode when barcode != null => 'off:$barcode',
    DraftSource.barcode || DraftSource.manual => 'manual',
  };

  /// The credit line the form must show beside anything Open Food Facts
  /// supplied (its database is ODbL). Null for a manual draft.
  String? get attribution =>
      source == DraftSource.barcode ? 'Open Food Facts · ODbL' : null;

  @override
  String toString() =>
      'IngredientDraft($suggestedName, source: $sourceValue, '
      'macros: $macros/${macrosBasis.dbValue}, gap: ${macrosGap.name})';
}
