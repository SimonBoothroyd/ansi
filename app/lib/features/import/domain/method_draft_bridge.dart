/// The seam between the review's method drafts and the import payload. Pure
/// Dart.
///
/// The payload (`reconciliation_payload.dart`) keys a [StepToken.ref] on
/// flattened line indexes, which `buildCommit` walks. The editor
/// (`method_draft.dart`) keys a [RefSpan] on string ids, which on the review
/// are the preview's `previewLineId(i) == 'line-<i>'`. This file converts
/// between them. Nothing renumbers: a dropped line's index stays unused.
library;

import '../../recipes/domain/method_draft.dart';
import '../../recipes/domain/method_step.dart';
import '../../recipes/domain/recipe.dart';
import 'preview_recipe.dart';
import 'reconciliation_payload.dart';

/// The line index behind a preview line id, or null when [id] is not one.
int? previewLineIndex(String id) => id.startsWith(kPreviewLinePrefix)
    ? int.tryParse(id.substring(kPreviewLinePrefix.length))
    : null;

/// The review's editable drafts for [preview], the recipe [buildPreviewRecipe]
/// built. Step ids are positional (`step-<i>`), so deriving twice gives the
/// same drafts and the cards never re-key.
List<MethodDraftStep> draftsFromPreview(Recipe preview) {
  final lines = {
    for (final group in preview.groups)
      for (final item in group.items) item.id: item,
  };
  return [
    for (final (i, step)
        in (preview.methodSteps ?? const <MethodStep>[]).indexed)
      toDraft(step, id: 'step-$i', lineById: lines),
  ];
}

/// The payload steps to commit, built from the review's edited [drafts].
/// [keptIndexes] is the set of surviving line indexes: a ref to a dropped line
/// is left out, and a chip with no surviving refs demotes to plain text
/// carrying its label.
///
/// Throws [StateError] on a ref id that is not `line-<i>`: a programming error,
/// which dropping silently would hide.
List<Step> stepsFromDrafts(
  List<MethodDraftStep> drafts,
  Set<int> keptIndexes,
) => [
  for (final draft in drafts)
    if (draft.text.trim().isNotEmpty) _step(draft, keptIndexes),
];

Step _step(MethodDraftStep draft, Set<int> keptIndexes) {
  final tokens = <StepToken>[];
  for (final token in toTokens(draft).tokens) {
    switch (token) {
      case MethodText(:final s):
        tokens.add(StepToken.text(s: s));
      case MethodTimer(:final lowSeconds, :final highSeconds):
        tokens.add(
          StepToken.timer(lowSeconds: lowSeconds, highSeconds: highSeconds),
        );
      case MethodRef(
        :final refs,
        :final label,
        :final amountRule,
        :final portion,
      ):
        final indexes = <int>[];
        for (final id in refs) {
          final index = previewLineIndex(id);
          if (index == null) {
            throw StateError(
              'method chip points at "$id", which is not a review line id',
            );
          }
          if (keptIndexes.contains(index)) indexes.add(index);
        }
        tokens.add(
          indexes.isEmpty
              ? StepToken.text(s: label)
              : StepToken.ref(
                  refs: indexes,
                  label: label,
                  mention: _mention(amountRule),
                  portion: portion == null ? null : _portion(portion),
                ),
        );
    }
  }
  return Step(tokens: _merged(tokens));
}

/// Adjacent text tokens fold into one, so a demoted chip does not change the
/// `steps` jsonb shape more than it must.
List<StepToken> _merged(List<StepToken> tokens) {
  final out = <StepToken>[];
  for (final token in tokens) {
    final last = out.isEmpty ? null : out.last;
    if (token is TextToken && last is TextToken) {
      out[out.length - 1] = StepToken.text(s: last.s + token.s);
    } else {
      out.add(token);
    }
  }
  return out;
}

MentionKind _mention(ChipAmountRule rule) => switch (rule) {
  ChipAmountRule.showAmount => MentionKind.isNew,
  ChipAmountRule.hideAmount => MentionKind.rementioned,
  ChipAmountRule.partial => MentionKind.fraction,
};

RefPortion _portion(StepPortion p) => RefPortion(
  qty: p.qty,
  qtyLow: p.qtyLow,
  qtyHigh: p.qtyHigh,
  unit: p.unit,
  qualifier: p.qualifier,
);
