/// What a cooked batch has left, on its Cook card: one line, opening
/// Leftovers, where it is put right.
library;

import 'package:flutter/widgets.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

import '../../../core/theme/ansi_theme.dart';
import '../../../core/theme/ansi_tokens.dart';
import '../../../core/units/portions.dart';
import '../../../shared/guarded_navigation.dart';
import '../../account/data/household_providers.dart';
import '../../planning/presentation/week_view_models.dart';
import '../domain/cook_plan.dart';
import '../domain/leftovers.dart';
import 'leftover_format.dart';
import 'leftovers_view_models.dart';

/// `1 portion left · until Fri`, `2 portions left · past its date`, `2
/// portions frozen`: the batch's row in the fridge or the freezer. Nothing
/// while it has no row: never cooked, nothing left, or said to be gone.
class BatchLeftoverLine extends ConsumerWidget {
  const BatchLeftoverLine({required this.session, super.key});

  final CookSession session;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final key = session.leftoverKey;
    if (key == null) return const SizedBox.shrink();
    final left =
        (ref.watch(fridgeAndFreezerProvider).asData?.value ??
                const <Leftover>[])
            .where((l) => l.batch == key)
            .firstOrNull;
    if (left == null) return const SizedBox.shrink();
    final today = ref.watch(todayProvider);
    final frozen = left.place == LeftoverPlace.freezer;
    final line = frozen
        ? '${formatPortions(left.portions)} frozen'
        : '${formatPortions(left.portions)} left · '
              '${leftoverWhen(left, today, ref.watch(weekShapeProvider))}';
    final ink = frozen
        ? AnsiColors.chillInk
        : left.pastItsDate(today)
        ? AnsiColors.cautionInk
        : AnsiColors.herbDeep;
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
                  child: Text(line, style: ansiMono(size: 11, color: ink)),
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
