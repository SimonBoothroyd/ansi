/// What became of a cooked batch's leftover: the one question Cook asks,
/// shared by the phone's cards and the wide schedule sheet.
library;

import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

import '../../../core/theme/ansi_theme.dart';
import '../../../core/theme/ansi_tokens.dart';
import '../../../core/units/portions.dart';
import '../../../shared/ansi_chip.dart';
import '../../../shared/ansi_tap.dart';
import '../../../shared/write.dart';
import '../../account/data/household_providers.dart';
import '../../planning/presentation/use_up_block.dart'
    show goodUntil, leftoverRowLine;
import '../../planning/presentation/week_view_models.dart';
import '../data/cook_plan_providers.dart';
import '../domain/cook_plan.dart';
import '../domain/leftovers.dart';
import 'cook_view_models.dart';

/// What became of a cooked batch's leftover. Until its use-by it
/// is only said — `1 portion left · good until Mon` — because the picker
/// offers it; once past, Cook asks once: **Binned** or **We ate it**. An
/// answer reads as a line, and a tap takes it back. A batch nobody ticked was
/// never cooked and is never asked about. Either member may answer; it is
/// about the pot, not a person.
class LeftoverQuestion extends ConsumerWidget {
  const LeftoverQuestion({required this.session, super.key});

  final CookSession session;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final key = session.leftoverKey;
    if (key == null) return const SizedBox.shrink();
    final answer = ref.watch(viewedWeekLeftoversProvider).asData?.value[key];
    final repo = ref.read(cookPlanRepositoryProvider);

    // Binned or eaten is an answer; an older `kept` answer is not,
    // since keeping is what a leftover does until its date.
    if (answer != null && (answer.binned > 0 || answer.eaten > 0)) {
      final said = leftoverAnswerLine(answer);
      return Padding(
        padding: const EdgeInsets.only(top: 10),
        child: AnsiTap(
          onTap: () => unawaited(
            ref.write(
              context,
              'change that',
              () => repo.setLeftover(key, null),
            ),
          ),
          semanticsLabel: 'Change what happened to the leftovers',
          child: Row(
            children: [
              Expanded(
                child: Text(
                  said,
                  style: ansiMono(
                    size: 11,
                    color: answer.binned > 0
                        ? AnsiColors.gone
                        : AnsiColors.herbDeep,
                  ),
                ),
              ),
              Text('›', style: ansiSans(size: 13, color: AnsiColors.muted)),
            ],
          ),
        ),
      );
    }

    final weekStart = ref.watch(viewedWeekStartProvider);
    final left = ref
        .watch(weekBatchLeftoversProvider(weekStart))
        .asData
        ?.value
        .where((l) => l.key == key)
        .firstOrNull;
    if (left == null) return const SizedBox.shrink();
    if (!left.isDueOn(ref.watch(todayProvider))) {
      return Padding(
        padding: const EdgeInsets.only(top: 10),
        child: Text(
          '${formatPortions(left.portions)} left · '
          '${goodUntil(left, ref.watch(weekShapeProvider))}',
          style: ansiMono(size: 11, color: AnsiColors.herbDeep),
        ),
      );
    }
    return Padding(
      padding: const EdgeInsets.only(top: 10),
      child: PastItsDate(
        heading: '${formatPortions(left.portions)} past its date',
        left: left,
      ),
    );
  }
}

/// The one question, asked once a cooked leftover's use-by has passed with
/// portions still unplanned: **Binned** or **We ate it**, for all of them.
class PastItsDate extends ConsumerWidget {
  const PastItsDate({required this.heading, required this.left, super.key});

  final String heading;
  final BatchLeftover left;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final repo = ref.read(cookPlanRepositoryProvider);
    final n = left.portions;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(heading, style: ansiSans(size: 12.5, weight: FontWeight.w600)),
        const SizedBox(height: 6),
        Row(
          children: [
            for (final (i, (label, answer)) in [
              ('Binned', (kept: 0.0, binned: n, eaten: 0.0)),
              ('We ate it', (kept: 0.0, binned: 0.0, eaten: n)),
            ].indexed) ...[
              if (i > 0) const SizedBox(width: 6),
              AnsiChip(
                label: label,
                selected: false,
                expand: true,
                onTap: () => unawaited(
                  ref.write(
                    context,
                    'say what happened',
                    () => repo.setLeftover(left.key, answer),
                  ),
                ),
              ),
            ],
          ],
        ),
      ],
    );
  }
}

/// On the week containing today, last week's cooked leftovers that ran out of
/// time unplanned: each asks the one question, so it is not missed for being
/// filed under a week nobody is looking at.
class LastWeekPastItsDate extends ConsumerWidget {
  const LastWeekPastItsDate({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final viewed = ref.watch(viewedWeekStartProvider);
    final current = ref.watch(currentWeekStartProvider);
    if (viewed != current) return const SizedBox.shrink();
    final shape = ref.watch(weekShapeProvider);
    final today = ref.watch(todayProvider);
    final lastWeek = shape.weekStartOf(
      DateTime(current.year, current.month, current.day - 7),
    );
    final due = [
      for (final l
          in ref.watch(weekBatchLeftoversProvider(lastWeek)).asData?.value ??
              const <BatchLeftover>[])
        if (l.isDueOn(today)) l,
    ];
    if (due.isEmpty) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final l in due)
          Container(
            margin: const EdgeInsets.fromLTRB(16, 4, 16, 10),
            padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
            decoration: BoxDecoration(
              color: AnsiColors.paper,
              border: Border.all(color: AnsiColors.line),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  'FROM LAST WEEK',
                  style: ansiMono(
                    size: 9.5,
                    color: AnsiColors.muted,
                    letterSpacing: 1.5,
                  ),
                ),
                const SizedBox(height: 4),
                Text(l.title, style: ansiSerif(size: AnsiType.row)),
                const SizedBox(height: 2),
                Text(
                  '${shape.labelShort(shape.offsetOf(l.cookDate))}\u2019s '
                  'batch · ${leftoverRowLine(l, shape)}',
                  style: ansiMono(size: 10.5, color: AnsiColors.muted),
                ),
                const SizedBox(height: 10),
                PastItsDate(heading: 'Past its date', left: l),
              ],
            ),
          ),
      ],
    );
  }
}

/// `1 portion kept`, `2 portions binned`, `1 kept · 1 binned`.
String leftoverAnswerLine(LeftoverAnswer a) {
  final parts = [
    if (a.kept > 0) (a.kept, 'kept'),
    if (a.binned > 0) (a.binned, 'binned'),
    if (a.eaten > 0) (a.eaten, 'eaten after all'),
  ];
  if (parts.isEmpty) return 'nothing left';
  if (parts.length == 1) {
    return '${formatPortions(parts.single.$1)} ${parts.single.$2}';
  }
  return [for (final (n, w) in parts) '${formatFraction(n)} $w'].join(' · ');
}
