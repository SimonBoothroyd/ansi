/// The receipt review as one map — PURE DART (invariant 2).
///
/// Everything the screen says about a scanned receipt is read from here: the
/// header's count, each card's amber flag, the join card, and what Save is
/// called. They read **one** map, so the header can never say three while the
/// button says two.
///
/// Three rules shape it, and each is a refusal rather than a guess
/// (invariant 3):
///
/// * **A line is a price only when it says what the cents bought.** A matched
///   food line with no pack is kept, counted in the receipt's total, and is
///   simply not a price — the card asks for the pack and holds Save.
/// * **The join is a flag, never a refusal.** The lines' sum against the
///   printed subtotal (or, where none printed, the total less tax) is a fact
///   worth showing; a receipt whose join lost a
///   line is still a receipt, and its printed total still stands. It is
///   counted in the header exactly as a line's flag is.
/// * **The vocabulary learns nothing.** A receipt's words are one store's
///   abbreviations, so confirming a match writes no alias and there is no
///   learning path in this folder. What carries between shops is the
///   household's own answers, and neither is a vocabulary word: the **pack**
///   (a matched line with no printed weight opens on the pack its own printed
///   words were last bought in, else the one the row was last bought in), and
///   the **match**, which the server recalls per printed name off this
///   household's own saved receipt lines. Both are filed under the same key —
///   the printed name — because that is what names one product at one shop. A
///   line that arrived on a recalled answer is [ReceiptLineDraft.remembered]
///   and the card says so.
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

  /// The reader could not make out what the line rang up as, and says so
  /// (`cents: 0` with the model's own doubt beside it). A food line with no
  /// figure is **not** a free one: it is a line somebody has to read off the
  /// paper, and until they do it holds Save and drags the join open, which is
  /// exactly what a figure nobody could read should do.
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

/// One line of the receipt as the review holds it: what the paper printed,
/// and what the person has said about it.
///
/// Immutable — every edit produces a new one, so the screen rebuilds from a
/// value rather than from a mutation nobody can see.
@immutable
class ReceiptLineDraft {
  const ReceiptLineDraft({
    required this.index,
    required this.printedText,
    required this.cents,
    required this.kind,
    this.lineId,
    this.namePrinted,
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

  /// The stored row behind this line, when the review is open on a SAVED
  /// receipt — what lets Save update the row rather than write a second one.
  /// Null on every line of a fresh scan.
  final String? lineId;

  final String printedText;

  /// The paper's words for the thing, figures off. See
  /// [ReceiptLineOut.namePrinted].
  final String? namePrinted;
  final int cents;
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

  /// The word to mint as a measure on this row at Save — the *keep as a
  /// measure* toggle's answer. Null when the person left it off, which is the
  /// ordinary case.
  ///
  /// **This is the one place a household's tap mints a measure from an
  /// import.** The pipeline itself mints none, as it never has.
  final String? keepAsMeasure;

  final List<ReceiptSuggestion> suggestions;
  final bool lowConfidence;

  /// Whether this line arrived on the household's OWN past answer for its
  /// printed words rather than on the cascade's reading of them. The card says
  /// so beside the chosen row, because a remembered match is the one kind of
  /// resolved line that can be wrong for a reason a person can see — and
  /// changing it is the fix, since the correction becomes the most recent
  /// answer. A match the person changes is theirs, so it stops being
  /// remembered.
  final bool remembered;

  final int photo;

  /// Dropped here: the line stays on screen, greyed, out of every figure and
  /// out of the count, until Save makes it real — the recipe review's own
  /// posture.
  final bool dropped;

  /// What was handed over for this line.
  int get paidCents => cents - discountCents;

  /// What this line names, for a card's title: the matched row, else the
  /// paper's words for the thing, else the whole printed line. The figures
  /// stay off the title where they can — the card says the money once, in its
  /// own column, and the verbatim line is under it either way.
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

  /// This line with the figure a person read off the paper.
  ///
  /// It is its own method rather than a [copyWith] field because `cents` is
  /// the one thing on a draft that came from the PAPER: changing it is
  /// correcting a transcription, not answering a question, and it should read
  /// that way at the call site.
  ReceiptLineDraft withCents(int cents) => ReceiptLineDraft(
    index: index,
    lineId: lineId,
    printedText: printedText,
    namePrinted: namePrinted,
    cents: cents,
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

/// The payload's lines as the review first holds them.
///
/// An `auto` match starts the line resolved; a `suggest` one starts it
/// unmatched with its chips offered, because a suggestion is an offer and
/// never a resolution (ADR-0004). No pack is resolved here — that needs the
/// vocabulary, and [landPack] does it a line at a time.
List<ReceiptLineDraft> initialReceiptDrafts(ReceiptPayload payload) => [
  for (final line in payload.lines)
    ReceiptLineDraft(
      index: line.index,
      printedText: line.printedText,
      namePrinted: line.namePrinted,
      cents: line.cents,
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

/// [draft] with the pack it can state without asking anybody.
///
/// Three sources, in order, and no fourth:
///
/// 1. **The paper's own weight.** `1.32 lb @ $1.99/lb` says what the cents
///    bought, so the line prices itself — resolved through the row's basis by
///    the same density gate the price sheet uses ([packInBasis]).
/// 2. **The pack these printed words were last bought in** ([sameName]). One
///    store's words name one product: `ORG TRICOLOR QUINOA` is the 16 oz bag
///    from the shop that prints it that way, whatever size the other shop
///    sells. A household alternating two shops would otherwise open on the
///    wrong size every other week.
/// 3. **The pack this row was last bought in** ([last]) — the answer for
///    words this household has not bought under before. A bottle of sriracha
///    is the same bottle this week; entering it once is what keeps the second
///    receipt from asking again.
///
/// At either carry-over step the basis figure comes from the stored
/// observation, **never re-derived**, so a measure re-weighed since cannot
/// re-price this shop.
///
/// A line that reaches none of the three keeps no pack and raises *Say what the
/// pack is*. Nothing is invented at any step.
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
  final label = carried.measureId == null
      ? null
      : _labelOf(carried.measureId!, measures) ?? carried.packLabel;
  return draft.copyWith(
    packBasisAmount: carried.packBasisAmount,
    packAmount: carried.packAmount ?? carried.packBasisAmount,
    packUnit: carried.packUnit,
    measureId: carried.measureId,
    packLabel: label,
  );
}

/// [sameName]'s pack where it really is the pack THESE words bought THIS row,
/// else null and the row's latest price answers instead.
///
/// Two refusals, both of them a name that does not stand for what the caller
/// thinks:
///
/// * **A line with no printed words** — read by a server older than the column
///   — is filed under nothing, so there is nothing of its own to recall.
/// * **Words last bought as another row.** The household has re-pointed them
///   since, and the size of somebody else's pack is not a fact about this one.
/// * **A pack of nothing**, which no read can build (`observationFrom` is the
///   gate) and this refuses anyway: a zero here must not swallow the row's own
///   latest price, which may well be a real pack.
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

/// Whether [other] is [line] again — the same printed words at the same
/// figure, standing exactly where [line] stands now.
///
/// A receipt honestly prints one item six times when six were bought, and
/// every one of them wants the same answer. Three fences keep that from
/// becoming an overwrite:
///
/// * **Standing where it stands.** A twin somebody has already answered
///   differently — matched to another row, packed another way — is no longer
///   the same line, so an answer given here cannot reach it.
/// * **A dropped line is nobody's twin**, in either direction. It is leaving,
///   and a doubled line is dropped precisely because the other one is staying.
/// * **A line sold by weight answers for itself.** Its printed weight IS its
///   pack, so a pack said on one is not a fact about the other, however alike
///   the two read.
bool isSameLineAgain(ReceiptLineDraft line, ReceiptLineDraft other) =>
    other.index != line.index &&
    !line.dropped &&
    !other.dropped &&
    !(line.weight?.isPack ?? false) &&
    !(other.weight?.isPack ?? false) &&
    line.printedText.isNotEmpty &&
    other.printedText == line.printedText &&
    other.cents == line.cents &&
    other.discountCents == line.discountCents &&
    other.kind == line.kind &&
    other.ingredientId == line.ingredientId &&
    other.packBasisAmount == line.packBasisAmount &&
    other.packAmount == line.packAmount &&
    other.packUnit == line.packUnit &&
    other.measureId == line.measureId &&
    other.keepAsMeasure == line.keepAsMeasure;

/// The index of the line at [index] and of every line that is it again — the
/// lines one answer answers. Just [index] where the line stands alone.
///
/// What rides along is an ANSWER: the match, the pack, *Not food*. What never
/// does is a correction to the paper — a dropped line or a re-read figure is
/// about one occurrence, and a doubled line is dropped precisely because its
/// twin is staying.
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
/// line stands alone. Said on the open card BEFORE the answer, so six cards
/// moving at once is what the person was told would happen.
String? sameLineAgainNote(List<ReceiptLineDraft> drafts, int index) {
  final count = linesAnsweredWith(drafts, index).length;
  return count < 2
      ? null
      : '×$count on this receipt — an answer here answers them all';
}

/// What [draft] still wants. A dropped line reports nothing — it is leaving,
/// and a line that is not food is under the fold, where it counts toward the
/// trip and toward nothing else.
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

/// The whole review as one figure: the flags, the sums and the join.
///
/// One value, computed once per rebuild, so the header, the cards, the join
/// card and Save cannot disagree.
@immutable
class ReceiptReviewMap {
  const ReceiptReviewMap({
    required this.issuesByIndex,
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

  /// What the header counts: the lines, **and the join card when it does not
  /// close**. A sum that is a line short is something somebody should look
  /// at, so it is counted; it is not something Save waits for, because the
  /// printed total is the paper's and stands either way.
  int get headerCount => outstanding + (joinCloses ? 0 : 1);

  /// What the paper says the lines should come to: its subtotal, else its
  /// total less the tax — a strip with no subtotal line (Trader Joe's prints
  /// none) still states the figure, one subtraction away. Null only when the
  /// paper printed neither, and then there is nothing to hold the lines
  /// against.
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

  /// Whether Save may open — every kept line answered, and the join is a flag
  /// rather than a gate.
  bool get canSave => outstanding == 0;
}

/// The map for [drafts] against what the paper printed.
ReceiptReviewMap receiptReviewMap(
  List<ReceiptLineDraft> drafts, {
  int? printedSubtotalCents,
  int? printedTaxCents,
  int? printedTotalCents,
}) {
  final issues = <int, List<ReceiptLineIssue>>{};
  var lines = 0;
  var folded = 0;
  var foldedCount = 0;
  var tax = 0;
  for (final draft in drafts) {
    if (draft.dropped) continue;
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

/// What the join card says underneath — the paper agreeing, or how far apart
/// they are and what to look for.
///
/// It is a **flag, never a refusal**: the receipt saves either way, because
/// the printed total is the paper's and stands.
String joinNote(ReceiptReviewMap map) {
  final expected = map.expectedLinesCents;
  if (expected == null) return 'the receipt printed no subtotal and no total';
  // Which of the paper's figures the lines were held against, said only when
  // it is the derived one — a reader checking the join needs to know the
  // number is not printed anywhere on the strip.
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

/// `Save receipt · $84.12`, or what is still owed.
/// The `line(s)` is the recipe review's own spelling, deliberately: the two
/// Save bars answer the same question and a reader moving between them should
/// not meet two grammars for it.
///
/// [saved] is the review open on a receipt already kept: the same button,
/// named for what it then does.
String receiptSaveLabel(ReceiptReviewMap map, {bool saved = false}) =>
    map.canSave
    ? '${saved ? 'Save changes' : 'Save receipt'} · '
          '${formatMoney(map.totalCents)}'
    : '${map.outstanding} line(s) need you';

/// `Not food · 2 · $7.09` — the fold's heading, or null when nothing folded.
String? foldedHeading(ReceiptReviewMap map) => map.foldedCount == 0
    ? null
    : 'Not food · ${map.foldedCount} · ${formatMoney(map.foldedCents)}';

/// `Tax · $0.82`, or null when the paper charged none.
String? taxHeading(ReceiptReviewMap map) =>
    map.taxCents == 0 ? null : 'Tax · ${formatMoney(map.taxCents)}';

/// `bag (454 g) · 77¢ / 100 g` — what a priced card reads under the name.
///
/// The pack in the words it was said in, then the unit price it comes to. A
/// line whose pack nobody has stated has nothing to say here and returns
/// null; the card draws its flag instead.
String? packAndUnitPrice(ReceiptLineDraft draft, {required MacrosBasis basis}) {
  final pack = draft.packBasisAmount;
  if (pack == null || !(pack > 0)) return null;
  final per100 = pricePer100(
    paidCents: draft.paidCents,
    packBasisAmount: pack,
    basis: basis,
  );
  final words = packWords(draft, basis: basis);
  return switch (per100) {
    Ok(:final value) =>
      words == null
          ? formatPricePer100(value)
          : '$words · ${formatPricePer100(value)}',
    Err() => words,
  };
}

/// `bag (454 g)`, `1.32 lb`, `482 g` — the pack as the person or the paper
/// said it.
///
/// A pack named as one of the row's measures prints the word AND what it
/// weighs, because the word alone tells a reader nothing about the figure
/// beside it — unless the word already says its size, which is the house
/// style for two sizes of one container ([measureWordWithSize]). A pack typed
/// as a plain amount already is its own reading.
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

/// `1.32 lb`, `454 g` — an amount printed in the unit it was said in, through
/// the app's one amount rule ([formatAmountIn]: metric reads decimal, every
/// kitchen unit keeps its fractions).
String _said(double amount, Unit unit) =>
    '${formatAmountIn(amount, unit)} ${unit.label}';

/// `−55¢ off` — the deduction printed under an item, said on the same line as
/// what was paid, because what you paid is the price. Null where there was
/// none.
String? discountWords(ReceiptLineDraft draft) => draft.discountCents == 0
    ? null
    : '−${formatMoney(draft.discountCents)} off';
