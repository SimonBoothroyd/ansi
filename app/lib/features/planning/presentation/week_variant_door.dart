/// The door into week mode at the foot of the meal editor sheet. The sheet is
/// per meal and the variant is per week and recipe, so the row states its
/// scope: "a change covers every day this week — Tue and Sat".
library;

import 'package:flutter/widgets.dart';
import 'package:forui/forui.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

import '../../../core/theme/ansi_theme.dart';
import '../../../core/theme/ansi_tokens.dart';
import '../../../core/week_shape.dart';
import '../../../shared/guarded_navigation.dart';
import '../../account/data/household_providers.dart';
import '../domain/planning.dart' show PlanEntry;
import 'week_variant_format.dart';
import 'week_view_models.dart';

class WeekVariantDoorRow extends ConsumerWidget {
  const WeekVariantDoorRow({
    required this.recipeId,
    this.recipeTitle,
    super.key,
  });

  final String recipeId;
  final String? recipeTitle;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final weekStart = ref.watch(viewedWeekStartProvider);
    final overrides =
        ref.watch(viewedWeekOverridesProvider).asData?.value ?? const {};
    final changes = overrides[recipeId]?.length ?? 0;
    final plan = ref.watch(viewedWeekProvider).asData?.value;
    final days = <int>{
      for (final e in plan?.entries ?? const <PlanEntry>[])
        if (e.recipeId == recipeId) e.dayOfWeek,
    }.toList()..sort();

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => context.pushOnce(
        '/recipes/$recipeId/edit?week=${isoDateOf(weekStart)}',
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 10),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(weekDoorTitle(changes), style: ansiSans(size: 15)),
                  const SizedBox(height: 2),
                  Text(
                    weekDoorDetail(
                      changes,
                      days,
                      ref.watch(weekShapeProvider).shortLabels,
                    ),
                    style: ansiMono(size: 10.5, color: AnsiColors.muted),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 10),
            Text(
              'edit for this week',
              style: ansiSans(size: 12, color: AnsiColors.herbDeep),
            ),
            const Icon(
              FLucideIcons.chevronRight,
              size: 14,
              color: AnsiColors.herbDeep,
            ),
          ],
        ),
      ),
    );
  }
}
