/// Per-line reconciliation state + the pure logic that turns a resolved
/// `ReconciliationPayload` into a `CommitPayload` — PURE DART (invariant 2).
///
/// A `LineResolution` captures the user's decision for one flattened line:
/// which ingredient it resolved to (an existing one, or a create-new stub),
/// and — for a printed **range** — which number the user picked. `none` lines
/// start unresolved; the human resolves them (spec §8). The invariant is
/// enforced at the seam: `buildCommit` throws unless every line is resolved AND
/// valid, so a partial import can never reach PowerSync.
///
/// A line the user DROPPED is the one exception, and it is one everywhere at
/// once: it is excluded from validation, from the Save gate, and from the
/// commit — see [LineResolution.isDropped].
library;

import '../../../core/units/units.dart';
import '../../ingredients/domain/allowed_units.dart';
import '../../ingredients/domain/search_query.dart';
import 'amount_text.dart';
import 'commit_payload.dart';
import 'line_validation.dart';
import 'reconciliation_payload.dart';

/// One line's resolution. Exactly one of [chosenIngredientId] /
/// [createStubName] is set once the line is resolved; both null means the user
/// still has to act (the `none` starting state).
class LineResolution {
  const LineResolution({
    required this.lineIndex,
    required this.band,
    required this.ingredientText,
    required this.isRange,
    required this.unit,
    this.notes,
    this.chosenIngredientId,
    this.chosenName,
    this.createStubName,
    this.quantity,
    this.isCorrection = false,
    this.isDropped = false,
  });

  /// Position in the payload's flattened line order — the stable key.
  final int lineIndex;
  final MatchBand band;
  final String ingredientText;

  /// The source printed a range (`qtyLow`/`qtyHigh`), so [quantity] must be
  /// picked before the line is resolved — no silent auto-pick (0014).
  final bool isRange;
  final String? unit;

  /// The line's editable note ("finely chopped", "to serve"). Renamed from
  /// `prep`: the slot carries usage notes too, never the ingredient identity.
  final String? notes;

  /// The chosen existing ingredient, or null.
  final String? chosenIngredientId;
  final String? chosenName;

  /// The name for a create-new stub, or null. Identical names coalesce onto one
  /// stub at commit.
  final String? createStubName;

  /// The resolved single quantity. Null is legitimate for a numberless line
  /// ("to taste"); for a [isRange] line, null means "not yet picked".
  final double? quantity;

  /// The user overrode the match (picked a different ingredient than the band
  /// implied), so the raw text is written back as an alias (lane B).
  final bool isCorrection;

  /// The user dropped this line at review — the recipe prints it, this cook
  /// doesn't want it. The line is not deleted yet: it stays in the list, greyed
  /// out and un-droppable, and only Save makes it real.
  ///
  /// A dropped line is EXCLUDED, not resolved: [lineIssues] reports nothing
  /// for it (so it can never hold "N line(s) need you"), [allResolved] skips
  /// it, and [buildCommit] writes no line for it — demoting any method-step
  /// chip that pointed at it to the chip's own label text.
  final bool isDropped;

  /// Whether this line can be committed: it has an ingredient and, if it was a
  /// range, a picked number. A dropped line is never "resolved" — it is
  /// excluded ([isDropped]); callers gate on both.
  bool get isResolved =>
      (chosenIngredientId != null || createStubName != null) &&
      !(isRange && quantity == null);

  LineResolution copyWith({
    String? chosenIngredientId,
    String? chosenName,
    String? createStubName,
    double? quantity,
    String? unit,
    String? notes,
    bool? isCorrection,
    bool? isDropped,
    bool clearIngredient = false,
    bool clearStub = false,
    bool clearQuantity = false,
    bool clearNotes = false,
  }) => LineResolution(
    lineIndex: lineIndex,
    band: band,
    ingredientText: ingredientText,
    isRange: isRange,
    unit: unit ?? this.unit,
    notes: clearNotes ? null : (notes ?? this.notes),
    chosenIngredientId: clearIngredient
        ? null
        : (chosenIngredientId ?? this.chosenIngredientId),
    chosenName: clearIngredient ? null : (chosenName ?? this.chosenName),
    createStubName: clearStub ? null : (createStubName ?? this.createStubName),
    quantity: clearQuantity ? null : (quantity ?? this.quantity),
    isCorrection: isCorrection ?? this.isCorrection,
    isDropped: isDropped ?? this.isDropped,
  );

  /// Drops the line from the import — reversible until Save ([undrop]).
  LineResolution drop() => copyWith(isDropped: true);

  /// Puts a dropped line back, exactly as it was: dropping edits nothing else,
  /// so the match, amount and note the user had already set survive.
  LineResolution undrop() => copyWith(isDropped: false);

  /// Resolves the line to an existing ingredient. [correction] marks it a user
  /// override (alias write-back); accepting the band's top candidate is not.
  LineResolution resolveToIngredient(
    String ingredientId,
    String name, {
    bool correction = false,
  }) => copyWith(
    chosenIngredientId: ingredientId,
    chosenName: name,
    isCorrection: correction,
    clearStub: true,
  );

  /// Resolves the line to a brand-new stub named [name].
  LineResolution resolveToNewStub(String name) =>
      copyWith(createStubName: name.trim(), clearIngredient: true);

  /// Picks the single [value] for a range (or edits any quantity).
  LineResolution pickQuantity(double value) => copyWith(quantity: value);

  /// Sets the amount from the tap-to-edit quantity + unit sheet (v3): both the
  /// picked [quantity] (null clears it — "to taste") and, when the user picked
  /// a unit chip, the [unit]. A range resolves the moment a number is set here,
  /// exactly like an explicit endpoint pick.
  LineResolution setAmount({double? quantity, String? unit}) =>
      copyWith(quantity: quantity, clearQuantity: quantity == null, unit: unit);

  /// Picks a unit from the inline unit-suggestion chips, leaving the quantity
  /// untouched (unit resolution is independent of the amount — round-3 #4).
  LineResolution pickUnit(String unit) => copyWith(unit: unit);

  /// Sets the line's note (blank/whitespace clears it).
  LineResolution setNotes(String? notes) {
    final trimmed = notes?.trim();
    return (trimmed == null || trimmed.isEmpty)
        ? copyWith(clearNotes: true)
        : copyWith(notes: trimmed);
  }
}

/// The unit string a [UnitChoice] picked in the quantity sheet resolves to on a
/// reconciliation line. A catalog [UnitOption] rides its own id; a
/// [MeasureOption] rides its LABEL ("clove", "can") — the honest measure word,
/// rather than silently degrading the pick to "piece" (the round-1 UX bug:
/// tapping the `clove` chip left the line reading `piece`). Commit re-resolves
/// that label back to the ingredient's `ingredient_measure.id`, persisting it
/// as a `measure_id` FK (migration 0009); a label that no longer names a live
/// measure still degrades to an honest count. When no chip was tapped
/// ([unitPicked] false) the line keeps [currentUnit].
String? sheetChoiceUnit({
  required UnitChoice choice,
  required bool unitPicked,
  required String? currentUnit,
}) {
  if (!unitPicked) return currentUnit;
  return switch (choice) {
    UnitOption(:final unit) => unit.id,
    MeasureOption(:final measure) => measure.label,
  };
}

/// The starting resolution for a line: only a confident `auto` match adopts its
/// top candidate (clean on arrival). `suggest` starts UNRESOLVED so its
/// candidates surface as "did you mean" for the user to confirm — a suggestion
/// the user never saw is not a match (owner refinement). `none` starts
/// unresolved too. A range starts with no picked number regardless of band.
LineResolution initialResolution(int lineIndex, ReconLine line) {
  final raw = line.raw;
  final isRange = raw.qtyLow != null || raw.qtyHigh != null;
  final top = line.candidates.isNotEmpty ? line.candidates.first : null;
  final adopt = line.band == MatchBand.auto && top != null;
  return LineResolution(
    lineIndex: lineIndex,
    band: line.band,
    ingredientText: raw.ingredientText,
    isRange: isRange,
    unit: raw.unit,
    notes: (raw.notes?.trim().isNotEmpty ?? false)
        ? raw.notes
        : noteFromRawAmount(raw),
    chosenIngredientId: adopt ? top.ingredientId : null,
    chosenName: adopt ? top.canonicalName : null,
    quantity: isRange ? null : raw.qty,
  );
}

/// The note a line's RAW AMOUNT carries when that amount is really prose — an
/// extractor filing "(to serve (optional))" in the amount field (owner call:
/// the raw parenthetical routes to NOTES, never the amount slot). Null unless
/// the line printed no number and no catalog unit; an amount the editor can
/// actually render stays in the amount slot, untouched.
String? noteFromRawAmount(RawLineItem raw) {
  if (raw.qty != null || raw.qtyLow != null || raw.qtyHigh != null) return null;
  final unit = raw.unit;
  if (unit != null && unit.isNotEmpty && unitById(unit) != null) return null;
  if (!isProseAmount(raw.rawAmount)) return null;
  return amountAsNote(raw.rawAmount);
}

/// The initial resolution list for the whole payload, in flattened line order.
List<LineResolution> initialResolutions(ReconciliationPayload payload) {
  final lines = payload.flatLines;
  return [
    for (var i = 0; i < lines.length; i++) initialResolution(i, lines[i]),
  ];
}

/// Whether every line in [resolutions] is resolved — the structural half of
/// the commit gate ([buildCommit] also demands unit validity). A DROPPED line
/// is excluded rather than required: the user already said what happens to it.
bool allResolved(List<LineResolution> resolutions) =>
    resolutions.every((r) => r.isDropped || r.isResolved);

/// The lines that will actually be written — everything the user did not drop.
List<LineResolution> keptLines(List<LineResolution> resolutions) => [
  for (final r in resolutions)
    if (!r.isDropped) r,
];

/// The confidence floor below which an extracted line is surfaced as shaky —
/// the single source for the recon card's honest-import flags (0014).
const kLowConfidenceFloor = 0.75;

/// Builds the [CommitPayload] from a fully-resolved, fully-valid
/// reconciliation.
///
/// - Coalesces create-new stubs by normalized name — identical no-match lines
///   land on one [CommitStub] (0014's within-import dedupe).
/// - Preserves the payload's group structure and the flattened line INDEX of
///   every surviving line (step refs index into it; the repo remaps on write).
/// - Emits an alias correction for every user override of a matched line.
/// - **Omits every dropped line.** Its index is simply absent, which is what
///   makes the repo's ref remap demote a chip that pointed at it to plain
///   text — the never-dangling-line invariant, enforced here rather than in
///   the view. A commit with nothing left to write is refused.
///
/// Throws [StateError] unless EVERY line clears [issuesByLine] — the
/// never-dangling-line invariant, and unit validity with it, are enforced here
/// rather than hoped for. [issuesByLine] is the per-line [lineIssues] result
/// for the whole import (see `importValidation`); the review screen derives its
/// Save button from the same map, so the button and this gate can never
/// disagree. Pass `null` only where the ingredient-backed unit check genuinely
/// cannot run — the structural resolve check still applies.
CommitPayload buildCommit(
  ReconciliationPayload payload,
  List<LineResolution> resolutions, {
  required double servingsBase,
  required Map<int, List<LineIssue>>? issuesByLine,
}) {
  if (!allResolved(resolutions)) {
    throw StateError('every line must be resolved before commit');
  }
  final kept = keptLines(resolutions);
  if (kept.isEmpty) {
    throw StateError('an import with every line dropped has nothing to save');
  }
  // A dropped line's issues are not the user's problem any more — the map can
  // still carry them (it is recomputed asynchronously), so gate on the kept
  // lines only, exactly as the Save button does.
  final keptIndexes = {for (final r in kept) r.lineIndex};
  if (issuesByLine != null) {
    final open = issuesByLine.entries
        .where((e) => keptIndexes.contains(e.key) && e.value.isNotEmpty)
        .map((e) => '${e.key}:${e.value.map((i) => i.name).join('+')}')
        .join(', ');
    if (open.isNotEmpty) {
      throw StateError('every line must be valid before commit — open: $open');
    }
  }
  final byIndex = {for (final r in kept) r.lineIndex: r};

  // Coalesce stubs: normalized name → the display name of its first occurrence.
  final stubKeyByIndex = <int, String>{};
  final stubs = <String, CommitStub>{};
  for (final r in kept) {
    final name = r.createStubName;
    if (name == null) continue;
    final key = normalizeSearchQuery(name);
    stubs.putIfAbsent(key, () => CommitStub(key: key, name: name));
    stubKeyByIndex[r.lineIndex] = key;
  }

  final groups = <CommitGroup>[];
  var flatIndex = 0;
  for (final group in payload.groups) {
    final lines = <CommitLine>[];
    for (final _ in group.lines) {
      final r = byIndex[flatIndex];
      if (r == null) {
        flatIndex++; // dropped: no line written, and its index stays unused
        continue;
      }
      lines.add(
        CommitLine(
          lineIndex: flatIndex,
          ingredientId: r.chosenIngredientId,
          stubKey: stubKeyByIndex[flatIndex],
          quantity: r.quantity,
          unit: r.unit,
          note: (r.notes?.isEmpty ?? true) ? null : r.notes,
        ),
      );
      flatIndex++;
    }
    // A group whose every line was dropped is not written at all — an empty
    // "To finish" heading on the saved recipe would be a ghost of the drop.
    if (lines.isNotEmpty) {
      groups.add(CommitGroup(name: group.name, lines: lines));
    }
  }

  final corrections = [
    for (final r in kept)
      if (r.isCorrection && r.chosenIngredientId != null)
        CommitCorrection(
          ingredientId: r.chosenIngredientId!,
          aliasText: r.ingredientText,
        ),
  ];

  return CommitPayload(
    title: payload.title,
    servingsBase: servingsBase,
    servingsRaw: payload.servingsRaw,
    cookTimeSeconds: payload.cookTimeSeconds?.lowSeconds,
    totalTimeSeconds: payload.totalTimeSeconds?.lowSeconds,
    groups: groups,
    stubs: stubs.values.toList(),
    steps: payload.steps,
    corrections: corrections,
  );
}
