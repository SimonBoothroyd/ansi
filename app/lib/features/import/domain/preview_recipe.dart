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

import '../../../core/units/units.dart';
import '../../ingredients/domain/search_query.dart';
import '../../recipes/domain/method_step.dart';
import '../../recipes/domain/recipe.dart';
import 'line_resolution.dart';
import 'reconciliation_payload.dart';

/// The synthetic line-item id for the flattened line at [index] — the handle
/// the preview's method refs point at.
String previewLineId(int index) => 'line-$index';

/// Assembles the preview [Recipe] from a resolved reconciliation. Every line
/// carries the ingredient the user resolved it to (a real match's name, a
/// create-new stub's name, or — defensively — the raw text); a multi-use
/// identity shares one [LineItem.ingredientId] so the recipe page folds it into
/// a single inline row. Method steps are remapped from line-index refs to the
/// synthetic line ids and rendered by the existing fold.
///
/// A DROPPED line is left out, exactly as [buildCommit] leaves it out, and any
/// step chip that pointed at it demotes to its own label as plain prose — so
/// the preview keeps showing what a save would actually write.
Recipe buildPreviewRecipe(
  ReconciliationPayload payload,
  List<LineResolution> resolutions, {
  required double servingsBase,
}) {
  final byIndex = {
    for (final r in resolutions)
      if (!r.isDropped) r.lineIndex: r,
  };

  final groups = <IngredientGroup>[];
  var flatIndex = 0;
  for (var gi = 0; gi < payload.groups.length; gi++) {
    final group = payload.groups[gi];
    final items = <LineItem>[];
    for (final _ in group.lines) {
      final r = byIndex[flatIndex];
      if (r == null) {
        flatIndex++;
        continue;
      }
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
          ingredientName: _displayName(r),
          unit: _unitOf(r),
          quantity: r.quantity,
          note: (r.notes?.trim().isEmpty ?? true) ? null : r.notes!.trim(),
        ),
      );
      flatIndex++;
    }
    if (items.isNotEmpty) {
      groups.add(
        IngredientGroup(id: 'group-$gi', name: group.name, items: items),
      );
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
/// a `stub:` handle keyed by the coalescing name so identical no-match uses
/// fold onto one inline row (the same coalescing [buildCommit] does).
String _identityId(LineResolution r) {
  if (r.chosenIngredientId != null) return r.chosenIngredientId!;
  if (r.createStubName != null) {
    return 'stub:${normalizeSearchQuery(r.createStubName!)}';
  }
  return 'raw:${normalizeSearchQuery(r.ingredientText)}';
}

String _displayName(LineResolution r) =>
    r.linkedRecipeTitle ?? r.chosenName ?? r.createStubName ?? r.ingredientText;

/// The line's unit: the mapped catalog unit, else an honest degrade — count
/// for a numbered line, "to taste" for a numberless one (invariant 3, never a
/// fabricated gram).
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
                  mention: _mention(mention),
                  portion: portion == null ? null : _portion(portion),
                )
              : MethodToken.text(s: label),
      },
  ],
);

StepMention _mention(MentionKind kind) => switch (kind) {
  MentionKind.isNew => StepMention.isNew,
  MentionKind.rementioned => StepMention.rementioned,
  MentionKind.fraction => StepMention.fraction,
};

StepPortion _portion(RefPortion p) => StepPortion(
  qty: p.qty,
  qtyLow: p.qtyLow,
  qtyHigh: p.qtyHigh,
  unit: p.unit,
  qualifier: p.qualifier,
);
