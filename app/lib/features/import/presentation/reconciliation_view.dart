/// The v3 review screen (owner refinement): ONE editable surface. There is no
/// separate triage/preview split any more — the imported recipe is reviewed and
/// confirmed here, every line an expandable [ReviewLineCard] (compact by
/// default, tap to edit in place). The honest-import warnings ride the top and
/// commit happens at the bottom.
///
/// The never-invent flags (0014) are shown, not hidden: parse warnings, a
/// degraded image, a truncated source, and each line's own flags.
library;

import 'package:flutter/widgets.dart';
import 'package:forui/forui.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

import '../../../core/theme/mise_theme.dart';
import '../../../core/theme/mise_tokens.dart';
import '../../recipes/domain/method_step.dart';
import '../../recipes/domain/recipe.dart';
import '../../recipes/presentation/format.dart';
import '../domain/line_validation.dart';
import '../domain/preview_recipe.dart';
import '../domain/reconciliation_payload.dart';
import 'import_view_models.dart';
import 'recon_line_card.dart';

class ReconciliationBody extends HookConsumerWidget {
  const ReconciliationBody({required this.state, super.key});

  final ImportReconciling state;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final controller = ref.read(importControllerProvider.notifier);
    final payload = state.payload;
    final flat = payload.flatLines;
    final byIndex = {for (final r in state.resolutions) r.lineIndex: r};
    // Per-line validity (matched? range picked? unit in the ingredient's
    // allowed set?) + inline unit chips — drives each card's flag, its unit
    // suggestions, AND the Save gate.
    final validation = ref.watch(importValidationProvider);
    final byLine = validation.asData?.value;
    final issuesByLine = byLine == null
        ? null
        : {for (final e in byLine.entries) e.key: e.value.issues};
    // The read-only method fold reads the same recipe a save would write.
    final recipe = buildPreviewRecipe(
      payload,
      state.resolutions,
      servingsBase: state.servings,
    );

    final rows = <Widget>[];
    var flatIndex = 0;
    for (final group in payload.groups) {
      if (group.name != null && group.name!.isNotEmpty) {
        rows.add(
          Padding(
            padding: const EdgeInsets.only(top: 16, bottom: 2),
            child: Text(
              group.name!,
              style: miseSerif(
                size: 18,
                color: MiseColors.herbDeep,
              ).copyWith(fontStyle: FontStyle.italic),
            ),
          ),
        );
      }
      for (final _ in group.lines) {
        final i = flatIndex;
        rows.add(
          ReviewLineCard(
            key: ValueKey('review-line-$i'),
            line: flat[i],
            resolution: byIndex[i]!,
            controller: controller,
            validation: byLine?[i],
          ),
        );
        flatIndex++;
      }
    }

    // Save is gated on EVERY line being valid: matched, range picked, and a
    // unit inside the matched ingredient's allowed set (round-2 #2). While
    // validation is still loading it stays disabled.
    final canSave =
        issuesByLine != null &&
        state.canCommit &&
        allLinesValid(issuesByLine);
    final outstanding = issuesByLine == null
        ? state.unresolvedCount
        : issuesByLine.values.where((i) => i.isNotEmpty).length;

    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 4, 20, 32),
      children: [
        Text(
          payload.title.isEmpty ? 'Untitled recipe' : payload.title,
          style: miseSerif(size: 28, weight: FontWeight.w700),
        ),
        const SizedBox(height: 12),
        _ServingsRow(state: state, onChanged: controller.setServings),
        const SizedBox(height: 10),
        _SectionHeader(label: 'Ingredients', count: flat.length),
        ...rows,
        const SizedBox(height: 24),
        _MethodPreview(recipe: recipe),
        const SizedBox(height: 12),
        Text(
          'Method is read-only in v1 — chips render with live amounts; editing '
          'lands later via the recipe’s Edit route.',
          style: miseMono(size: 11, color: MiseColors.muted),
        ),
        const SizedBox(height: 20),
        FButton(
          onPress: canSave ? controller.commit : null,
          child: Text(
            canSave ? 'Save recipe' : '$outstanding line(s) need you',
          ),
        ),
      ],
    );
  }
}

/// A section header: the mono label + a count pill + a rule.
class _SectionHeader extends StatelessWidget {
  const _SectionHeader({required this.label, required this.count});

  final String label;
  final int count;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 8, bottom: 6),
      child: Row(
        children: [
          Text(label.toUpperCase(), style: miseLabel(color: MiseColors.ink)),
          const SizedBox(width: 8),
          DecoratedBox(
            decoration: BoxDecoration(
              color: MiseColors.herb,
              borderRadius: BorderRadius.circular(999),
            ),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 1),
              child: Text(
                '$count',
                style: miseMono(size: 10, color: MiseColors.surface),
              ),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(child: Container(height: 1, color: MiseColors.line)),
        ],
      ),
    );
  }
}


class _ServingsRow extends StatelessWidget {
  const _ServingsRow({required this.state, required this.onChanged});

  final ImportReconciling state;
  final ValueChanged<double> onChanged;

  @override
  Widget build(BuildContext context) {
    final unclear = state.payload.servingsBase == null;
    return Row(
      children: [
        Text('SERVES', style: miseLabel()),
        if (unclear) ...[
          const SizedBox(width: 8),
          Text(
            'not printed — set it',
            style: miseMono(size: 10, color: MiseColors.aging),
          ),
        ],
        const Spacer(),
        FButton.icon(
          onPress: state.servings > 1
              ? () => onChanged(state.servings - 1)
              : null,
          child: const Icon(FLucideIcons.minus),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14),
          child: Text(
            formatQuantity(state.servings),
            style: miseSans(size: 17, weight: FontWeight.w700),
          ),
        ),
        FButton.icon(
          onPress: () => onChanged(state.servings + 1),
          child: const Icon(FLucideIcons.plus),
        ),
      ],
    );
  }
}

/// The read-only method: each step folded to prose + inline ingredient/timer
/// chips by [foldMethod] (no render-time matching), numbered.
class _MethodPreview extends StatelessWidget {
  const _MethodPreview({required this.recipe});

  final Recipe recipe;

  @override
  Widget build(BuildContext context) {
    final steps = recipe.methodSteps ?? const [];
    if (steps.isEmpty) return const SizedBox.shrink();
    final lineById = {
      for (final g in recipe.groups)
        for (final i in g.items) i.id: i,
    };

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text('METHOD', style: miseLabel()),
        const SizedBox(height: 8),
        for (var i = 0; i < steps.length; i++)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 6),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${i + 1}',
                  style: miseMono(size: 13, weight: FontWeight.w700),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _StepText(
                    spans: foldMethod(steps[i], lineById: lineById),
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }
}

class _StepText extends StatelessWidget {
  const _StepText({required this.spans});

  final List<MethodSpan> spans;

  @override
  Widget build(BuildContext context) {
    return Text.rich(
      TextSpan(
        children: [
          for (final span in spans)
            switch (span) {
              MethodTextSpan(:final text) => TextSpan(text: text),
              MethodChipSpan(:final label, :final amount) => WidgetSpan(
                alignment: PlaceholderAlignment.middle,
                child: _Chip(label: label, amount: amount),
              ),
              MethodTimerSpan(:final text) => WidgetSpan(
                alignment: PlaceholderAlignment.middle,
                child: _Chip(label: text, timer: true),
              ),
            },
        ],
        style: miseSans(size: 15, height: 1.5),
      ),
    );
  }
}

class _Chip extends StatelessWidget {
  const _Chip({required this.label, this.amount, this.timer = false});

  final String label;
  final String? amount;
  final bool timer;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 1),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: timer ? MiseColors.paper : MiseColors.herbSoft,
          border: timer ? Border.all(color: MiseColors.line) : null,
          borderRadius: BorderRadius.circular(6),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (timer) ...[
                const Icon(
                  FLucideIcons.timer,
                  size: 12,
                  color: MiseColors.muted,
                ),
                const SizedBox(width: 4),
              ],
              Text(
                label,
                style: timer
                    ? miseMono(size: 12)
                    : miseSans(
                        size: 15,
                        color: MiseColors.herbDeep,
                        weight: FontWeight.w600,
                      ),
              ),
              if (amount != null) ...[
                const SizedBox(width: 5),
                Text(
                  amount!,
                  style: miseMono(size: 12, color: MiseColors.herb),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
