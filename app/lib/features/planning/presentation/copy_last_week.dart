/// Copying last week, and saying what it could not bring.
///
/// `copyLastWeek` takes `plan_entry` columns only, so a recipe's **this-week
/// changes** already stayed behind — "just this week" is the whole promise,
/// and carrying a variant forward would turn it into a recipe edit made by
/// accretion. The work here is the saying of it: a silent drop is the same bug
/// as a silent carry, pointing the other way.
///
/// It is a **state, not a toast**. It stays true until somebody acts on it, it
/// names rows they may want to open, and it is about the part of an act that
/// did NOT happen — so it renders in the week's own body and clears when the
/// week moves.
library;

import 'package:flutter/widgets.dart';
import 'package:forui/forui.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

import '../../../core/theme/ansi_theme.dart';
import '../../../core/theme/ansi_tokens.dart';
import '../../../core/words.dart';
import '../../../shared/write.dart';
import '../data/planning_providers.dart';
import '../domain/planning.dart';
import 'week_view_models.dart';

/// Runs the copy and records what it left behind, for both doors that offer
/// it — the empty week's bar and the week menu — so the two cannot report it
/// two different ways.
Future<void> copyLastWeekInto(
  BuildContext context,
  WidgetRef ref, {
  required DateTime weekStart,
}) async {
  // Captured before the await: the menu that opened this closes itself, so the
  // widget's own ref is not safe on the far side.
  final container = ProviderScope.containerOf(context, listen: false);
  final result = await ref.write(
    context,
    'copy last week',
    () => container.read(planningRepositoryProvider).copyLastWeek(weekStart),
  );
  if (result == null) return;
  container.read(lastCopyReportProvider.notifier).record(weekStart, result);
}

/// What the copy brought, and the recipes whose variants it did not.
///
/// Drawn only for the week the report is about: stepping away and back is not
/// a reason to be told again.
class CopyLastWeekNotice extends ConsumerWidget {
  const CopyLastWeekNotice({required this.weekStart, super.key});

  final DateTime weekStart;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final report = ref.watch(lastCopyReportProvider);
    if (report == null || report.weekStart != weekStart) {
      return const SizedBox.shrink();
    }
    final left = report.result.variantsLeftBehind;
    if (left.isEmpty) return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 14, 20, 4),
      child: Container(
        decoration: BoxDecoration(
          color: AnsiColors.paper,
          border: Border.all(color: AnsiColors.line),
          borderRadius: BorderRadius.circular(12),
        ),
        padding: const EdgeInsets.fromLTRB(13, 11, 13, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(
                  FLucideIcons.info,
                  size: 13,
                  color: AnsiColors.muted,
                ),
                const SizedBox(width: 7),
                Expanded(
                  child: Text(
                    copiedMealsLine(report.result.meals),
                    style: ansiMono(size: 11, color: AnsiColors.muted),
                  ),
                ),
                GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: ref.read(lastCopyReportProvider.notifier).clear,
                  child: const Icon(
                    FLucideIcons.x,
                    size: 13,
                    color: AnsiColors.muted,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 7),
            Text(variantsLeftBehindLine(left), style: ansiSans(size: 12.5)),
          ],
        ),
      ),
    );
  }
}

/// The `copy last week` chip an empty week offers.
///
/// It is the one door both shapes of the screen share: beside the phone's
/// "Add the first meal" button, and under the wide matrix's head, where the
/// seven column feet already carry the add doors so a primary would be a
/// second door to the same place. Drawn only while the week has zero entries
/// and there is a week behind it — the permanent home is the switcher menu.
class CopyLastWeekChip extends StatelessWidget {
  const CopyLastWeekChip({required this.onTap, super.key});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
        decoration: BoxDecoration(
          color: AnsiColors.herbSoft,
          borderRadius: BorderRadius.circular(999),
        ),
        child: Text(
          'copy last week',
          style: ansiMono(size: 11, color: AnsiColors.herbDeep),
        ),
      ),
    );
  }
}

/// `Copied 7 meals from last week`.
String copiedMealsLine(int meals) =>
    'Copied $meals ${plural(meals, 'meal')} from last week';

/// The recipes whose this-week changes did not follow, named and counted.
String variantsLeftBehindLine(List<VariantLeftBehind> left) {
  final n = left.length;
  final named = [
    for (final v in left)
      '${v.recipeTitle} (${v.changes} ${plural(v.changes, 'change')})',
  ].join(', ');
  final subject = n == 1
      ? "One recipe's this-week changes were left behind"
      : "$n recipes' this-week changes were left behind";
  return "$subject — $named. Last week's meals came over; last week's "
      'changes did not. Open one and edit for this week if you want it again.';
}
