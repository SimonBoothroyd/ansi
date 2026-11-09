/// What a cooked batch has left, on its Cook card: one line, opening
/// Leftovers, where it is put right.
library;

import 'package:flutter/widgets.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

import '../../../core/theme/ansi_theme.dart';
import '../../../core/theme/ansi_tokens.dart';
import '../../../shared/guarded_navigation.dart';
import '../../account/data/household_providers.dart';
import '../../planning/presentation/week_view_models.dart';
import '../domain/cook_plan.dart';
import '../domain/leftovers.dart';
import 'leftover_format.dart';
import 'leftovers_view_models.dart';

/// `2 left · till Mon`, `1 left · for Sun`, `2 left · freeze by Mon for Wed`,
/// `2 left · past its date`, `1 left · Wed needs 2`: what is in the batch's
/// box and what it is for.
/// Before anybody ticked it, `freeze 2 by Tue for Thu` for its later meals
/// reached from the freezer. Nothing while it has nothing left or to come.
class BatchLeftoverLine extends ConsumerWidget {
  const BatchLeftoverLine({required this.session, super.key});

  final CookSession session;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final key = session.cookingId;
    final today = ref.watch(todayProvider);
    final shape = ref.watch(weekShapeProvider);
    final weekStart = ref.watch(viewedWeekStartProvider);
    final share = freezeShareOf(session, weekStart, today);
    final shareDue = share != null && !today.isAfter(share.freezeBy);
    // The cooking's fridge shelf first, else its freezer.
    final left = key != null && wasCooked(session)
        ? (ref.watch(fridgeAndFreezerProvider).asData?.value ??
                  const <Leftover>[])
              .where((l) => l.id == key && l.isCookedBy(today))
              .firstOrNull
        : null;

    final List<(String, Color)> parts;
    if (left == null) {
      // Not cooked yet: what it will put in the freezer.
      if (!shareDue || wasCooked(session)) return const SizedBox.shrink();
      parts = [(freezeShareLine(share, weekStart, shape), AnsiColors.chillInk)];
    } else {
      final past = left.pastItsDate(today);
      final frozen = left.place == LeftoverPlace.freezer;
      final forDays = leftoverFor(left, today, shape);
      final short = leftoverShortFor(left, today, shape);
      final freeze = shareDue
          ? freezeShareFor(share, weekStart, shape)
          : leftoverFreezeFor(left, today, shape);
      parts = [
        (leftCount(left.inBox), AnsiColors.herbDeep),
        if (short != null) (short, AnsiColors.cautionInk),
        if (forDays != null) (forDays, AnsiColors.herbDeep),
        if (freeze != null) (freeze, AnsiColors.chillInk),
        if (forDays == null && freeze == null && short == null)
          (
            leftoverWhen(left, today, shape),
            past
                ? AnsiColors.cautionInk
                : frozen
                ? AnsiColors.chillInk
                : AnsiColors.herbDeep,
          ),
      ];
    }
    final line = parts.map((p) => p.$1).join(' · ');
    return Semantics(
      button: true,
      label: '$line, open Leftovers',
      child: ExcludeSemantics(
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () => context.pushOnce('/leftovers'),
          child: Container(
            constraints: const BoxConstraints(minHeight: 44),
            padding: const EdgeInsets.only(top: 6),
            child: Row(
              children: [
                Expanded(
                  child: Text.rich(
                    TextSpan(
                      children: [
                        for (final (i, (words, ink)) in parts.indexed) ...[
                          if (i > 0)
                            TextSpan(
                              text: ' · ',
                              style: ansiMono(
                                size: 11,
                                color: AnsiColors.muted,
                              ),
                            ),
                          TextSpan(
                            text: words,
                            style: ansiMono(
                              size: 11,
                              color: ink,
                              weight: left != null && i == 0
                                  ? FontWeight.w600
                                  : FontWeight.w400,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
                Text('›', style: ansiSans(size: 13, color: AnsiColors.muted)),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
