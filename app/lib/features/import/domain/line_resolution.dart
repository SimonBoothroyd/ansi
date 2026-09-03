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
///
/// A line can also resolve to a **household recipe** instead of an ingredient
/// (step 8.6 / D6): the server offers a recipe-title candidate, the human taps
/// it, and the line becomes a COMPONENT line. Nothing links itself — the offer
/// is never taken automatically, at any score.
library;

import '../../../core/units/units.dart';
import '../../ingredients/domain/allowed_units.dart';
import '../../ingredients/domain/normalize.dart';
import '../../recipes/domain/recipe.dart';
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
    this.linkedRecipeId,
    this.linkedRecipeTitle,
    this.quantity,
    this.isCorrection = false,
    this.isDropped = false,
    this.unitFromDefault = false,
    this.optional = false,
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

  /// The household recipe this line was LINKED to (step 8.6 / D6), or null.
  ///
  /// Set only by a human tapping the offered chip — never on arrival, at any
  /// score. While it is set the line is a component line: it has no ingredient
  /// ([chosenIngredientId] and [createStubName] are cleared by [linkToRecipe]),
  /// wants no ingredient match, and faces no `allowed_units` gate — admission
  /// is an ingredient concept, and this unit meets the target's yield family
  /// later, at derive time (D2).
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

  /// The user dropped this line at review — the recipe prints it, this cook
  /// doesn't want it. The line is not deleted yet: it stays in the list, greyed
  /// out and un-droppable, and only Save makes it real.
  ///
  /// A dropped line is EXCLUDED, not resolved: [lineIssues] reports nothing
  /// for it (so it can never hold "N line(s) need you"), [allResolved] skips
  /// it, and [buildCommit] writes no line for it — demoting any method-step
  /// chip that pointed at it to the chip's own label text.
  final bool isDropped;

  /// The line's [unit] is the ingredient's curated default measure, spent on
  /// arrival because the source named a number and no thing (seam **D2**).
  ///
  /// **Display only, and never persisted.** The stored line records an
  /// ordinary measure — no `inferred` mark, no provenance, no revert. Those
  /// are a *guess's* apparatus, and this is not a guess: it is shown on the
  /// card at the moment it is applied ("counts as pepper, medium · 119 g"),
  /// beside the chips that change it, so nothing happens behind the user's
  /// back. The flag exists so the card can say that sentence, and so a
  /// re-match knows the word on the line was ours rather than the source's.
  ///
  /// Cleared the moment the user touches the unit ([pickUnit], [setAmount]).
  final bool unitFromDefault;

  /// The recipe says this line may be left out (plan 0025 / D6b) — seeded
  /// from the extractor's raw flag, toggled in the amount sheet at review,
  /// committed to `recipe_line_item.optional`. Always false while the line is
  /// a component ([linkToRecipe] clears it): an optional sub-recipe is a
  /// week-level question, not a line fact.
  final bool optional;

  /// Whether this line is a sub-recipe COMPONENT (step 8.6 / D1) rather than
  /// an ingredient line.
  bool get isComponent => linkedRecipeId != null;

  /// Whether this line can be committed.
  ///
  /// An ingredient line: it has an ingredient and, if it was a range, a picked
  /// number. A LINKED line (D6): its amount is set — no ingredient match is
  /// wanted and none is required, which is the whole point of the offer.
  /// A dropped line is never "resolved" — it is excluded ([isDropped]);
  /// callers gate on both.
  bool get isResolved => isComponent
      ? quantity != null
      : (chosenIngredientId != null || createStubName != null) &&
            !(isRange && quantity == null);

  LineResolution copyWith({
    String? chosenIngredientId,
    String? chosenName,
    String? createStubName,
    String? linkedRecipeId,
    String? linkedRecipeTitle,
    double? quantity,
    String? unit,
    String? notes,
    bool? isCorrection,
    bool? isDropped,
    bool? unitFromDefault,
    bool? optional,
    bool clearIngredient = false,
    bool clearStub = false,
    bool clearLink = false,
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
    linkedRecipeId: clearLink ? null : (linkedRecipeId ?? this.linkedRecipeId),
    linkedRecipeTitle: clearLink
        ? null
        : (linkedRecipeTitle ?? this.linkedRecipeTitle),
    quantity: clearQuantity ? null : (quantity ?? this.quantity),
    isCorrection: isCorrection ?? this.isCorrection,
    isDropped: isDropped ?? this.isDropped,
    unitFromDefault: unitFromDefault ?? this.unitFromDefault,
    optional: optional ?? this.optional,
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
    // Matching an ingredient UN-LINKS a component line: exactly one identity
    // (D1's XOR), and re-picking is how a link is undone (D7's rule too).
    clearLink: true,
  );

  /// Resolves the line to a brand-new stub named [name].
  LineResolution resolveToNewStub(String name) => copyWith(
    createStubName: name.trim(),
    clearIngredient: true,
    clearLink: true,
  );

  /// LINKS the line to a household recipe (step 8.6 / D6): it becomes a
  /// component line, and any ingredient match it carried is cleared — the two
  /// identities are exclusive (D1's XOR), here as in the database.
  ///
  /// The printed amount and unit are kept exactly as they are: "¼ cup" is what
  /// the page said, and the review screen's source-line honesty is the reason
  /// components are denominated in printed units at all.
  LineResolution linkToRecipe(String recipeId, String title) => copyWith(
    linkedRecipeId: recipeId,
    linkedRecipeTitle: title,
    clearIngredient: true,
    clearStub: true,
    // A link is not an ingredient correction — there is no alias to write.
    isCorrection: false,
    // Nor is a component line ever optional (D6b's stated scope) — the raw
    // flag was about an ingredient, and the sheet does not offer the switch
    // on a component.
    optional: false,
  );

  /// Marks the line optional, or not — the amount sheet's switch at review
  /// (plan 0025 / D6a). A fact about the line, not its amount.
  LineResolution setOptional({required bool optional}) =>
      copyWith(optional: optional);

  /// Un-links the line, back to the plain unmatched text it arrived as —
  /// reversible right up to Save, like every other review decision.
  LineResolution unlink() => copyWith(clearLink: true);

  /// Picks the single [value] for a range (or edits any quantity).
  LineResolution pickQuantity(double value) => copyWith(quantity: value);

  /// Sets the amount from the tap-to-edit quantity + unit sheet (v3): both the
  /// picked [quantity] (null clears it — "to taste") and, when the user picked
  /// a unit chip, the [unit]. A range resolves the moment a number is set here,
  /// exactly like an explicit endpoint pick.
  LineResolution setAmount({double? quantity, String? unit}) => copyWith(
    quantity: quantity,
    clearQuantity: quantity == null,
    unit: unit,
    // A unit the user set in the sheet is theirs; the card stops saying the
    // default answered this line (D2).
    unitFromDefault: unit == null ? null : false,
  );

  /// Picks a unit from the inline unit-suggestion chips, leaving the quantity
  /// untouched (unit resolution is independent of the amount — round-3 #4).
  LineResolution pickUnit(String unit) =>
      copyWith(unit: unit, unitFromDefault: false);

  /// Spends the ingredient's curated default measure on this line: the same
  /// write [pickUnit] makes, marked as ours rather than the user's (seam D2).
  ///
  /// The label is what a tapped chip would have written, so `lineIssues`,
  /// `sheetChoiceUnit` and `buildCommit` see nothing new — the card is clean
  /// for the ordinary reason, and the saved row is an ordinary measure line.
  LineResolution applyDefaultUnit(String label) =>
      copyWith(unit: label, unitFromDefault: true);

  /// Puts the SOURCE's own word back on a line whose unit we had supplied —
  /// what a re-match calls before the new ingredient's default is spent.
  /// Without it a pepper's `pepper, medium` would follow the line onto
  /// broccoli and be flagged there as if the recipe had printed it.
  LineResolution restorePrintedUnit(String? printed) => LineResolution(
    lineIndex: lineIndex,
    band: band,
    ingredientText: ingredientText,
    isRange: isRange,
    unit: printed,
    notes: notes,
    chosenIngredientId: chosenIngredientId,
    chosenName: chosenName,
    createStubName: createStubName,
    linkedRecipeId: linkedRecipeId,
    linkedRecipeTitle: linkedRecipeTitle,
    quantity: quantity,
    isCorrection: isCorrection,
    isDropped: isDropped,
    optional: optional,
  );

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
///
/// A RECIPE candidate is never adopted here, at any score (8.6 / D6, the whole
/// step's non-goal): the chip is an offer, and a line nobody tapped commits as
/// the plain text it always did.
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
    // The extractor's flag is the starting state (plan 0025 #6) — a human
    // may untick it at review, and the card keeps showing the raw tag.
    optional: raw.optional,
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
///
/// A LINKED line (8.6 / D6) commits as a component: `sub_recipe_id` set,
/// `ingredient_id` null, and no measure — the D1 XOR and its measure fence,
/// asserted HERE as well as by migration 0017's CHECKs, because a payload that
/// only the database refuses is a crash rather than a rule. Its own gate is
/// the one the board draws: valid the moment its amount is set, with no
/// ingredient match and no `allowed_units` admission (that is an ingredient
/// concept; the unit meets the target's yield family at derive time).
///
/// [steps] is the method the review screen edited (seam D4), already converted
/// back to line-index refs by `stepsFromDrafts`. Omitted — the common path,
/// where nobody touched the method — the payload's own steps ride through
/// unchanged.
///
/// [header] is the review's header draft (plan 0025 #4): title, serves,
/// makes in up to two denominations, times, shelf life and filing, as the
/// shared header form left them. Every header column the editor's save
/// writes is read off it. None of it gates Save: a yield-less, time-less
/// recipe saves, links and scales; only derived numbers wait (D2).
CommitPayload buildCommit(
  ReconciliationPayload payload,
  List<LineResolution> resolutions, {
  required Recipe header,
  required Map<int, List<LineIssue>>? issuesByLine,
  List<Step>? steps,
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

  // Coalesce stubs: normalized name → the display name of its first
  // occurrence. The key is `normalizeMatchText`, which IS the server's
  // `noneDedupeKey` — the same phrase rules, on both sides of the seam. It
  // used to be the character-level query normalizer, so two no-match lines
  // reading "Almonds" and "almond" coalesced to one stub on the server and to
  // TWO on the client, and a comment claimed a symmetry that did not exist.
  final stubKeyByIndex = <int, String>{};
  final stubs = <String, CommitStub>{};
  for (final r in kept) {
    final name = r.createStubName;
    if (name == null) continue;
    if (r.isComponent) {
      // Belt and braces for the XOR: a resolution carrying both identities is
      // a bug upstream, and one stub row written for a line that will not use
      // it is a ghost ingredient in the vocabulary.
      throw StateError(
        'line ${r.lineIndex} is linked to a recipe and cannot also make a stub',
      );
    }
    final key = normalizeMatchText(name);
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
      if (r.isComponent) {
        // D6's rule, re-asserted at the seam rather than trusted from the
        // view: a linked line is valid when its amount is set, and it is a
        // component line honestly — one identity, no measure.
        if (r.quantity == null) {
          throw StateError(
            'linked line ${r.lineIndex} needs an amount before commit',
          );
        }
        if (r.chosenIngredientId != null || r.createStubName != null) {
          throw StateError(
            'line ${r.lineIndex} carries both a recipe link and an ingredient',
          );
        }
      }
      lines.add(
        CommitLine(
          lineIndex: flatIndex,
          ingredientId: r.isComponent ? null : r.chosenIngredientId,
          stubKey: r.isComponent ? null : stubKeyByIndex[flatIndex],
          subRecipeId: r.linkedRecipeId,
          quantity: r.quantity,
          unit: r.unit,
          note: (r.notes?.isEmpty ?? true) ? null : r.notes,
          // Re-asserted at the seam like the identity rules above: a
          // component line commits as not optional whatever the raw flag
          // said about the text it was linked from.
          optional: !r.isComponent && r.optional,
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

  // Both halves of a yield or neither, and a second only over a first — the
  // migration's `recipe_yield_pair` CHECKs say the same thing, and a commit
  // must not be able to bounce off them however the draft was built.
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
    title: header.title.trim(),
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
    groups: groups,
    stubs: stubs.values.toList(),
    // The review screen's own method, when it edited one (seam D4); otherwise
    // the payload's, byte-for-byte.
    steps: steps ?? payload.steps,
    corrections: corrections,
  );
}
