/// "Household": a section of `/account` stating each member's usual portion and
/// the household's first day of the week.
///
/// A portion factor is set once here and read wherever demand is counted; an
/// entry's override is the exception. Either member may set either's, and every
/// tap writes through.
library;

import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:forui/forui.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

import '../../../core/sync/sync_health.dart';
import '../../../core/theme/ansi_theme.dart';
import '../../../core/theme/ansi_tokens.dart';
import '../../../core/units/portions.dart';
import '../../../core/week_shape.dart';
import '../../../shared/ansi_chip.dart';
import '../../../shared/ansi_micro_label.dart';
import '../../../shared/ansi_modals.dart';
import '../../../shared/write.dart';
import '../../account/data/household_providers.dart';
import '../data/planning_providers.dart';
import '../domain/planning.dart';
import 'week_view_models.dart';
import 'week_widgets.dart';

class HouseholdSection extends ConsumerWidget {
  const HouseholdSection({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Live: the partner's write lands here too, mid-screen.
    final members = ref.watch(membersProvider).asData?.value ?? const [];
    final repo = ref.read(planningRepositoryProvider);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const AnsiMicroLabel('Usual portion'),
        for (final (i, m) in members.indexed)
          Padding(
            padding: const EdgeInsets.only(bottom: 14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    EaterAvatar(member: m, color: memberColor(i)),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        m.displayName,
                        style: ansiSerif(size: AnsiType.row),
                      ),
                    ),
                    Text(
                      '×${formatFraction(m.portionFactor)}',
                      style: ansiMono(size: 12, color: AnsiColors.herbDeep),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                PortionFactorSegment(
                  value: m.portionFactor,
                  onChanged: (factor) => unawaited(
                    ref.write(
                      context,
                      'set ${m.displayName}’s usual portion',
                      () => repo.setPortionFactor(m.id, factor),
                    ),
                  ),
                ),
              ],
            ),
          ),
        const SizedBox(height: 4),
        const AnsiMicroLabel('Week'),
        const SizedBox(height: 6),
        const WeekStartControl(),
      ],
    );
  }
}

/// The household's first day of the week: two chips naming each week's span,
/// a confirm, and a note line while there is something to report.
///
/// Online-only: the flip is one server transaction re-homing every planned
/// week, so offline the chips go inert with the reason. A failure shows as the
/// write door's toast (with Retry) and as an amber note until the next attempt.
class WeekStartControl extends HookConsumerWidget {
  const WeekStartControl({super.key});

  /// The two days offered; the code handles any start day.
  static const _offered = [DateTime.sunday, DateTime.monday];

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final shape = ref.watch(weekShapeProvider);
    final reachable = ref.watch(serverReachableProvider).value ?? true;
    final moving = useState(false);
    final failed = useState(false);
    final inert = moving.value || !reachable;

    Future<void> pick(int startsOn) async {
      if (inert || startsOn == shape.startsOn) return;
      final span = weekSpanLabel(WeekShape(startsOn));
      // Captured before the confirm: the dialog is an async gap, and the write
      // goes through these handles (`shared/write.dart`), never this `ref`.
      final container = ProviderScope.containerOf(context, listen: false);
      final host = hostContextOf(context);
      final repo = ref.read(householdRepositoryProvider);
      final yes = await askAnsi(
        context,
        title: 'Run weeks $span?',
        body: 'Your planned weeks will shift to match.',
        confirm: span,
      );
      if (!yes) return;
      moving.value = true;
      failed.value = false;
      final done = await container.writeOk(
        host,
        'move your weeks',
        () => repo.setWeekStart(startsOn),
      );
      // Only this row's display remains to update.
      if (!context.mounted) return;
      moving.value = false;
      failed.value = !done;
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Opacity(
          opacity: inert ? 0.45 : 1,
          child: Row(
            children: [
              for (final day in _offered)
                Padding(
                  padding: const EdgeInsets.only(right: 6),
                  child: AnsiChip(
                    label: weekSpanLabel(WeekShape(day)),
                    selected: shape.startsOn == day,
                    onTap: () => unawaited(pick(day)),
                  ),
                ),
            ],
          ),
        ),
        if (weekStartNote(
              moving: moving.value,
              reachable: reachable,
              failed: failed.value,
            )
            case final note?) ...[
          const SizedBox(height: 6),
          Text(
            note,
            style: ansiMono(
              size: 10.5,
              color: switch ((failed.value, reachable)) {
                (true, _) => AnsiColors.aging,
                (_, false) => AnsiColors.gone,
                _ => AnsiColors.muted,
              },
            ),
          ),
        ],
      ],
    );
  }
}

/// `Sun – Sat`, `Mon – Sun`: the week's first and last day, so a chip names
/// the whole span whichever day it starts on.
String weekSpanLabel(WeekShape shape) =>
    '${shape.labelShort(0)} – ${shape.labelShort(6)}';

/// The note under the chips: running, failed or unavailable offline. Null
/// when there is nothing to say.
String? weekStartNote({
  required bool moving,
  required bool reachable,
  required bool failed,
}) {
  if (moving) return 'moving your weeks…';
  if (failed) return 'couldn’t move your weeks · try again';
  if (!reachable) return 'needs a connection';
  return null;
}

/// The five picks, and `…` for a custom value in quarter steps within
/// [kPortionFactorMin]..[kPortionFactorMax]. A stored value that is not a pick
/// opens in custom mode, so the row always shows the value on file.
class PortionFactorSegment extends HookWidget {
  const PortionFactorSegment({
    required this.value,
    required this.onChanged,
    super.key,
  });

  final double value;
  final ValueChanged<double> onChanged;

  @override
  Widget build(BuildContext context) {
    final isPick = kPortionFactorPicks.any((p) => (p - value).abs() < 1e-9);
    final custom = useState(!isPick);
    // A synced value arriving from the partner's phone re-decides the mode.
    useEffect(() {
      if (!isPick) custom.value = true;
      return null;
    }, [value]);

    const step = kPortionFactorStep;
    final canStepDown = value - step >= kPortionFactorMin - 1e-9;
    final canStepUp = value + step <= kPortionFactorMax + 1e-9;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            for (final pick in kPortionFactorPicks)
              Padding(
                padding: const EdgeInsets.only(right: 6),
                child: AnsiChip(
                  mono: true,
                  label: '×${formatFraction(pick)}',
                  selected: !custom.value && (pick - value).abs() < 1e-9,
                  onTap: () {
                    custom.value = false;
                    onChanged(pick);
                  },
                ),
              ),
            AnsiChip(
              mono: true,
              label: '…',
              selected: custom.value,
              onTap: () => custom.value = true,
            ),
          ],
        ),
        if (custom.value)
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Row(
              children: [
                FButton.icon(
                  variant: FButtonVariant.ghost,
                  onPress: canStepDown ? () => onChanged(value - step) : null,
                  child: const Icon(FLucideIcons.minus, size: 16),
                ),
                SizedBox(
                  width: 56,
                  child: Text(
                    '×${formatFraction(value)}',
                    textAlign: TextAlign.center,
                    style: ansiMono(size: 15, weight: FontWeight.w600),
                  ),
                ),
                FButton.icon(
                  variant: FButtonVariant.ghost,
                  onPress: canStepUp ? () => onChanged(value + step) : null,
                  child: const Icon(FLucideIcons.plus, size: 16),
                ),
                const SizedBox(width: 8),
                Text(
                  'quarter steps, ¼ to 3',
                  style: ansiMono(size: 10, color: AnsiColors.muted),
                ),
              ],
            ),
          ),
      ],
    );
  }
}
