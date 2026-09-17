/// What a row costs, and how the app knows — PURE DART (invariant 2).
///
/// A price is an **event**, not a field: cents paid for a stated pack, at a
/// store, on a day. The household's prices live as `receipt_line` rows
/// (migration 0044), because a shop's receipt is already a list of exactly
/// that, and a price typed by hand on the ingredient page is the same fact
/// with a smaller piece of paper behind it — one `manual` [Receipt], one
/// [ReceiptLine]. One fact, one ledger.
///
/// **The derived figure is never stored.** `77¢ / 100 g` is read off the
/// observation every time it is printed, in the row's own basis unit, so a
/// pack re-weighed or a discount corrected moves every screen at once and
/// nothing has to be re-derived into a column.
///
/// **The pack is kept twice, on purpose.** What the person SAID — `1 lb`, or
/// one `bag` — is what the ledger prints back at them ([PriceObservation
/// .packAmount]), and what it CAME TO in the row's basis unit is what every
/// figure is derived from ([PriceObservation.packBasisAmount]). They answer
/// different questions and must be able to disagree: a household that
/// re-weighs its `bag` from 454 g to 500 g is saying what a bag is today, and
/// last month's $3.49 bought last month's bag. Re-deriving the basis figure
/// from the words would silently re-price a shop that has already happened.
///
/// **The honesty gate is at entry, and it refuses rather than guesses**
/// (invariant 3). A pack is stored in the row's basis unit — grams on a
/// per-100 g row, millilitres on a per-100 ml one — so a person who buys
/// olive oil by the litre on a gram-basis row is asking to cross the
/// mass↔volume boundary, and that crosses only through the row's density.
/// Without one there is no number, so [packInBasis] returns a typed
/// [Failure] and the sheet's Done says why. The same gate the macros use, on
/// the same boundary, refusing for the same reason.
library;

import 'package:meta/meta.dart';

import '../../../core/money.dart';
import '../../../core/result/result.dart';
import '../../../core/units/macros.dart';
import '../../../core/units/measure.dart';
import '../../../core/units/units.dart';
import 'allowed_units.dart';
import 'ingredient.dart';

/// Where a receipt came from.
enum ReceiptSource {
  /// Typed on an ingredient page: one line, no photo, the store as the chip
  /// word and the date as now.
  manual('manual'),

  /// Read off a picture through the import pipeline.
  photo('photo');

  const ReceiptSource(this.dbValue);

  /// The persisted `receipt.source` value.
  final String dbValue;

  /// Parses the stored value; anything unexpected reads as [photo] — a row
  /// this client did not write is not one it typed.
  static ReceiptSource fromDb(String? value) =>
      value == 'manual' ? ReceiptSource.manual : ReceiptSource.photo;
}

/// What one line of a receipt IS — which decides whether it can ever be a
/// price.
enum ReceiptLineKind {
  /// Food. The only kind that names an ingredient or carries a pack, and so
  /// the only kind a price is derived from.
  item('item'),

  /// Paper towels, a bag fee, a bottle deposit. It counts toward what the
  /// trip cost and never toward what anything is worth per gram.
  notFood('not_food'),

  /// The paper's own lines, kept so the receipt adds up.
  tax('tax'),
  fee('fee');

  const ReceiptLineKind(this.dbValue);

  /// The persisted `receipt_line.kind` value.
  final String dbValue;

  /// Parses the stored value; an unrecognized kind reads as [notFood], which
  /// is the one reading that can never fabricate a price out of a row this
  /// client does not understand.
  static ReceiptLineKind fromDb(String? value) {
    for (final kind in ReceiptLineKind.values) {
      if (kind.dbValue == value) return kind;
    }
    return ReceiptLineKind.notFood;
  }
}

/// One shop, or one hand-typed price.
///
/// The printed figures are kept as printed and never re-derived from the
/// lines: the sum of the lines *checked against* [subtotalCents] is the
/// review's reconcile figure, and two numbers that have to be able to
/// disagree cannot be stored as one.
@immutable
class Receipt {
  const Receipt({
    required this.id,
    required this.store,
    required this.purchasedAt,
    required this.source,
    this.subtotalCents,
    this.taxCents,
    this.totalCents,
  });

  final String id;

  /// The store as a word — whatever the household calls it. There is no store
  /// table: what a shop is called is a chip, not an entity with an identity
  /// two devices would have to agree about.
  final String store;

  /// When the shopping happened — the receipt's own date, never the scan's.
  final DateTime purchasedAt;

  final ReceiptSource source;
  final int? subtotalCents;
  final int? taxCents;
  final int? totalCents;
}

/// One line of a receipt.
///
/// A [ReceiptLineKind.item] line that names an ingredient AND states a pack is
/// a price; every other line is kept because the paper is kept whole, and
/// prices nothing.
@immutable
class ReceiptLine {
  const ReceiptLine({
    required this.id,
    required this.receiptId,
    required this.cents,
    required this.kind,
    this.ingredientId,
    this.printedText,
    this.discountCents = 0,
    this.packBasisAmount,
    this.packAmount,
    this.packUnit,
    this.measureId,
    this.sortOrder = 0,
  });

  final String id;
  final String receiptId;

  /// The vocabulary row this line is about, or null — a non-food line, a tax
  /// line, and a line whose ingredient was retired out from under it (the
  /// server detaches it rather than letting it dangle, 0044).
  final String? ingredientId;

  /// What the paper said, verbatim. Null on a hand-typed price: nothing
  /// printed it, and the ingredient names the line.
  final String? printedText;

  /// What the line rang up as, as printed. A [ReceiptLineKind.fee] may be
  /// negative — an unattached discount kept as its own line.
  final int cents;

  /// The deduction printed under the item, kept beside [cents] rather than
  /// subtracted into it, so both printed figures survive. What was **paid** is
  /// [paidCents].
  final int discountCents;

  final ReceiptLineKind kind;

  /// What the cents bought, in the ingredient's basis unit (g or ml). Null
  /// where nobody has said what the pack is, which is an honest state: the
  /// line is kept, and it simply is not a price yet.
  ///
  /// **Every derived figure comes from this one**, never from [packAmount].
  final double? packBasisAmount;

  /// The pack as the person SAID it, read through [packUnit]: an amount in
  /// that unit, or — with [packUnit] null and [measureId] set — a count of
  /// that measure. Null on a line nobody has stated the pack of, and on one
  /// written before the ledger kept the words.
  final double? packAmount;

  /// The catalog unit [packAmount] is said in, or null when the pack was
  /// tapped as one of the row's measures (whose label is then the word).
  final Unit? packUnit;

  /// The row's own word for that pack ("bag"), when the pack was named as a
  /// measure. A LABEL, never the amount — [packBasisAmount] is the number, so
  /// a measure re-weighed later does not silently re-price a shop that has
  /// already happened.
  final String? measureId;

  final int sortOrder;

  /// What was handed over for this line: the printed figure less the printed
  /// deduction. It is the figure a price is derived from, because what you
  /// paid is the price.
  int get paidCents => cents - discountCents;
}

/// One price the household paid, as every reader of a price sees it: a
/// [ReceiptLine] joined to the [Receipt] that dates and places it.
///
/// It is the shape of the fact, not of the table — the ingredient page's
/// *Latest* line, its *Before* rows and (from the cost lane) a recipe's
/// per-line figure all read this and nothing else, so there is one account of
/// what a price is.
@immutable
class PriceObservation {
  const PriceObservation({
    required this.lineId,
    required this.receiptId,
    required this.cents,
    required this.packBasisAmount,
    required this.basis,
    required this.store,
    required this.purchasedAt,
    this.discountCents = 0,
    this.packAmount,
    this.packUnit,
    this.packLabel,
    this.measureId,
  });

  final String lineId;
  final String receiptId;

  /// As printed, before [discountCents] — see [ReceiptLine.cents].
  final int cents;
  final int discountCents;

  /// What the cents bought, in [basis]'s own unit. Positive, or the row would
  /// not be an observation: [observationFrom] refuses to build one otherwise.
  final double packBasisAmount;

  /// The ingredient's basis at the time this was read — the dimension both
  /// [packBasisAmount] and the derived figure are denominated in.
  final MacrosBasis basis;

  final String store;
  final DateTime purchasedAt;

  /// The pack's own word, where the person named one ("bag"). Null for a pack
  /// typed as a plain amount, and null where the measure has since been
  /// deleted — the amount is the fact, the word is how it was said.
  final String? packLabel;

  /// The pack as the person SAID it — see [ReceiptLine.packAmount]. It is what
  /// the ledger PRINTS; [packBasisAmount] is what it is read from, and the two
  /// are deliberately different questions.
  final double? packAmount;

  /// The catalog unit [packAmount] is said in, or null for a count of
  /// [packLabel]'s measure — see [ReceiptLine.packUnit].
  final Unit? packUnit;

  /// The measure the pack was tapped as, still by id, so the sheet reopened on
  /// this line lands on the same chip. Kept even when the measure has been
  /// deleted since and [packLabel] is gone.
  final String? measureId;

  /// What was paid — see [ReceiptLine.paidCents].
  int get paidCents => cents - discountCents;

  /// What this observation says per 100 of the row's basis unit, or a typed
  /// refusal — see [pricePer100].
  Result<PricePer100> get per100 => pricePer100(
    paidCents: paidCents,
    packBasisAmount: packBasisAmount,
    basis: basis,
  );
}

/// A price per 100 of an ingredient's basis unit — `77¢ / 100 g`.
///
/// [cents] is a real number of cents and not an integer: it is derived, not
/// paid, and rounding it before it is printed would put a rounding inside
/// every downstream sum. It is rounded once, at the edge, by
/// [formatPricePer100].
@immutable
class PricePer100 {
  const PricePer100(this.cents, this.basis);

  final double cents;
  final MacrosBasis basis;

  @override
  bool operator ==(Object other) =>
      other is PricePer100 && other.cents == cents && other.basis == basis;

  @override
  int get hashCode => Object.hash(cents, basis);

  @override
  String toString() => 'PricePer100($cents¢ /100 ${basis.dbValue})';
}

/// What [paidCents] for [packBasisAmount] of [basis] comes to per 100 of it.
///
/// Two refusals, and no third (invariant 3 — a refusal beats a number nobody
/// can stand behind):
///
/// - `price/no_pack` when the pack is not a positive finite amount. Dividing
///   by it would fabricate an infinity, and a pack of nothing would price
///   everything at once.
/// - `price/nothing_paid` when nothing was paid. A zero is not a discovery
///   that the food is free — it is a line somebody has not finished — and a
///   recipe reading `$0.00` for it would state a cost the receipt never
///   supported. A free sample is honestly *unpriced*.
Result<PricePer100> pricePer100({
  required int paidCents,
  required double packBasisAmount,
  required MacrosBasis basis,
}) {
  // `!(x > 0)` (rather than `x <= 0`) also catches NaN.
  if (!(packBasisAmount > 0) || !packBasisAmount.isFinite) {
    return const Err(
      Failure('price/no_pack', 'a price needs to say what the cents bought'),
    );
  }
  if (paidCents <= 0) {
    return const Err(
      Failure(
        'price/nothing_paid',
        'a price is what was paid, and nothing was',
      ),
    );
  }
  return Ok(PricePer100(paidCents * 100 / packBasisAmount, basis));
}

/// `77¢ / 100 g` — the one figure the whole app reads a price as.
String formatPricePer100(PricePer100 price) =>
    '${formatMoneyRounded(price.cents)} / 100 ${price.basis.dbValue}';

/// The pack a person typed — [amount] of [choice] — resolved into
/// [ingredient]'s basis unit, which is the only denomination a pack is stored
/// in.
///
/// **This is the honesty gate.** A measure carries its own weight and needs
/// nothing; a `piece` on a row that says what one weighs converts the same way
/// (ADR-0015); a unit of the basis family converts by the ratio table. A unit
/// of the *other* mass/volume family crosses the boundary and therefore needs
/// the row's density — a 500 ml bottle of oil on a per-100 g row is grams only
/// if the row says what a millilitre of it weighs. Without one this returns
/// `unit/no_density` and the sheet refuses Done, naming it, rather than
/// storing a number the row cannot support.
///
/// An imprecise word (`a handful of parsley for $2`) refuses as
/// `unit/imprecise`: it converts to nothing, here as everywhere.
Result<double> packInBasis(
  Ingredient ingredient, {
  required double amount,
  required UnitChoice choice,
}) {
  if (!(amount > 0) || !amount.isFinite) {
    return const Err(
      Failure('price/no_pack', 'a price needs to say what the cents bought'),
    );
  }
  final basis = ingredient.macrosBasis.baseUnit;
  final density = ingredient.densityGPerMl;
  // A weighed `piece` is a measure the row states rather than names, so it
  // bridges exactly as one does. A count on a row that weighs nothing falls
  // through to [convert] and is refused there as `unit/incompatible` — which
  // is the truth about it.
  final piece = pieceAsMeasure(ingredient);
  return switch (choice) {
    MeasureOption(:final measure) => convertMeasure(
      amount,
      measure,
      to: basis,
      densityGPerMl: density,
    ).map((q) => q.amount),
    UnitOption(:final unit)
        when unit.family == UnitFamily.count && piece != null =>
      convertMeasure(
        amount,
        piece,
        to: basis,
        densityGPerMl: density,
      ).map((q) => q.amount),
    UnitOption(:final unit) => convert(
      Quantity(amount, unit),
      to: basis,
      densityGPerMl: density,
    ).map((q) => q.amount),
  };
}

/// The whole of what the price sheet asks, as one pure function: what a person
/// paid, for the pack they typed, comes to *this* per 100 of the row's basis —
/// or refuses, with the reason the dock prints.
///
/// The two halves are [packInBasis] (the density gate) and [pricePer100] (the
/// arithmetic), in that order, so the refusal a person sees is the first thing
/// that was actually wrong.
Result<PricePer100> priceFromEntry(
  Ingredient ingredient, {
  required int paidCents,
  required double packAmount,
  required UnitChoice packChoice,
}) {
  final pack = packInBasis(ingredient, amount: packAmount, choice: packChoice);
  return switch (pack) {
    Err(:final failure) => Err(failure),
    Ok(:final value) => pricePer100(
      paidCents: paidCents,
      packBasisAmount: value,
      basis: ingredient.macrosBasis,
    ),
  };
}

/// The pack as it will be STORED, from the choice the person tapped — the one
/// place the two shapes a pack can take are decided.
///
/// A unit chip stores the amount and the unit's catalog id; a measure chip
/// stores the COUNT and points at the measure, whose own label is the word. So
/// `pack_unit` is what tells a reader which of the two it is holding, and the
/// measure's label is never copied into a second column to drift from.
typedef PackAsEntered = ({double amount, String? unitId, String? measureId});

PackAsEntered packAsEntered(double amount, UnitChoice choice) =>
    switch (choice) {
      MeasureOption(:final measure) => (
        amount: amount,
        unitId: null,
        measureId: measure.id,
      ),
      UnitOption(:final unit) => (
        amount: amount,
        unitId: unit.id,
        measureId: null,
      ),
    };

/// The chip [price] was entered on, resolved against the row's [measures] —
/// what the price sheet reopens a stored line on.
///
/// Null when the line kept no entered pack (a row written before the ledger
/// held the words), or when the measure it named has been deleted since: the
/// caller then opens on its own default rather than on a word that is gone.
UnitChoice? enteredChoice(PriceObservation price, List<Measure> measures) {
  if (price.packAmount == null) return null;
  final unit = price.packUnit;
  if (unit != null) return UnitOption(unit);
  final id = price.measureId;
  if (id == null) return null;
  for (final measure in measures) {
    if (measure.id == id) return MeasureOption(measure);
  }
  return null;
}

/// [line] as an observation, or null where it is not one.
///
/// A line is a price when it is food, names an ingredient, states a pack and
/// was paid for. Everything else is a line of a receipt and nothing more —
/// the tax, the bag fee, the matched row whose pack nobody has said yet — and
/// null is the honest answer for it, not a zero.
PriceObservation? observationFrom(
  ReceiptLine line,
  Receipt receipt, {
  required MacrosBasis basis,
  String? packLabel,
}) {
  final pack = line.packBasisAmount;
  if (line.kind != ReceiptLineKind.item ||
      line.ingredientId == null ||
      pack == null ||
      !(pack > 0) ||
      line.paidCents <= 0) {
    return null;
  }
  return PriceObservation(
    lineId: line.id,
    receiptId: receipt.id,
    cents: line.cents,
    discountCents: line.discountCents,
    packBasisAmount: pack,
    basis: basis,
    store: receipt.store,
    purchasedAt: receipt.purchasedAt,
    packAmount: line.packAmount,
    packUnit: line.packUnit,
    packLabel: packLabel,
    measureId: line.measureId,
  );
}
