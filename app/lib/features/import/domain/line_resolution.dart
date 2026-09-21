/// Per-line reconciliation state, and the pure logic that turns a resolved
/// [ReconciliationPayload] into a [CommitPayload]. Pure Dart (invariant 2).
///
/// A [LineResolution] is the user's decision for one flattened line (spec §8).
/// [buildCommit] throws unless every kept line is resolved and valid, so a
/// partial import never reaches PowerSync. A line resolves to an ingredient row
/// that exists or, only when a human taps the offer, to a household recipe; a
/// dropped line is excluded everywhere ([LineResolution.isDropped]).
library;

import '../../../core/text/name_clean.dart';
import '../../../core/units/measure.dart';
import '../../../core/units/units.dart';
import '../../ingredients/domain/allowed_units.dart';
import '../../ingredients/domain/ingredient.dart';
import '../../recipes/domain/recipe.dart';
import 'amount_text.dart';
import 'commit_payload.dart';
import 'line_validation.dart';
import 'reconciliation_payload.dart';
import 'review_groups.dart';

/// One line's resolution. With neither [chosenIngredientId] nor
/// [linkedRecipeId] set, the user still has to act.
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
    this.linkedRecipeId,
    this.linkedRecipeTitle,
    this.quantity,
    this.isCorrection = false,
    this.isDropped = false,
    this.optional = false,
    this.addedAtReview = false,
    this.createdHere = false,
  });

  /// The resolution for a line the review minted. It has no [ReconLine] and no
  /// source text, is matched from the start, and its [lineIndex] is past the
  /// payload's last. Never a correction: there is no printed phrase to alias.
  factory LineResolution.added({
    required int lineIndex,
    required String name,
    String? ingredientId,
    String? recipeId,
    double? quantity,
    String? unit,
    bool optional = false,
  }) => LineResolution(
    lineIndex: lineIndex,
    band: MatchBand.auto,
    ingredientText: name,
    isRange: false,
    unit: unit,
    chosenIngredientId: recipeId == null ? ingredientId : null,
    chosenName: recipeId == null ? name : null,
    linkedRecipeId: recipeId,
    linkedRecipeTitle: recipeId == null ? null : name,
    quantity: quantity,
    optional: optional,
    addedAtReview: true,
  );

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

  /// The household recipe this line was linked to, or null. Set only by a human
  /// tap. A linked line is a component: no ingredient ([linkToRecipe] clears
  /// [chosenIngredientId]) and no `allowed_units` gate.
  final String? linkedRecipeId;

  /// The linked recipe's title, for the chip. Display only — [linkedRecipeId]
  /// is the identity that commits.
  final String? linkedRecipeTitle;

  /// The resolved single quantity. Null is legitimate for a numberless line
  /// ("to taste"); for a [isRange] line, null means "not yet picked".
  final double? quantity;

  /// The user overrode the match (picked a different ingredient than the band
  /// implied), so the raw text is written back as an alias (lane B).
  final bool isCorrection;

  /// The user dropped this line at review. It stays in the list until Save, but
  /// [lineIssues] reports nothing for it, [allResolved] skips it and
  /// [buildCommit] writes no line for it, demoting any step chip that pointed
  /// at it to plain text.
  final bool isDropped;

  /// The line may be left out: seeded from the extractor's flag, toggled on the
  /// card, committed to `recipe_line_item.optional`. Survives a link.
  final bool optional;

  /// The review minted this line; the card says so in place of a source line.
  final bool addedAtReview;

  /// The vocabulary row this line resolved to was created during this review.
  /// Distinct from [addedAtReview]; validity never turns on it. Only the wide
  /// review's work queue reads it.
  final bool createdHere;

  /// Whether this line is a sub-recipe COMPONENT (step 8.6 / D1) rather than
  /// an ingredient line.
  bool get isComponent => linkedRecipeId != null;

  /// What the line is now: its resolved identity, else the page's own words.
  /// Read by the collapsed row, the card heading and the preview alike.
  String get displayName => chosenName ?? linkedRecipeTitle ?? ingredientText;

  /// Whether this line can be committed: an ingredient line needs an ingredient
  /// and, for a range, a picked number; a linked line needs only its amount. A
  /// dropped line is excluded ([isDropped]), not resolved; callers gate on
  /// both.
  bool get isResolved => isComponent
      ? quantity != null
      : chosenIngredientId != null && !(isRange && quantity == null);

  LineResolution copyWith({
    String? chosenIngredientId,
    String? chosenName,
    String? linkedRecipeId,
    String? linkedRecipeTitle,
    double? quantity,
    String? unit,
    String? notes,
    bool? isCorrection,
    bool? isDropped,
    bool? optional,
    bool clearIngredient = false,
    bool clearLink = false,
    bool clearQuantity = false,
    bool clearNotes = false,
    bool? createdHere,
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
    linkedRecipeId: clearLink ? null : (linkedRecipeId ?? this.linkedRecipeId),
    linkedRecipeTitle: clearLink
        ? null
        : (linkedRecipeTitle ?? this.linkedRecipeTitle),
    quantity: clearQuantity ? null : (quantity ?? this.quantity),
    isCorrection: isCorrection ?? this.isCorrection,
    isDropped: isDropped ?? this.isDropped,
    optional: optional ?? this.optional,
    addedAtReview: addedAtReview,
    createdHere: createdHere ?? this.createdHere,
  );

  /// Drops the line from the import — reversible until Save ([undrop]).
  LineResolution drop() => copyWith(isDropped: true);

  /// Puts a dropped line back, exactly as it was: dropping edits nothing else,
  /// so the match, amount and note the user had already set survive.
  LineResolution undrop() => copyWith(isDropped: false);

  /// Resolves the line to an existing ingredient. [correction] marks a user
  /// override, which writes an alias back; accepting the top candidate is not
  /// one. A row created during the review arrives as a correction too.
  LineResolution resolveToIngredient(
    String ingredientId,
    String name, {
    bool correction = false,
    bool created = false,
  }) => copyWith(
    chosenIngredientId: ingredientId,
    chosenName: name,
    isCorrection: correction,
    // The mark follows the row, so re-matching onto an existing row clears it.
    createdHere: created,
    // Matching an ingredient UN-LINKS a component line: exactly one identity
    // (D1's XOR), and re-picking is how a link is undone (D7's rule too).
    clearLink: true,
  );

  /// Links the line to a household recipe, clearing any ingredient match (the
  /// two identities are exclusive). The printed amount and unit are kept.
  LineResolution linkToRecipe(String recipeId, String title) => copyWith(
    linkedRecipeId: recipeId,
    linkedRecipeTitle: title,
    clearIngredient: true,
    // A link is not an ingredient correction — there is no alias to write.
    isCorrection: false,
  );

  /// Marks the line optional, or not — the review card's switch. A fact about
  /// the line, not its amount.
  LineResolution setOptional({required bool optional}) =>
      copyWith(optional: optional);

  /// Un-links the line, back to the plain unmatched text it arrived as —
  /// reversible right up to Save, like every other review decision.
  LineResolution unlink() => copyWith(clearLink: true);

  /// Picks the single [value] for a range (or edits any quantity).
  LineResolution pickQuantity(double value) => copyWith(quantity: value);

  /// Sets the amount from the quantity sheet: [quantity] (null clears it, "to
  /// taste") and, when a chip was picked, the [unit]. A range resolves once a
  /// number is set.
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

/// The stand-in [ReconLine] for a line the review minted: the picked name, no
/// candidates, no flags and an empty printed amount.
ReconLine addedLine(LineResolution r) => ReconLine(
  raw: RawLineItem(ingredientText: r.ingredientText),
  band: r.band,
);

/// The unit string a quantity-sheet [UnitChoice] becomes on a reconciliation
/// line. A [UnitOption] rides its id; a [MeasureOption] rides its label
/// ("clove"), which commit re-resolves to a `measure_id`, degrading to a count
/// if the label no longer names a live measure. With [unitPicked] false the
/// line keeps [currentUnit].
String? sheetChoiceUnit({
  required UnitChoice choice,
  required bool unitPicked,
  required String? currentUnit,
}) {
  if (!unitPicked) return currentUnit;
  return switch (choice) {
    UnitOption(:final unit) => unit.id,
    MeasureOption(:final measure) => measure.label,
    RecipeMeasureOption(:final measure) => notAWordForAnIngredient(measure),
  };
}

/// The measure [unit] names among [measures], or null. A measure rides its
/// label on a resolution ([sheetChoiceUnit]).
Measure? measureNamed(String? unit, List<Measure> measures) {
  if (unit == null || unit.isEmpty) return null;
  for (final m in measures) {
    if (m.label == unit) return m;
  }
  return null;
}

/// Lands a plain-count [resolution] on [ingredient]'s whole measure
/// ([wholeMeasureOf]), as if that chip had been tapped.
///
/// Fires only when a match resolves: on arrival, or on a re-match. A plain
/// count printed `piece` or a bare number ([resolutionIsCount]), or still says
/// the word this rule gave it on the row it is [leaving]. A unit somebody chose
/// or the page printed is never overruled. A row with no whole measure keeps
/// `piece`.
LineResolution landOnWholeMeasure(
  LineResolution resolution, {
  required Ingredient? ingredient,
  required List<Measure> measures,
  Measure? leaving,
}) {
  if (ingredient == null ||
      resolution.isComponent ||
      resolution.chosenIngredientId != ingredient.id) {
    return resolution;
  }
  final onLeaving = leaving != null && resolution.unit == leaving.label;
  if (!onLeaving && !resolutionIsCount(resolution)) return resolution;
  final whole = wholeMeasureOf(ingredient, measures);
  if (whole != null) return resolution.pickUnit(whole.label);
  return onLeaving ? resolution.pickUnit(pieces.id) : resolution;
}

/// [landOnWholeMeasure] over a payload's [resolutions] on arrival, with [vocab]
/// and [measuresById] fetched once for the import.
List<LineResolution> landedOnWholeMeasures(
  List<LineResolution> resolutions, {
  required Map<String, Ingredient> vocab,
  required Map<String, List<Measure>> measuresById,
}) => [
  for (final r in resolutions)
    landOnWholeMeasure(
      r,
      ingredient: vocab[r.chosenIngredientId],
      measures: measuresById[r.chosenIngredientId] ?? const [],
    ),
];

/// The starting resolution for a line. Only a confident `auto` match adopts its
/// top candidate; `suggest` and `none` start unresolved, and a range starts
/// with no picked number. A recipe candidate is never adopted, at any score.
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
    // The extractor's flag is the starting state — a human may untick it at
    // review, and the card keeps showing the raw tag.
    optional: raw.optional,
  );
}

/// The note hidden in a raw amount that is really prose ("(to serve
/// (optional))"). Null unless the line printed no number and no catalog unit.
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

/// [resolutions] as this device's live vocabulary sees them: a line matched to
/// an id not in [liveIngredientIds] (retired since the server answered, or
/// never synced) becomes unmatched. Applied once, in `importValidation`.
List<LineResolution> againstLiveVocabulary(
  List<LineResolution> resolutions, {
  required Set<String> liveIngredientIds,
}) => [
  for (final r in resolutions)
    if (r.chosenIngredientId == null ||
        liveIngredientIds.contains(r.chosenIngredientId))
      r
    else
      r.copyWith(clearIngredient: true),
];

/// Whether every kept line is resolved: the structural half of the commit gate.
/// Dropped lines are skipped.
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

/// Builds the [CommitPayload] from a fully resolved, fully valid
/// reconciliation.
///
/// - Keeps the group structure and every surviving line's flat index (step refs
///   index into it; the repo remaps on write).
/// - Emits an alias correction for every user override of a matched line.
/// - Omits dropped lines, so the repo's remap demotes chips that pointed at
///   them. A commit with no lines left is refused.
/// - A linked line commits as a component: `sub_recipe_id` set, `ingredient_id`
///   null, no measure, valid once its amount is set.
///
/// Throws [StateError] unless every kept line clears [issuesByLine], the
/// [lineIssues] map the Save button also reads (see `importValidation`). Pass
/// null only where the ingredient-backed check cannot run; the structural check
/// still applies.
///
/// [steps] is the edited method, already converted back to line-index refs by
/// `stepsFromDrafts`; omitted, the payload's steps pass through. [sections] is
/// the review's group structure (`review_groups.dart`); omitted, the payload's
/// groups. [header] is the review's header draft; none of it gates Save.
CommitPayload buildCommit(
  ReconciliationPayload payload,
  List<LineResolution> resolutions, {
  required Recipe header,
  required Map<int, List<LineIssue>>? issuesByLine,
  List<Step>? steps,
  List<ReviewGroup>? sections,
}) {
  if (!allResolved(resolutions)) {
    throw StateError('every line must be resolved before commit');
  }
  final kept = keptLines(resolutions);
  if (kept.isEmpty) {
    throw StateError('an import with every line dropped has nothing to save');
  }
  // The asynchronously recomputed map can still carry a dropped line's issues,
  // so gate on kept lines only.
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

  final commitGroups = <CommitGroup>[];
  for (final group in sections ?? initialGroups(payload)) {
    final lines = <CommitLine>[];
    for (final flatIndex in group.lines) {
      final r = byIndex[flatIndex];
      if (r == null) {
        // dropped: no line written, and its index stays unused
        continue;
      }
      if (r.isComponent) {
        // Re-asserted here, not trusted from the view: a linked line needs its
        // amount.
        if (r.quantity == null) {
          throw StateError(
            'linked line ${r.lineIndex} needs an amount before commit',
          );
        }
        if (r.chosenIngredientId != null) {
          throw StateError(
            'line ${r.lineIndex} carries both a recipe link and an ingredient',
          );
        }
      }
      lines.add(
        CommitLine(
          lineIndex: flatIndex,
          ingredientId: r.isComponent ? null : r.chosenIngredientId,
          subRecipeId: r.linkedRecipeId,
          quantity: r.quantity,
          unit: r.unit,
          note: (r.notes?.isEmpty ?? true) ? null : r.notes,
          optional: r.optional,
        ),
      );
    }
    // A section with no surviving lines is not written.
    if (lines.isNotEmpty) {
      commitGroups.add(CommitGroup(name: group.name, lines: lines));
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

  // Both halves of a yield or neither, and a second only over a first, as the
  // `recipe_yield_pair` CHECKs require.
  final yieldQty = header.yieldQty;
  final yieldQty2 = header.yieldQty2;
  final statedYield =
      yieldQty != null && yieldQty > 0 && header.yieldUnit != null;
  final statedSecond =
      statedYield &&
      yieldQty2 != null &&
      yieldQty2 > 0 &&
      header.yieldUnit2 != null;

  return CommitPayload(
    // The backstop for a title field that was never left, as on the editor's
    // own Save.
    title: cleanName(header.title, NameKind.title),
    servingsBase: header.servingsBase,
    servingsRaw: payload.servingsRaw,
    yieldQty: statedYield ? yieldQty : null,
    yieldUnit: statedYield ? header.yieldUnit : null,
    yieldQty2: statedSecond ? yieldQty2 : null,
    yieldUnit2: statedSecond ? header.yieldUnit2 : null,
    cookTimeSeconds: header.cookTimeSeconds,
    totalTimeSeconds: header.totalTimeSeconds,
    keepsForDays: header.keepsForDays,
    freezable: header.freezable,
    freezerDays: header.freezerDays,
    bookId: header.bookId,
    sectionId: header.sectionId,
    // The measure words ride the draft and land with this commit (ADR-0011).
    measures: header.measures,
    groups: commitGroups,
    // The review screen's own method, when it edited one (seam D4); otherwise
    // the payload's, byte-for-byte.
    steps: steps ?? payload.steps,
    corrections: corrections,
  );
}
