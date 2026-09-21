/// The receipt review as one map. Pure Dart (invariant 2).
///
/// The header's count, each card's flag, the join card and the Save label all
/// read [ReceiptReviewMap], so they cannot disagree. A matched food line with
/// no pack is kept in the total but is not a price, and holds Save. The join
/// (lines against the printed subtotal) is a flag, never a gate. Confirming a
/// match writes no alias; what carries between shops is the pack ([landPack])
/// and the server-recalled match ([ReceiptLineDraft.remembered]), both keyed by
/// the printed name.
library;

import 'package:meta/meta.dart';

import '../../../core/money.dart';
import '../../../core/result/result.dart';
import '../../../core/units/macros.dart';
import '../../../core/units/measure.dart';
import '../../../core/units/number_format.dart';
import '../../../core/units/units.dart';
import '../../ingredients/domain/allowed_units.dart';
import '../../ingredients/domain/ingredient.dart';
import '../../ingredients/domain/price.dart';
import 'receipt_payload.dart';

/// Why one line still needs the person.
enum ReceiptLineIssue {
  /// Food, and nobody has said what it is.
  unmatched,

  /// The reader could not make out the figure (`cents: 0` plus the model's
  /// doubt). Not a free line: it holds Save until somebody reads it off the
  /// paper.
  amountMissing,

  /// Matched food whose row neither sells by weight here nor has a pack: the
  /// cents bought something nobody has stated the size of.
  packMissing,
}

/// The `⚠` label a card wears, in the order the gate checks them — the same
/// shape the recipe review's `attentionLabel` has.
String? receiptAttentionLabel(List<ReceiptLineIssue> issues) {
  if (issues.contains(ReceiptLineIssue.unmatched)) return 'Match an ingredient';
  if (issues.contains(ReceiptLineIssue.amountMissing)) {
    return 'Set the amount';
  }
  if (issues.contains(ReceiptLineIssue.packMissing)) {
    return 'Say what the pack is';
  }
  return null;
}

/// One line of the receipt as the review holds it: what the paper printed and
/// what the person has said about it. Immutable.
@immutable
class ReceiptLineDraft {
  const ReceiptLineDraft({
    required this.index,
    required this.printedText,
    required this.cents,
    required this.kind,
    this.lineId,
    this.namePrinted,
    this.count = 1,
    this.discountCents = 0,
    this.weight,
    this.ingredientId,
    this.ingredientName,
    this.packBasisAmount,
    this.packAmount,
    this.packUnit,
    this.measureId,
    this.packLabel,
    this.keepAsMeasure,
    this.suggestions = const [],
    this.lowConfidence = false,
    this.remembered = false,
    this.photo = 0,
    this.dropped = false,
  });

  /// The line's position in the joined strip — its identity, because two
  /// lines of a receipt print identically when two of a thing were bought.
  final int index;

  /// The stored row behind this line on a saved receipt, so Save updates it.
  /// Null on a fresh scan.
  final String? lineId;

  final String printedText;

  /// The paper's words for the thing, figures off. See
  /// [ReceiptLineOut.namePrinted].
  final String? namePrinted;
  final int cents;

  /// How many the line rang up (`8 @ $2.99`); one unless the paper said
  /// otherwise. [cents] already covers them all, so the price is [cents] over
  /// `count × packBasisAmount`.
  final int count;
  final int discountCents;

  /// What the line is NOW — a folded line reads [ReceiptKind.notFood].
  final ReceiptKind kind;

  final ReceiptWeight? weight;

  final String? ingredientId;
  final String? ingredientName;

  /// What the cents bought, in the ingredient's basis unit. The one figure
  /// every price is derived from.
  final double? packBasisAmount;

  /// The pack as it was said — an amount in [packUnit], or a count of
  /// [measureId]'s measure. See `ingredients/domain/price.dart`.
  final double? packAmount;
  final Unit? packUnit;
  final String? measureId;

  /// The measure's own word, for printing. Never stored: the measure's label
  /// is the word, and a second copy of it would drift.
  final String? packLabel;

  /// The word to mint as a measure on this row at Save, or null. The only place
  /// an import mints a measure, and only on a tap.
  final String? keepAsMeasure;

  final List<ReceiptSuggestion> suggestions;
  final bool lowConfidence;

  /// Whether the match arrived from the household's own past answer for these
  /// printed words. The card says so; a match the person changes stops being
  /// remembered.
  final bool remembered;

  final int photo;

  /// Dropped: stays on screen greyed, out of every figure, until Save.
  final bool dropped;

  /// What was handed over for this line.
  int get paidCents => cents - discountCents;

  /// Whether nothing on this line came off the paper: a line added by hand.
  bool get saidByHand => printedText.isEmpty && namePrinted == null;

  /// The card's title: the matched row, else the paper's name for the thing,
  /// else the whole printed line.
  String get displayName =>
      ingredientName ??
      namePrinted ??
      (printedText.isEmpty ? 'a line' : printedText);

  /// Whether this line will be written as a price — food, matched, packed
  /// and paid for. The same four conditions `observationFrom` holds.
  bool get isPrice =>
      !dropped &&
      kind.isFood &&
      ingredientId != null &&
      (packBasisAmount ?? 0) > 0 &&
      paidCents > 0;

  /// This line with the figure a person read off the paper. Separate from
  /// [copyWith] so correcting a transcription reads as such at the call site.
  ReceiptLineDraft withCents(int cents) => ReceiptLineDraft(
    index: index,
    lineId: lineId,
    printedText: printedText,
    namePrinted: namePrinted,
    cents: cents,
    count: count,
    discountCents: discountCents,
    kind: kind,
    weight: weight,
    ingredientId: ingredientId,
    ingredientName: ingredientName,
    packBasisAmount: packBasisAmount,
    packAmount: packAmount,
    packUnit: packUnit,
    measureId: measureId,
    packLabel: packLabel,
    keepAsMeasure: keepAsMeasure,
    suggestions: suggestions,
    lowConfidence: lowConfidence,
    remembered: remembered,
    photo: photo,
    dropped: dropped,
  );

  ReceiptLineDraft copyWith({
    ReceiptKind? kind,
    int? count,
    String? ingredientId,
    String? ingredientName,
    double? packBasisAmount,
    double? packAmount,
    Unit? packUnit,
    String? measureId,
    String? packLabel,
    String? keepAsMeasure,
    bool? dropped,
    bool clearMatch = false,
    bool clearPack = false,
    bool clearKeepAsMeasure = false,
  }) => ReceiptLineDraft(
    index: index,
    lineId: lineId,
    printedText: printedText,
    namePrinted: namePrinted,
    cents: cents,
    count: count ?? this.count,
    discountCents: discountCents,
    kind: kind ?? this.kind,
    weight: weight,
    ingredientId: clearMatch ? null : (ingredientId ?? this.ingredientId),
    ingredientName: clearMatch ? null : (ingredientName ?? this.ingredientName),
    packBasisAmount: clearPack || clearMatch
        ? null
        : (packBasisAmount ?? this.packBasisAmount),
    packAmount: clearPack || clearMatch
        ? null
        : (packAmount ?? this.packAmount),
    packUnit: clearPack || clearMatch ? null : (packUnit ?? this.packUnit),
    measureId: clearPack || clearMatch ? null : (measureId ?? this.measureId),
    packLabel: clearPack || clearMatch ? null : (packLabel ?? this.packLabel),
    keepAsMeasure: clearKeepAsMeasure || clearMatch
        ? null
        : (keepAsMeasure ?? this.keepAsMeasure),
    suggestions: suggestions,
    lowConfidence: lowConfidence,
    // A match the person changes is THEIRS now, whatever it replaced.
    remembered: remembered && !clearMatch,
    photo: photo,
    dropped: dropped ?? this.dropped,
  );
}

/// The payload's lines as the review first holds them. An `auto` match starts
/// resolved; a `suggest` starts unmatched with its chips offered (ADR-0004).
/// Packs are resolved later by [landPack].
List<ReceiptLineDraft> initialReceiptDrafts(ReceiptPayload payload) => [
  for (final line in payload.lines)
    ReceiptLineDraft(
      index: line.index,
      printedText: line.printedText,
      namePrinted: line.namePrinted,
      cents: line.cents,
      count: line.count,
      discountCents: line.discountCents,
      kind: line.kind,
      weight: line.weight,
      ingredientId: line.match?.auto ?? false ? line.match!.ingredientId : null,
      suggestions: line.suggestions,
      lowConfidence: line.lowConfidence,
      remembered:
          (line.match?.auto ?? false) && (line.match?.remembered ?? false),
      photo: line.photo,
    ),
];

/// A line the reader missed, added by hand and matched to the picked row. Its
/// index is one past the review's highest, since the index is a line's
/// identity. With no printed words it is never a twin ([isSameLineAgain]).
ReceiptLineDraft handAddedLine(
  List<ReceiptLineDraft> drafts, {
  required Ingredient row,
  required int cents,
}) => ReceiptLineDraft(
  index: drafts.fold(-1, (top, d) => d.index > top ? d.index : top) + 1,
  printedText: '',
  cents: cents,
  kind: ReceiptKind.item,
  ingredientId: row.id,
  ingredientName: row.canonicalName,
);

/// [draft] with the pack it can state without asking, from the first of:
///
/// 1. The paper's own weight (`1.32 lb @ $1.99/lb`), through [packInBasis].
/// 2. The pack these printed words were last bought in ([sameName]).
/// 3. The pack this row was last bought in ([last]).
///
/// A carried pack takes its basis figure from the stored observation, never
/// re-derived, so a measure re-weighed since cannot re-price this shop. If its
/// measure is gone or it has no unit, it carries as the basis figure in the
/// basis unit. Otherwise the line keeps no pack and the card asks for one.
ReceiptLineDraft landPack(
  ReceiptLineDraft draft, {
  required Ingredient? ingredient,
  List<Measure> measures = const [],
  PackLastBoughtAs? sameName,
  PriceObservation? last,
}) {
  if (ingredient == null || !draft.kind.isFood) return draft;
  final weight = draft.weight;
  if (weight != null && weight.isPack) {
    final basis = packInBasis(
      ingredient,
      amount: weight.amount,
      choice: UnitOption(weight.unit!),
    );
    if (basis case Ok(:final value)) {
      return draft.copyWith(
        packBasisAmount: value,
        packAmount: weight.amount,
        packUnit: weight.unit,
      );
    }
    return draft;
  }
  final carried = _underTheseWords(draft, ingredient, sameName) ?? last;
  if (carried == null || !(carried.packBasisAmount > 0)) return draft;
  final measureId = carried.measureId;
  final label = measureId == null ? null : _labelOf(measureId, measures);
  final sayable =
      carried.packAmount != null &&
      (measureId == null ? carried.packUnit != null : label != null);
  if (!sayable) {
    // A unit-less amount would be stored as a count of a measure, so words
    // that can no longer be said fall back to the basis figure itself.
    return draft
        .copyWith(clearPack: true)
        .copyWith(
          packBasisAmount: carried.packBasisAmount,
          packAmount: carried.packBasisAmount,
          packUnit: ingredient.macrosBasis.baseUnit,
        );
  }
  return draft.copyWith(
    packBasisAmount: carried.packBasisAmount,
    packAmount: carried.packAmount,
    packUnit: carried.packUnit,
    measureId: measureId,
    packLabel: label,
  );
}

/// [sameName]'s pack where it really is the pack these words bought this row,
/// else null so the row's latest price answers. Three refusals:
///
/// - A line with no printed words is filed under nothing.
/// - Words last bought as another row: that pack is not a fact about this one.
/// - A zero pack (`observationFrom` should already gate it) must not swallow
///   the row's own latest price.
PriceObservation? _underTheseWords(
  ReceiptLineDraft draft,
  Ingredient ingredient,
  PackLastBoughtAs? sameName,
) {
  if (sameName == null || printedNameKey(draft.namePrinted) == null) {
    return null;
  }
  return sameName.ingredientId == ingredient.id &&
          sameName.pack.packBasisAmount > 0
      ? sameName.pack
      : null;
}

String? _labelOf(String measureId, List<Measure> measures) {
  for (final m in measures) {
    if (m.id == measureId) return m.label;
  }
  return null;
}

/// Whether [other] is [line] again: the same printed words at the same figure,
/// with the same answers so far. A twin already answered differently, a dropped
/// line, and a line sold by weight (its printed weight is its pack) are never
/// twins.
bool isSameLineAgain(ReceiptLineDraft line, ReceiptLineDraft other) =>
    other.index != line.index &&
    !line.dropped &&
    !other.dropped &&
    !(line.weight?.isPack ?? false) &&
    !(other.weight?.isPack ?? false) &&
    line.printedText.isNotEmpty &&
    other.printedText == line.printedText &&
    other.cents == line.cents &&
    // A line that rang up four of the thing is not a line that rang up one,
    // however alike the two print: an answer here would price the other wrong.
    other.count == line.count &&
    other.discountCents == line.discountCents &&
    other.kind == line.kind &&
    other.ingredientId == line.ingredientId &&
    other.packBasisAmount == line.packBasisAmount &&
    other.packAmount == line.packAmount &&
    other.packUnit == line.packUnit &&
    other.measureId == line.measureId &&
    other.keepAsMeasure == line.keepAsMeasure;

/// The indexes of the line at [index] and its twins: the lines one answer
/// answers. Answers (match, pack, `Not food`) ride along; corrections to the
/// paper (a drop, a re-read figure) never do.
Set<int> linesAnsweredWith(List<ReceiptLineDraft> drafts, int index) {
  final line = drafts.where((d) => d.index == index).firstOrNull;
  if (line == null) return {index};
  return {
    index,
    for (final other in drafts)
      if (isSameLineAgain(line, other)) other.index,
  };
}

/// `×6 on this receipt — an answer here answers them all`, or null where the
/// line stands alone.
String? sameLineAgainNote(List<ReceiptLineDraft> drafts, int index) {
  final count = linesAnsweredWith(drafts, index).length;
  return count < 2
      ? null
      : '×$count on this receipt — an answer here answers them all';
}

/// What [draft] still wants. Dropped and non-food lines report nothing.
List<ReceiptLineIssue> receiptLineIssues(ReceiptLineDraft draft) {
  if (draft.dropped || !draft.kind.isFood) return const [];
  return [
    if (draft.ingredientId == null) ReceiptLineIssue.unmatched,
    if (draft.paidCents <= 0)
      ReceiptLineIssue.amountMissing
    // A pack is only owed by a line that HAS a figure to divide.
    else if (draft.ingredientId != null && !((draft.packBasisAmount ?? 0) > 0))
      ReceiptLineIssue.packMissing,
  ];
}

/// The whole review as one value: the flags, the sums and the join.
@immutable
class ReceiptReviewMap {
  const ReceiptReviewMap({
    required this.issuesByIndex,
    required this.keptCount,
    required this.linesCents,
    required this.foldedCents,
    required this.foldedCount,
    required this.taxCents,
    required this.printedSubtotalCents,
    required this.printedTotalCents,
  });

  /// Per line index, what it still wants. A line with nothing outstanding is
  /// absent, so `length` IS the count the header prints.
  final Map<int, List<ReceiptLineIssue>> issuesByIndex;

  /// How many lines are still being kept — everything the drops left.
  final int keptCount;

  /// What the kept lines add up to, **tax excluded** — the figure the printed
  /// subtotal is held against. Non-food lines are in it: they were paid for.
  final int linesCents;

  /// What the folded (non-food) lines come to, and how many there are — the
  /// fold's own heading.
  final int foldedCents;
  final int foldedCount;

  /// What the paper's tax lines come to.
  final int taxCents;

  final int? printedSubtotalCents;
  final int? printedTotalCents;

  /// How many lines still need the person — what Save is gated on.
  int get outstanding => issuesByIndex.length;

  /// What the header counts: outstanding lines, plus one when the join does not
  /// close. Save does not wait for the join.
  int get headerCount => outstanding + (joinCloses ? 0 : 1);

  /// What the paper says the lines should come to: its subtotal, else total
  /// less tax. Null when it printed neither.
  int? get expectedLinesCents =>
      printedSubtotalCents ??
      (printedTotalCents == null ? null : printedTotalCents! - taxCents);

  /// Whether the lines' sum and the paper agree. True when the paper printed
  /// nothing to disagree with: an unprovable claim is not a flag.
  bool get joinCloses =>
      expectedLinesCents == null || expectedLinesCents == linesCents;

  /// By how much they differ, or null when they do not.
  int? get apartCents =>
      joinCloses ? null : (expectedLinesCents! - linesCents).abs();

  /// What the receipt is worth: the paper's total where it printed one, else
  /// the lines plus the tax they did not include.
  int get totalCents => printedTotalCents ?? (linesCents + taxCents);

  /// Whether Save may open: every kept line answered and at least one kept (the
  /// repository refuses an empty receipt).
  bool get canSave => outstanding == 0 && keptCount > 0;
}

/// The map for [drafts] against what the paper printed.
ReceiptReviewMap receiptReviewMap(
  List<ReceiptLineDraft> drafts, {
  int? printedSubtotalCents,
  int? printedTaxCents,
  int? printedTotalCents,
}) {
  final issues = <int, List<ReceiptLineIssue>>{};
  var kept = 0;
  var lines = 0;
  var folded = 0;
  var foldedCount = 0;
  var tax = 0;
  for (final draft in drafts) {
    if (draft.dropped) continue;
    kept++;
    final wants = receiptLineIssues(draft);
    if (wants.isNotEmpty) issues[draft.index] = wants;
    if (draft.kind == ReceiptKind.tax) {
      tax += draft.paidCents;
      continue;
    }
    lines += draft.paidCents;
    if (draft.kind == ReceiptKind.notFood) {
      folded += draft.paidCents;
      foldedCount++;
    }
  }
  return ReceiptReviewMap(
    issuesByIndex: issues,
    keptCount: kept,
    linesCents: lines,
    foldedCents: folded,
    foldedCount: foldedCount,
    // The paper's own tax line wins where it printed one: the lines are what
    // was read, and the printed figure is what was charged.
    taxCents: printedTaxCents ?? tax,
    printedSubtotalCents: printedSubtotalCents,
    printedTotalCents: printedTotalCents,
  );
}

/// `The lines add up to $83.30` — the join card's first line.
String joinSumLine(ReceiptReviewMap map) =>
    'The lines add up to ${formatMoney(map.linesCents)}';

/// The join card's note: the paper agrees, or how far apart the sums are and
/// what to look for.
String joinNote(ReceiptReviewMap map) {
  final expected = map.expectedLinesCents;
  if (expected == null) return 'the receipt printed no subtotal and no total';
  // Said only when the expected figure was derived, not printed on the strip.
  final derived = map.printedSubtotalCents == null;
  if (map.joinCloses) {
    return derived
        ? 'the receipt’s total less tax says the same'
        : 'the receipt says the same';
  }
  final against = derived
      ? ' from the total less tax (${formatMoney(expected)})'
      : '';
  return '${formatMoney(map.apartCents!)} apart$against · Find the join — a '
      'line is missing, doubled or misread';
}

/// `Save receipt · $84.12`, or what is still owed, in the recipe review's
/// `line(s)` spelling. [saved] names the button for a receipt already kept.
String receiptSaveLabel(ReceiptReviewMap map, {bool saved = false}) {
  if (map.canSave) {
    return '${saved ? 'Save changes' : 'Save receipt'} · '
        '${formatMoney(map.totalCents)}';
  }
  // Every line dropped: counting outstanding lines would say zero.
  if (map.keptCount == 0) return 'Nothing left to save';
  return '${map.outstanding} line(s) need you';
}

/// `Not food · 2 · $7.09` — the fold's heading, or null when nothing folded.
String? foldedHeading(ReceiptReviewMap map) => map.foldedCount == 0
    ? null
    : 'Not food · ${map.foldedCount} · ${formatMoney(map.foldedCents)}';

/// `Tax · $0.82`, or null when the paper charged none.
String? taxHeading(ReceiptReviewMap map) =>
    map.taxCents == 0 ? null : 'Tax · ${formatMoney(map.taxCents)}';

/// `8 × block (16 oz) · 66¢ / 100 g`: the count, the pack as said, and the unit
/// price. Null when the line has no pack.
String? packAndUnitPrice(ReceiptLineDraft draft, {required MacrosBasis basis}) {
  final pack = draft.packBasisAmount;
  if (pack == null || !(pack > 0)) return null;
  final per100 = pricePer100(
    paidCents: draft.paidCents,
    packBasisAmount: pack,
    count: draft.count,
    basis: basis,
  );
  final words = packWords(draft, basis: basis);
  final said = words == null ? null : '${countPrefix(draft)}$words';
  return switch (per100) {
    Ok(:final value) =>
      said == null
          ? formatPricePer100(value)
          : '$said · ${formatPricePer100(value)}',
    Err() => said,
  };
}

/// `8 × ` before the pack, nothing for a count of one. Shares [countTimes] with
/// the ingredient page.
String countPrefix(ReceiptLineDraft draft) => countTimes(draft.count);

/// `× 8` — the COUNT chip's own label, beside the PACK chip on the open card.
/// It is drawn whatever the count is: the chip is the door to change it.
String countChipLabel(int count) => '× ${formatAmount(count.toDouble())}';

/// `bag (454 g)`, `1.32 lb`, `482 g`: the pack as it was said. A measure prints
/// its word and weight, unless the word already says its size
/// ([measureWordWithSize]).
String? packWords(ReceiptLineDraft draft, {required MacrosBasis basis}) {
  final label = draft.packLabel;
  if (label != null) {
    final weighed = draft.packBasisAmount;
    return weighed == null
        ? label
        : measureWordWithSize(label, weighed, basis.baseUnit);
  }
  final amount = draft.packAmount;
  if (amount == null) return null;
  final unit = draft.packUnit;
  return unit == null ? formatAmount(amount) : _said(amount, unit);
}

/// An amount in the unit it was said in, through [formatAmountIn].
String _said(double amount, Unit unit) =>
    '${formatAmountIn(amount, unit)} ${unit.label}';

/// `−55¢ off`: the deduction printed under an item, or null.
String? discountWords(ReceiptLineDraft draft) => draft.discountCents == 0
    ? null
    : '−${formatMoney(draft.discountCents)} off';
