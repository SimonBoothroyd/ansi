/// What a row costs. Pure Dart.
///
/// A price is cents paid for a stated pack. A paid price is an event, one
/// [ReceiptLine] on a [Receipt] ([PriceObservation]); a hand-typed price is the
/// row's own [BasePrice], on no receipt. Both are a [UnitPrice], and the
/// per-100 figure is derived on read ([pricePer100]), never stored. Which one a
/// cost reads is `cost_price.dart`'s one rule.
library;

import 'package:meta/meta.dart';

import '../../../core/money.dart';
import '../../../core/result/result.dart';
import '../../../core/units/macros.dart';
import '../../../core/units/measure.dart';
import '../../../core/units/number_format.dart';
import '../../../core/units/units.dart';
import 'allowed_units.dart';
import 'ingredient.dart';

/// Where a receipt came from.
enum ReceiptSource {
  /// A price typed on an ingredient page by a build that predates base
  /// prices: one line, no photo. Nothing writes one now; it is still read,
  /// as an ordinary receipt.
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

  /// Parses the stored value. An unrecognized kind reads as [notFood], which
  /// can never become a price.
  static ReceiptLineKind fromDb(String? value) {
    for (final kind in ReceiptLineKind.values) {
      if (kind.dbValue == value) return kind;
    }
    return ReceiptLineKind.notFood;
  }
}

/// One shop. The printed totals are kept as printed,
/// never re-derived from the lines.
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

  /// The store as a word. There is no store table.
  final String store;

  /// When the shopping happened — the receipt's own date, never the scan's.
  final DateTime purchasedAt;

  final ReceiptSource source;
  final int? subtotalCents;
  final int? taxCents;
  final int? totalCents;
}

/// [wall] as `purchased_at` stores it: the wall time, marked `Z`.
///
/// The wall components are written unconverted so a price reads back as the
/// same day on every device. [receiptInstant] reads it back unchanged.
String receiptStamp(DateTime wall) => DateTime.utc(
  wall.year,
  wall.month,
  wall.day,
  wall.hour,
  wall.minute,
  wall.second,
).toIso8601String();

/// A stored `purchased_at` as an instant.
///
/// The column is TEXT and its format differs by writer (`…T…Z` from this
/// client, `… …Z` from Postgres). A value with no zone marker is read as UTC,
/// not in the device's zone. An unparseable value falls back to the epoch and
/// sorts last.
DateTime receiptInstant(Object? raw) {
  final text = (raw as String? ?? '').trim();
  final parsed = DateTime.tryParse(text);
  if (parsed == null) return DateTime.utc(1970);
  return parsed.isUtc
      ? parsed
      : DateTime.tryParse('${text}Z') ?? parsed.toUtc();
}

/// One line of a receipt. Only a [ReceiptLineKind.item] line that names an
/// ingredient and states a pack is a price.
@immutable
class ReceiptLine {
  const ReceiptLine({
    required this.id,
    required this.receiptId,
    required this.cents,
    required this.kind,
    this.ingredientId,
    this.printedText,
    this.count = 1,
    this.discountCents = 0,
    this.packBasisAmount,
    this.packAmount,
    this.packUnit,
    this.measureId,
    this.sortOrder = 0,
  });

  final String id;
  final String receiptId;

  /// The vocabulary row this line is about. Null on a non-food line and on one
  /// whose ingredient was retired (the server detaches it).
  final String? ingredientId;

  /// What the paper said, verbatim. Null on a hand-typed price: nothing
  /// printed it, and the ingredient names the line.
  final String? printedText;

  /// What the line rang up as, as printed. A [ReceiptLineKind.fee] may be
  /// negative — an unattached discount kept as its own line.
  final int cents;

  /// How many of the thing this line rang up (`8 @ $2.99`); 1 unless the paper
  /// said otherwise, and more only on an [ReceiptLineKind.item] line.
  ///
  /// [cents] already covers them all. What the cents bought is `count ×
  /// packBasisAmount`.
  final int count;

  /// The deduction printed under the item, kept beside [cents] rather than
  /// subtracted into it. What was paid is [paidCents].
  final int discountCents;

  final ReceiptLineKind kind;

  /// What ONE pack holds, in the ingredient's basis unit (g or ml). Null where
  /// nobody has stated the pack; the line is then not a price. Every derived
  /// figure comes from this, never from [packAmount].
  final double? packBasisAmount;

  /// The pack as entered: an amount in [packUnit], or, with [packUnit] null and
  /// [measureId] set, a count of that measure. Null when no pack was stated.
  final double? packAmount;

  /// The catalog unit [packAmount] is said in, or null when the pack was
  /// tapped as one of the row's measures (whose label is then the word).
  final Unit? packUnit;

  /// The measure the pack was named as ("bag"). A label only: [packBasisAmount]
  /// is the number, so re-weighing the measure does not re-price a past shop.
  final String? measureId;

  final int sortOrder;

  /// What was paid for this line: the printed figure less the printed
  /// deduction. Prices derive from this.
  int get paidCents => cents - discountCents;
}

/// What a cost can be read at: cents paid for a stated pack, per unit of the
/// row's basis. Either a price paid on a receipt ([PriceObservation]) or the
/// row's own base price ([BasePrice]); `costPriceOf` says which one a cost
/// reads.
@immutable
sealed class UnitPrice {
  const UnitPrice();

  /// Identifies this price among every other, so two readings of the same one
  /// compare equal: a receipt line's id, or the row's for a base price.
  String get key;

  /// What was paid for [count] packs.
  int get paidCents;

  /// What ONE pack is, in [basis]'s own unit. Every derived figure comes from
  /// this, never from [packAmount].
  double get packBasisAmount;

  /// How many packs [paidCents] bought; always 1 on a base price.
  int get count;

  /// The row's basis at the time this was read.
  MacrosBasis get basis;

  /// The pack as entered: an amount in [packUnit], or, with [packUnit] null
  /// and [measureId] set, a count of that measure.
  double? get packAmount;

  /// The catalog unit [packAmount] is said in, or null for a count of a
  /// measure.
  Unit? get packUnit;

  /// The measure the pack was tapped as. Kept even when it has since been
  /// deleted.
  String? get measureId;

  /// The pack's own word ("bag"). Null for a plain amount, and when the
  /// measure has since been deleted.
  String? get packLabel;

  /// The day the figure dates from: the receipt's own, or when a base price
  /// was last set. A recipe's `prices from` reads it.
  DateTime get asOf;

  /// What this price says per 100 of the row's basis unit, or a typed refusal
  /// — see [pricePer100].
  Result<PricePer100> get per100 => pricePer100(
    paidCents: paidCents,
    packBasisAmount: packBasisAmount,
    count: count,
    basis: basis,
  );
}

/// One price the household paid: a [ReceiptLine] joined to the [Receipt] that
/// dates and places it.
final class PriceObservation extends UnitPrice {
  const PriceObservation({
    required this.lineId,
    required this.receiptId,
    required this.cents,
    required this.packBasisAmount,
    required this.basis,
    required this.store,
    required this.purchasedAt,
    this.count = 1,
    this.source = ReceiptSource.photo,
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

  /// Positive, or the row would not be an observation: [observationFrom]
  /// refuses to build one otherwise.
  @override
  final double packBasisAmount;

  /// See [ReceiptLine.count]. It multiplies [packBasisAmount] in [per100] and
  /// is never carried to another receipt.
  @override
  final int count;

  @override
  final MacrosBasis basis;

  final String store;
  final DateTime purchasedAt;

  /// What kind of paper is behind this price. Defaults to
  /// [ReceiptSource.photo], the conservative reading.
  final ReceiptSource source;

  @override
  final String? packLabel;

  @override
  final double? packAmount;

  @override
  final Unit? packUnit;

  /// Kept even when the measure has since been deleted, so the pack carries to
  /// the next receipt on the same word.
  @override
  final String? measureId;

  @override
  String get key => lineId;

  /// What was paid — see [ReceiptLine.paidCents].
  @override
  int get paidCents => cents - discountCents;

  @override
  DateTime get asOf => purchasedAt;
}

/// The row's own base price: what the household usually pays for a pack of
/// it, typed on the ingredient page and kept on the row, on no receipt. A cost
/// reads it only when no receipt prices the row (`costPriceOf`).
final class BasePrice extends UnitPrice {
  const BasePrice({
    required this.ingredientId,
    required this.cents,
    required this.packBasisAmount,
    required this.basis,
    required this.setAt,
    this.packAmount,
    this.packUnit,
    this.measureId,
    this.packLabel,
  });

  final String ingredientId;

  /// What was paid for one pack.
  final int cents;

  @override
  final double packBasisAmount;

  @override
  final MacrosBasis basis;

  /// When it was last set, as the wall time it was set at.
  final DateTime setAt;

  @override
  final double? packAmount;

  @override
  final Unit? packUnit;

  @override
  final String? measureId;

  @override
  final String? packLabel;

  @override
  String get key => 'base:$ingredientId';

  @override
  int get paidCents => cents;

  @override
  int get count => 1;

  @override
  DateTime get asOf => setAt;
}

/// The base price a row's stored columns state, or null when they state none
/// or state one nothing could be read from (no pack, nothing paid) — an
/// unreadable base price is unpriced, never a zero.
BasePrice? basePriceFrom({
  required String ingredientId,
  required int? cents,
  required double? packBasisAmount,
  required MacrosBasis basis,
  required DateTime? setAt,
  double? packAmount,
  Unit? packUnit,
  String? measureId,
  String? packLabel,
}) {
  if (cents == null ||
      cents <= 0 ||
      packBasisAmount == null ||
      !(packBasisAmount > 0) ||
      setAt == null) {
    return null;
  }
  return BasePrice(
    ingredientId: ingredientId,
    cents: cents,
    packBasisAmount: packBasisAmount,
    basis: basis,
    setAt: setAt,
    packAmount: packAmount,
    packUnit: packUnit,
    measureId: measureId,
    packLabel: packLabel,
  );
}

/// The key a receipt line's printed words are filed under: trimmed and
/// upper-cased. It mirrors the server's recall key
/// (`_shared/receipt_memory.ts`). Null when the words are empty or absent.
String? printedNameKey(String? namePrinted) {
  final trimmed = (namePrinted ?? '').trim();
  return trimmed.isEmpty ? null : trimmed.toUpperCase();
}

/// The pack one printed name was last bought in, and the vocabulary row it was
/// bought as. The row travels with the pack because a household can re-point a
/// printed name; only a caller holding the line's current match can tell
/// whether the pack still applies.
typedef PackLastBoughtAs = ({String ingredientId, PriceObservation pack});

/// A price per 100 of an ingredient's basis unit (`77¢ / 100 g`). [cents] is
/// fractional: it is derived, and is rounded once, by [formatPricePer100].
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

/// What [paidCents] for [count] packs of [packBasisAmount] of [basis] comes to
/// per 100 of it. Every price in the app is read through this; a base price
/// passes a [count] of 1.
///
/// Refuses with:
///
/// - `price/no_pack` when `count × packBasisAmount` is not positive and finite.
/// - `price/nothing_paid` when nothing was paid. An unpaid line is unpriced,
///   not free.
Result<PricePer100> pricePer100({
  required int paidCents,
  required double packBasisAmount,
  required int count,
  required MacrosBasis basis,
}) {
  final bought = packBasisAmount * count;
  // `!(x > 0)` (rather than `x <= 0`) also catches NaN.
  if (count < 1 || !(bought > 0) || !bought.isFinite) {
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
  return Ok(PricePer100(paidCents * 100 / bought, basis));
}

/// `77¢ / 100 g` — the one figure the whole app reads a price as.
String formatPricePer100(PricePer100 price) =>
    '${formatMoneyRounded(price.cents)} / 100 ${price.basis.dbValue}';

/// `8 × ` in front of a pack the line rang up more than one of, and nothing for
/// a count of one. Shared by the receipt card and the ingredient page.
String countTimes(int count) =>
    count > 1 ? '${formatAmount(count.toDouble())} × ' : '';

/// The pack a person typed, [amount] of [choice], in [ingredient]'s basis unit.
///
/// A measure and a weighed `piece` (ADR-0015) carry their own weight; a unit of
/// the basis family converts by ratio. A unit of the other mass/volume family
/// needs the row's density and refuses with `unit/no_density` without one. An
/// imprecise word refuses as `unit/imprecise`.
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
  // A weighed `piece` bridges as a measure does. A count on a row with no piece
  // weight falls through to [convert] and is refused as `unit/incompatible`.
  final piece = pieceAsMeasure(ingredient);
  return switch (choice) {
    RecipeMeasureOption(:final measure) => notAWordForAnIngredient(measure),
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

/// What a person paid for the pack they typed, per 100 of the row's basis, or
/// the refusal the dock prints. Runs [packInBasis] then [pricePer100], so the
/// first thing wrong is the refusal shown. [count] is how many of that pack the
/// money bought.
Result<PricePer100> priceFromEntry(
  Ingredient ingredient, {
  required int paidCents,
  required double packAmount,
  required UnitChoice packChoice,
  int count = 1,
}) {
  final pack = packInBasis(ingredient, amount: packAmount, choice: packChoice);
  return switch (pack) {
    Err(:final failure) => Err(failure),
    Ok(:final value) => pricePer100(
      paidCents: paidCents,
      packBasisAmount: value,
      count: count,
      basis: ingredient.macrosBasis,
    ),
  };
}

/// The pack as it will be stored. A unit chip stores the amount and the unit's
/// catalog id; a measure chip stores the count and the measure's id, and the
/// label is read from the measure.
typedef PackAsEntered = ({double amount, String? unitId, String? measureId});

PackAsEntered packAsEntered(double amount, UnitChoice choice) =>
    switch (choice) {
      RecipeMeasureOption(:final measure) => notAWordForAnIngredient(measure),
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

/// The chip [price] was entered on, resolved against the row's [measures], for
/// reopening the price sheet. Null when the price kept no entered pack or its
/// measure has been deleted.
UnitChoice? enteredChoice(UnitPrice price, List<Measure> measures) {
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

/// [line] as an observation, or null when it is not a price. A line is a price
/// when it is food, names an ingredient, states a pack and was paid for.
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
    count: line.count,
    basis: basis,
    store: receipt.store,
    purchasedAt: receipt.purchasedAt,
    source: receipt.source,
    packAmount: line.packAmount,
    packUnit: line.packUnit,
    packLabel: packLabel,
    measureId: line.measureId,
  );
}
