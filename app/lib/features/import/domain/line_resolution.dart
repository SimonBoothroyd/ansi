/// Per-line reconciliation state + the pure logic that turns a resolved
/// `ReconciliationPayload` into a `CommitPayload` — PURE DART (invariant 2).
///
/// A `LineResolution` captures the user's decision for one flattened line:
/// which ingredient it resolved to (an existing one, or a create-new stub),
/// and — for a printed **range** — which number the user picked. `none` lines
/// start unresolved; the human resolves them (spec §8). The invariant is
/// enforced at the seam: `buildCommit` throws unless every line is resolved AND
/// valid, so a partial import can never reach PowerSync.
library;

import '../../ingredients/domain/allowed_units.dart';
import '../../ingredients/domain/search_query.dart';
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

  /// Whether this line can be committed: it has an ingredient and, if it was a
  /// range, a picked number.
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
  );

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
    notes: raw.notes,
    chosenIngredientId: adopt ? top.ingredientId : null,
    chosenName: adopt ? top.canonicalName : null,
    quantity: isRange ? null : raw.qty,
  );
}

/// The initial resolution list for the whole payload, in flattened line order.
List<LineResolution> initialResolutions(ReconciliationPayload payload) {
  final lines = payload.flatLines;
  return [
    for (var i = 0; i < lines.length; i++) initialResolution(i, lines[i]),
  ];
}

/// Whether every line in [resolutions] is resolved — the structural half of
/// the commit gate ([buildCommit] also demands unit validity).
bool allResolved(List<LineResolution> resolutions) =>
    resolutions.every((r) => r.isResolved);

/// The confidence floor below which an extracted line is surfaced as shaky —
/// the single source for the recon card's honest-import flags (0014).
const kLowConfidenceFloor = 0.75;

/// Builds the [CommitPayload] from a fully-resolved, fully-valid
/// reconciliation.
///
/// - Coalesces create-new stubs by normalized name — identical no-match lines
///   land on one [CommitStub] (0014's within-import dedupe).
/// - Preserves the payload's group structure and flattened line order (step
///   refs index into it; the repo remaps on write).
/// - Emits an alias correction for every user override of a matched line.
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
  if (issuesByLine != null && !allLinesValid(issuesByLine)) {
    final open = issuesByLine.entries
        .where((e) => e.value.isNotEmpty)
        .map((e) => '${e.key}:${e.value.map((i) => i.name).join('+')}')
        .join(', ');
    throw StateError('every line must be valid before commit — open: $open');
  }
  final byIndex = {for (final r in resolutions) r.lineIndex: r};

  // Coalesce stubs: normalized name → the display name of its first occurrence.
  final stubKeyByIndex = <int, String>{};
  final stubs = <String, CommitStub>{};
  for (final r in resolutions) {
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
      final r = byIndex[flatIndex]!;
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
    groups.add(CommitGroup(name: group.name, lines: lines));
  }

  final corrections = [
    for (final r in resolutions)
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
