/// Builds the in-memory [Recipe] the import review renders. Pure Dart. Nothing
/// is persisted: ids are synthetic (`line-<index>`), and the repository mints
/// real ones at commit.
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

/// Assembles the preview [Recipe] from a resolved reconciliation. A multi-use
/// identity shares one [LineItem.ingredientId]; steps are remapped from
/// line-index refs to the synthetic line ids. A dropped line is left out, as in
/// [buildCommit], and a chip that pointed at it demotes to plain text.
///
/// [measureByLine] is the measure each line's unit names, by flat line index,
/// taken from the review's validation (`LineValidation.unitMeasure`). A line
/// with one previews as commit writes it (`unit = 'piece'` + `measure_id`); a
/// component line never carries one.
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
          // Exactly one identity, as the saved row will have: a review-linked
          // line previews as the component it is about to be.
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
          // The preview tags the line as the page will — a linked line
          // included: the recipe may say a whole sub-recipe is optional.
          optional: r.optional,
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

/// The stable identity id for the preview line: a matched ingredient's id, or a
/// `raw:` handle for a line with no identity, using the character normalization
/// so two differently phrased unresolved lines stay two lines.
String _identityId(LineResolution r) {
  if (r.chosenIngredientId != null) return r.chosenIngredientId!;
  return 'raw:${normalizeSearchQuery(r.ingredientText)}';
}

/// The line's unit when it names no measure: the mapped catalog unit, else
/// count for a numbered line and "to taste" for a numberless one. Mirrors the
/// repository's `_unitId`.
Unit _unitOf(LineResolution r) {
  final mapped = r.unit == null ? null : unitById(r.unit!);
  if (mapped != null) return mapped;
  return r.quantity == null ? toTaste : pieces;
}

/// One step's tokens, remapped onto the surviving lines in [keptIndexes]. A
/// chip keeps every ref that survived; one whose lines were all dropped demotes
/// to its label as text, as the repository does at commit.
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
