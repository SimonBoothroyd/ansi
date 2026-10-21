/// The meal sheet's top row from a meal's own day on: *I ate this*, for the
/// member signed in on this phone and nobody else.
///
/// Ticking never edits the plan; it records who ate the meal and when. The
/// time is when they ticked — or, ticked on a later day, the meal's own day at
/// that clock time — and the time beside the switch opens a picker to change
/// it.
library;

import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:forui/forui.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

import '../../../core/theme/ansi_theme.dart';
import '../../../core/theme/ansi_tokens.dart';
import '../../../core/words.dart';
import '../../../shared/ansi_modals.dart';
import '../../../shared/ansi_sheet_shell.dart';
import '../../../shared/ansi_tap.dart';
import '../../../shared/write.dart';
import '../data/planning_providers.dart';
import '../domain/planning.dart';
import 'week_view_models.dart';

/// When a tick made at [now] says a meal on [mealDay] was eaten: now, on the
/// meal's day; otherwise the meal's day at now's clock time, so a late tick
/// never lands on the wrong day.
DateTime defaultEatenAt({required DateTime mealDay, required DateTime now}) =>
    now.year == mealDay.year &&
        now.month == mealDay.month &&
        now.day == mealDay.day
    ? now
    : DateTime(mealDay.year, mealDay.month, mealDay.day, now.hour, now.minute);

/// `19:42` on the meal's own day, `Thu 19:42` on another.
String eatenAtLabel(DateTime at, {required DateTime mealDay}) {
  final local = at.toLocal();
  final clock =
      '${local.hour.toString().padLeft(2, '0')}:'
      '${local.minute.toString().padLeft(2, '0')}';
  final sameDay =
      local.year == mealDay.year &&
      local.month == mealDay.month &&
      local.day == mealDay.day;
  return sameDay ? clock : '${kWeekdayShort[local.weekday - 1]} $clock';
}

/// The row: `I ate this`, the time once ticked, and the switch.
class MealEatenRow extends ConsumerWidget {
  const MealEatenRow({
    required this.entry,
    required this.memberId,
    required this.mealDay,
    super.key,
  });

  final PlanEntry entry;

  /// The member signed in on this phone — the only one this row writes for.
  final String memberId;

  /// The local day the meal is planned on.
  final DateTime mealDay;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final at = entry.eatenAt[memberId];
    final repo = ref.read(planningRepositoryProvider);

    void set(DateTime? when) => unawaited(
      ref.write(
        context,
        when == null ? 'untick it' : 'tick it',
        () => repo.setMealEaten(entry.id, memberId: memberId, eatenAt: when),
      ),
    );

    return Container(
      padding: const EdgeInsets.only(left: 12, right: 8),
      decoration: BoxDecoration(
        color: AnsiColors.paper,
        borderRadius: BorderRadius.circular(12),
      ),
      constraints: const BoxConstraints(minHeight: 48),
      child: Row(
        children: [
          Expanded(
            child: Text(
              'I ate this',
              style: ansiSans(size: 14.5, weight: FontWeight.w500),
            ),
          ),
          if (at != null)
            AnsiTap(
              onTap: () => unawaited(_pickTime(context, ref, at)),
              semanticsLabel: 'Change when',
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 12),
              child: Text(
                '${eatenAtLabel(at, mealDay: mealDay)} ›',
                style: ansiMono(size: 12, color: AnsiColors.herbDeep),
              ),
            ),
          FSwitch(
            semanticsLabel: 'I ate this',
            value: at != null,
            onChange: (on) => set(
              on
                  ? defaultEatenAt(
                      mealDay: mealDay,
                      now: ref.read(clockProvider)(),
                    )
                  : null,
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _pickTime(
    BuildContext context,
    WidgetRef ref,
    DateTime current,
  ) async {
    // Captured before the await: the sheet's row may be gone when the picker
    // closes (`shared/write.dart`).
    final container = ProviderScope.containerOf(context, listen: false);
    final host = hostContextOf(context);
    final repo = ref.read(planningRepositoryProvider);
    final picked = await showAnsiSheet<DateTime>(
      context: context,
      builder: (_) => _EatenAtPicker(initial: current.toLocal()),
    );
    if (picked == null) return;
    await container.write(
      host,
      'change when you ate it',
      () => repo.setMealEaten(entry.id, memberId: memberId, eatenAt: picked),
    );
  }
}

/// A date-and-time wheel and a Done.
class _EatenAtPicker extends StatefulWidget {
  const _EatenAtPicker({required this.initial});

  final DateTime initial;

  @override
  State<_EatenAtPicker> createState() => _EatenAtPickerState();
}

class _EatenAtPickerState extends State<_EatenAtPicker> {
  late DateTime _picked = widget.initial;

  @override
  Widget build(BuildContext context) {
    return AnsiSheetShell(
      title: 'When',
      centerTitle: false,
      topPadding: 16,
      children: [
        const SizedBox(height: 12),
        SizedBox(
          height: 180,
          child: FDateTimePicker(
            hour24: true,
            control: FDateTimePickerControl.managed(
              initial: widget.initial,
              onChange: (v) => _picked = v,
            ),
          ),
        ),
        const SizedBox(height: 16),
        FButton(
          onPress: () => Navigator.of(context).pop(_picked),
          child: const Text('Done'),
        ),
      ],
    );
  }
}
