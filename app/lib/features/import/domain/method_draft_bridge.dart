/// The seam between the review screen's METHOD DRAFTS and the import payload
/// — PURE DART (invariant 2).
///
/// Two vocabularies meet here, and neither moves:
///
/// - the **payload** (`reconciliation_payload.dart`) keys a [StepToken.ref] on
///   `refs: List<int>` — flattened LINE INDEXES, which is what `buildCommit`
///   walks and what the repository turns into `line_item_id`s;
/// - the **editor** (`method_draft.dart`) keys a [RefSpan] on
///   `refs: List<String>` — and on the review screen those strings are the
///   preview's synthetic ids, `previewLineId(i) == 'line-<i>'`, which is what
///   lets `MethodStepText`'s "Reads as" fold show live amounts with no extra
///   plumbing.
///
/// So the whole conversion is one parse at one place (seam **D4**). Nothing
/// renumbers: a dropped line's index simply stays unused, which `buildCommit`
/// already depends on.
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

/// The review screen's editable drafts for [preview] — the recipe
/// [buildPreviewRecipe] just built, whose method steps already carry the
/// synthetic `line-<i>` refs and whose dropped-line chips have already
/// demoted.
///
/// Step ids are positional and stable (`step-<i>`), so deriving twice from the
/// same payload gives the same drafts and nothing has to be cached to keep the
/// cards from re-keying underneath the user.
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
///
/// [keptIndexes] is the set of line indexes surviving the review. A ref whose
/// index was DROPPED is left out, and a chip left with no surviving refs
/// **demotes to plain text carrying its own label** — the never-dangling-line
/// rule `buildCommit` and the repository's `_remapSteps` already implement,
/// said once more here because this is where a chip could first lose its last
/// ref.
///
/// Throws [StateError] on a ref id that is not `line-<i>`. That is a
/// programming error (some other host's ids reached the import seam), and the
/// alternative — dropping it silently — would lose a chip with no trace.
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

/// Adjacent text tokens fold into one. A demoted chip leaves its label sitting
/// between the prose either side of it, and three tokens where the payload
/// would have written one is the difference between "edited nothing" and a
/// changed `steps` jsonb.
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
