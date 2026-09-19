/// What `import-receipt` answers with — PURE DART (invariant 2), the Dart
/// mirror of the frozen wire contract.
///
/// It is the receipt twin of `import/domain/reconciliation_payload.dart` and
/// carries the same promise: **the server reads the paper and proposes; it
/// decides nothing.** Every figure here is something the receipt printed or
/// something the match cascade offered, and a line the model could not place
/// arrives flagged rather than guessed (ADR-0004, import spec §4.4).
///
/// Three shapes are worth knowing before reading the fields:
///
/// * **A discount rides beside the line's cents, never inside them.** The
///   paper printed both figures and both are kept; what was PAID is
///   [ReceiptLineOut.paidCents], and that is what a price is derived from.
/// * **A by-weight line carries its own pack.** `1.32 lb @ 1.99/lb` says what
///   the cents bought, so the review asks nothing — [ReceiptLineOut.weight]
///   is the pack, in the unit the paper printed it in.
/// * **A `kind` that is not `item` can never be a price.** Paper towels, the
///   bag fee and the tax line count toward what the trip cost and toward
///   nothing else.
///
/// Decoding is **total and forgiving**: a field this build does not
/// understand is ignored, and a missing one reads as absent rather than as a
/// zero. A payload that cannot be read at all throws, and the reading screen
/// says so — that is the one honest answer to a stream that is not a receipt.
library;

import 'package:meta/meta.dart';

import '../../../core/units/units.dart';

/// One whole receipt, as read off its photos.
@immutable
class ReceiptPayload {
  const ReceiptPayload({
    required this.lines,
    this.storePrinted,
    this.purchasedAtPrinted,
    this.purchasedAt,
    this.subtotalCents,
    this.taxCents,
    this.totalCents,
    this.linesSumCents = 0,
    this.photoJoins = const [],
    this.notes = const [],
  });

  factory ReceiptPayload.fromJson(Map<String, Object?> json) {
    final printed = _object(json['printed']);
    return ReceiptPayload(
      storePrinted: _text(json['store_printed']),
      purchasedAtPrinted: _text(json['purchased_at_printed']),
      // The receipt's own wall time, with no zone on it: the paper says when
      // the shop happened where the shop happened, and re-reading that in the
      // device's zone would file a late-evening shop on the wrong day.
      purchasedAt: _wallTime(_text(json['purchased_at'])),
      subtotalCents: _cents(printed['subtotal_cents']),
      taxCents: _cents(printed['tax_cents']),
      totalCents: _cents(printed['total_cents']),
      linesSumCents: _cents(json['lines_sum_cents']) ?? 0,
      lines: [
        for (final (index, line) in _list(json['lines']).indexed)
          ReceiptLineOut.fromJson(_object(line), fallbackIndex: index),
      ],
      photoJoins: [
        for (final join in _list(json['photos_joined']))
          ReceiptPhotoJoin.fromJson(_object(join)),
      ],
      notes: [
        for (final note in _list(json['notes']))
          if (_text(note) case final text?) text,
      ],
    );
  }

  /// The store as the header printed it — `TRADER JOE'S #135`. It is not the
  /// household's word for the shop: the review offers the chips and this sits
  /// under them as the paper's own line.
  final String? storePrinted;

  /// The date and time as printed, verbatim, for the same reason.
  final String? purchasedAtPrinted;

  /// The shop's own moment, as **local wall time with no zone**. Null when the
  /// paper printed nothing readable, and the review then asks.
  final DateTime? purchasedAt;

  final int? subtotalCents;
  final int? taxCents;
  final int? totalCents;

  /// What the server made the lines add up to. The review recomputes it from
  /// the lines it actually holds ([ReceiptPayload] is a proposal, and lines
  /// get dropped), so this is a cross-check rather than the figure on screen.
  final int linesSumCents;

  final List<ReceiptLineOut> lines;

  /// Where one photo was joined to the next, by position — never by item
  /// identity, because a receipt honestly prints the same item twice when two
  /// were bought.
  final List<ReceiptPhotoJoin> photoJoins;

  /// What the reader could not read, in its own words — drawn at the top of
  /// the review exactly as an import's parse warnings are.
  final List<String> notes;
}

/// One printed line.
@immutable
class ReceiptLineOut {
  const ReceiptLineOut({
    required this.index,
    required this.printedText,
    required this.cents,
    required this.kind,
    this.namePrinted,
    this.discountCents = 0,
    this.weight,
    this.match,
    this.suggestions = const [],
    this.lowConfidence = false,
    this.photo = 0,
  });

  factory ReceiptLineOut.fromJson(
    Map<String, Object?> json, {
    required int fallbackIndex,
  }) => ReceiptLineOut(
    index: _cents(json['index']) ?? fallbackIndex,
    printedText: _text(json['printed_text']) ?? '',
    namePrinted: _text(json['name_printed']),
    cents: _cents(json['cents']) ?? 0,
    discountCents: _cents(json['discount_cents']) ?? 0,
    kind: ReceiptKind.fromWire(_text(json['kind'])),
    weight: json['weight'] == null
        ? null
        : ReceiptWeight.fromJson(_object(json['weight'])),
    match: json['match'] == null
        ? null
        : ReceiptMatch.fromJson(_object(json['match'])),
    suggestions: [
      for (final s in _list(json['suggestions']))
        ReceiptSuggestion.fromJson(_object(s)),
    ],
    lowConfidence: json['low_confidence'] == true,
    photo: _cents(json['photo']) ?? 0,
  );

  /// The line's position in the joined strip — its identity through the whole
  /// review, because two lines of a receipt can print identically.
  final int index;

  /// What the paper said, verbatim. It is on screen under every card: from a
  /// photograph there is no other way to check what was read.
  final String printedText;

  /// The words that name the thing, with the figures taken off — what an
  /// unmatched card is titled with, because the money already has its own
  /// column. Null from a server that does not send it, and the card then
  /// falls back to [printedText].
  final String? namePrinted;

  /// What the line rang up as, as printed. A [ReceiptKind.fee] may be
  /// negative — a discount the reader could not attach to an item is kept as
  /// its own line so the receipt still adds up.
  final int cents;

  /// The deduction printed under the item, kept beside [cents] rather than
  /// subtracted into it.
  final int discountCents;

  final ReceiptKind kind;

  /// The printed weight and rate, where the line was sold by weight. It IS
  /// the pack, so such a line prices itself and the review asks nothing.
  final ReceiptWeight? weight;

  /// What the cascade resolved this line to, or null. `auto` starts the line
  /// matched; `suggest` starts it unmatched with [suggestions] offered.
  final ReceiptMatch? match;

  /// The did-you-mean chips, in the cascade's own order.
  final List<ReceiptSuggestion> suggestions;

  /// The reader's own doubt about this line — shown as a badge, never acted
  /// on. A low-confidence line is still counted in the total.
  final bool lowConfidence;

  /// Which photo of the strip this line came off, from zero.
  final int photo;

  /// What was handed over for this line: printed less the printed deduction.
  int get paidCents => cents - discountCents;
}

/// A line's printed weight — `1.32 lb @ $1.99/lb`.
///
/// [unit] is a `units.dart` catalog id or null for a word this build's catalog
/// does not carry. A null unit is not a failure: the line keeps its cents and
/// simply cannot price itself, which the card says.
@immutable
class ReceiptWeight {
  const ReceiptWeight({required this.amount, this.unit, this.rateCents = 0});

  factory ReceiptWeight.fromJson(Map<String, Object?> json) => ReceiptWeight(
    amount: _number(json['amount']) ?? 0,
    unit: unitById(_text(json['unit']) ?? ''),
    rateCents: _cents(json['rate_cents']) ?? 0,
  );

  final double amount;
  final Unit? unit;

  /// The printed per-unit rate, kept because the paper printed it. Nothing is
  /// derived from it: what the line cost is [ReceiptLineOut.paidCents], and
  /// `cents ÷ weight` is the figure a price reads.
  final int rateCents;

  /// Whether this weight can stand as a pack — a positive amount in a unit
  /// the catalog knows.
  bool get isPack => unit != null && amount > 0 && amount.isFinite;
}

/// What the cascade resolved a line to.
@immutable
class ReceiptMatch {
  const ReceiptMatch({
    required this.ingredientId,
    this.confidence = 0,
    this.auto = false,
    this.remembered = false,
  });

  factory ReceiptMatch.fromJson(Map<String, Object?> json) => ReceiptMatch(
    ingredientId: _text(json['ingredient_id']) ?? '',
    confidence: _number(json['confidence']) ?? 0,
    auto: _text(json['kind']) == 'auto',
    remembered: json['remembered'] == true,
  );

  final String ingredientId;
  final double confidence;

  /// True for the `auto` band — the line starts resolved. A `suggest` match
  /// is an offer the person taps, never a resolution (ADR-0004).
  final bool auto;

  /// True where this is the HOUSEHOLD's own past answer for these printed
  /// words, recalled from its saved receipt lines, rather than the cascade's
  /// reading of them. It arrives `auto` at confidence 1, because somebody said
  /// it — and the card says so, because the one `auto` that can be wrong for a
  /// reason a person can see is worth seeing.
  ///
  /// It is not a vocabulary word and never becomes one: a receipt's words are
  /// one store's abbreviations.
  final bool remembered;
}

/// One did-you-mean chip.
@immutable
class ReceiptSuggestion {
  const ReceiptSuggestion({
    required this.ingredientId,
    required this.name,
    this.confidence = 0,
  });

  factory ReceiptSuggestion.fromJson(Map<String, Object?> json) =>
      ReceiptSuggestion(
        ingredientId: _text(json['ingredient_id']) ?? '',
        name: _text(json['name']) ?? '',
        confidence: _number(json['confidence']) ?? 0,
      );

  final String ingredientId;
  final String name;
  final double confidence;
}

/// Where photo [from] was joined to photo [to], and how many lines they
/// shared.
@immutable
class ReceiptPhotoJoin {
  const ReceiptPhotoJoin({
    required this.from,
    required this.to,
    this.overlapLines = 0,
  });

  factory ReceiptPhotoJoin.fromJson(Map<String, Object?> json) =>
      ReceiptPhotoJoin(
        from: _cents(json['from']) ?? 0,
        to: _cents(json['to']) ?? 0,
        overlapLines: _cents(json['overlap_lines']) ?? 0,
      );

  final int from;
  final int to;
  final int overlapLines;
}

/// What the paper says a line IS, on the wire.
///
/// It maps onto the stored `receipt_line.kind` (`ingredients/domain/price
/// .dart`) one for one, and a kind this build does not recognise reads as
/// `not_food` — the one reading that can never fabricate a price out of a row
/// nobody here understands.
enum ReceiptKind {
  item('item'),
  notFood('not_food'),
  tax('tax'),
  fee('fee');

  const ReceiptKind(this.wire);

  final String wire;

  static ReceiptKind fromWire(String? value) {
    for (final kind in ReceiptKind.values) {
      if (kind.wire == value) return kind;
    }
    return ReceiptKind.notFood;
  }

  /// Whether a line of this kind can ever name an ingredient or carry a pack.
  bool get isFood => this == ReceiptKind.item;
}

Map<String, Object?> _object(Object? value) =>
    value is Map ? Map<String, Object?>.from(value) : const {};

List<Object?> _list(Object? value) => value is List ? value : const [];

String? _text(Object? value) {
  if (value is! String) return null;
  final trimmed = value.trim();
  return trimmed.isEmpty ? null : trimmed;
}

int? _cents(Object? value) => value is num ? value.round() : null;

double? _number(Object? value) => value is num ? value.toDouble() : null;

/// The receipt's `purchased_at` — an ISO local wall time with no zone.
///
/// It is read as a **plain** [DateTime] (not UTC): the paper's `05:42 PM` is
/// the time at the till, and stamping a zone on it would move a late shop
/// into the next day on one phone and not on the other. The ledger files it
/// by that wall time, which is what the household means by "Sunday's shop".
DateTime? _wallTime(String? text) {
  if (text == null) return null;
  final parsed = DateTime.tryParse(text);
  if (parsed == null) return null;
  return parsed.isUtc
      ? DateTime(
          parsed.year,
          parsed.month,
          parsed.day,
          parsed.hour,
          parsed.minute,
          parsed.second,
        )
      : parsed;
}
