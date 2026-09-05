/// Builds the in-memory [Recipe] the import **preview** renders — PURE DART
/// (invariant 2). The preview (v3 LOCKED, step 7) is the resolved recipe shown
/// exactly as the recipe page will read it, before anything is written: the
/// same three-part ingredient lines (so multi-use identities fold inline) and
/// the same method fold, read-only.
///
/// Nothing here is persisted — ids are synthetic (`line-<index>`), so the
/// preview never leaks a fake id into PowerSync. The real ids are minted by the
/// repository at commit; this recipe exists only to be looked at.
library;

import '../../../core/search/search_query.dart';
import '../../../core/units/measure.dart';
import '../../../core/units/units.dart';
import '../../recipes/domain/method_step.dart';
import '../../recipes/domain/recipe.dart';
import 'line_resolution.dart';
import 'reconciliation_payload.dart';
import 'review_groups.dart';

/// The prefix every synthetic preview line id carries. `method_draft_bridge`
/// parses ids back to indexes with it, so the two cannot drift.
const kPreviewLinePrefix = 'line-';

/// The synthetic line-item id for the flattened line at [index] — the handle
/// the preview's method refs point at.
String previewLineId(int index) => '$kPreviewLinePrefix$index';

/// Assembles the preview [Recipe] from a resolved reconciliation. Every line
/// carries the ingredient the user resolved it to (a real match's name, or —
/// defensively — the raw text); a multi-use
/// identity shares one [LineItem.ingredientId] so the recipe page folds it into
/// a single inline row. Method steps are remapped from line-index refs to the
/// synthetic line ids and rendered by the existing fold.
///
/// A DROPPED line is left out, exactly as [buildCommit] leaves it out, and any
/// step chip that pointed at it demotes to its own label as plain prose — so
/// the preview keeps showing what a save would actually write.
///
/// [measureByLine] is the measure each line's unit NAMES, by flat line index —
/// the review's validation already resolved it once for the whole import
/// (`LineValidation.unitMeasure`), and the preview takes that same value rather
/// than re-deriving it, so the card and the chip sheet cannot disagree. A line
/// with a measure previews exactly as commit writes it (`unit = 'piece'` +
/// `measure_id`, migration 0009): its formatter reads the measure label, not
/// "piece". A measure word is not a catalogue unit id, so without this it
/// degraded to a bare count — right at commit, wrong on the sheet. A component
/// line never carries one, whatever the map says, mirroring the commit guard.
Recipe buildPreviewRecipe(
  ReconciliationPayload payload,
  List<LineResolution> resolutions, {
  required double servingsBase,
  Map<int, Measure> measureByLine = const {},
  List<ReviewGroup>? sections,
}) {
  final byIndex = {
    for (final r in resolutions)
      if (!r.isDropped) r.lineIndex: r,
  };

  final groups = <IngredientGroup>[];
  for (final group in sections ?? initialGroups(payload)) {
    final items = <LineItem>[];
    for (final flatIndex in group.lines) {
      final r = byIndex[flatIndex];
      if (r == null) continue;
      final measure = r.isComponent || r.chosenIngredientId == null
          ? null
          : measureByLine[flatIndex];
      items.add(
        LineItem(
          id: previewLineId(flatIndex),
          // Exactly one identity, as the saved row will have (8.6 / D1): a
          // review-LINKED line previews as the component it is about to be.
          ingredientId: r.isComponent ? null : _identityId(r),
          subRecipeId: r.linkedRecipeId,
          subRecipe: r.isComponent
              ? SubRecipeTarget(
                  id: r.linkedRecipeId!,
                  title: r.linkedRecipeTitle ?? r.ingredientText,
                )
              : null,
          ingredientName: r.displayName,
          unit: measure == null ? _unitOf(r) : pieces,
          measureId: measure?.id,
          measure: measure,
          quantity: r.quantity,
          note: (r.notes?.trim().isEmpty ?? true) ? null : r.notes!.trim(),
          // The preview tags the line as the page will; the commit guard's rule
          // for a component, mirrored.
          optional: !r.isComponent && r.optional,
        ),
      );
    }
    if (items.isNotEmpty) {
      groups.add(IngredientGroup(id: group.id, name: group.name, items: items));
    }
  }

  return Recipe(
    id: 'preview',
    title: payload.title,
    servingsBase: servingsBase <= 0 ? 1 : servingsBase,
    groups: groups,
    methodSteps: [
      for (final step in payload.steps) _methodStep(step, byIndex.keys.toSet()),
    ],
  );
}

/// The stable identity id for the preview line — a matched ingredient's id, or
/// a `raw:` handle for a line that has no identity at all. A line with no
/// identity is still a line, so the looser character normalization is the right
/// one there — two differently phrased unresolved lines are two lines. There is
/// no third handle between them: a row created at review has a real id like any
/// other.
String _identityId(LineResolution r) {
  if (r.chosenIngredientId != null) return r.chosenIngredientId!;
  return 'raw:${normalizeSearchQuery(r.ingredientText)}';
}

/// The line's unit when it names no measure: the mapped catalog unit, else an
/// honest degrade — count for a numbered line, "to taste" for a numberless one
/// (invariant 3, never a fabricated gram). Mirrors the repository's `_unitId`.
Unit _unitOf(LineResolution r) {
  final mapped = r.unit == null ? null : unitById(r.unit!);
  if (mapped != null) return mapped;
  return r.quantity == null ? toTaste : pieces;
}

/// One step's tokens, remapped onto the surviving lines in [keptIndexes]. A
/// chip keeps every ref that survived; a chip whose lines were ALL dropped
/// demotes to its own label as prose (the same demotion the repository does at
/// commit), so the sentence still reads — "finish with basil", chip-less —
/// instead of losing the word.
MethodStep _methodStep(Step step, Set<int> keptIndexes) => MethodStep(
  tokens: [
    for (final token in step.tokens)
      switch (token) {
        TextToken(:final s) => MethodToken.text(s: s),
        TimerToken(:final lowSeconds, :final highSeconds) => MethodToken.timer(
          lowSeconds: lowSeconds,
          highSeconds: highSeconds,
        ),
        RefToken(:final refs, :final label, :final mention, :final portion) =>
          refs.any(keptIndexes.contains)
              ? MethodToken.ref(
                  refs: [
                    for (final i in refs)
                      if (keptIndexes.contains(i)) previewLineId(i),
                  ],
                  label: label,
                  amountRule: _amountRule(mention),
                  portion: portion == null ? null : _portion(portion),
                )
              : MethodToken.text(s: label),
      },
  ],
);

ChipAmountRule _amountRule(MentionKind kind) => switch (kind) {
  MentionKind.isNew => ChipAmountRule.showAmount,
  MentionKind.rementioned => ChipAmountRule.hideAmount,
  MentionKind.fraction => ChipAmountRule.partial,
};

StepPortion _portion(RefPortion p) => StepPortion(
  qty: p.qty,
  qtyLow: p.qtyLow,
  qtyHigh: p.qtyHigh,
  unit: p.unit,
  qualifier: p.qualifier,
);
