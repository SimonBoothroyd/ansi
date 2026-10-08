/// A held timer's sheet, from its chip or a long-press on its dock row: the
/// count large, what it is the middle of and when it rings, and its verbs —
/// Pause or Resume, −1 min, +1 min and Cancel while it runs; +1 min and Stop
/// once it is due.
///
/// It names the step and the recipe, never a verb lifted out of the prose:
/// reading *simmer* out of a sentence is the render-time reading ADR-0004
/// refuses.
library;

import 'package:flutter/widgets.dart';
import 'package:forui/forui.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

import '../../../core/theme/ansi_theme.dart';
import '../../../core/theme/ansi_tokens.dart';
import '../../../shared/ansi_modals.dart';
import '../../../shared/ansi_sheet_shell.dart';
import '../../recipes/domain/method_step.dart';
import '../data/timer_providers.dart';
import '../domain/cook_timer.dart';

Future<void> showTimerSheet(BuildContext context, String timerId) =>
    showAnsiSheet<void>(
      context: context,
      builder: (sheetContext) => _TimerSheet(
        timerId: timerId,
        close: () => Navigator.of(sheetContext).maybePop(),
      ),
    );

class _TimerSheet extends ConsumerWidget {
  const _TimerSheet({required this.timerId, required this.close});

  final String timerId;
  final VoidCallback close;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Stopped from the band, the dock or a notification while open: the
    // sheet has nothing left to say.
    ref.listen(cookTimersProvider, (_, timers) {
      if (timers[timerId] == null) close();
    });
    final timers = ref.watch(cookTimersProvider);
    final timer = timers[timerId];
    if (timer == null) return const SizedBox.shrink();
    final now = timers.now;
    final state = timer.stateAt(now);
    final notifier = ref.read(cookTimersProvider.notifier);
    final range = formatTimerRange(timer.lowSeconds, timer.highSeconds);

    return AnsiSheetShell(
      title: timer.recipeTitle,
      subtitle: 'step ${timer.step + 1} · $range',
      centerTitle: false,
      children: [
        const SizedBox(height: 18),
        Text(
          formatTimerClock(timer.left(now)),
          style: ansiMono(
            size: 44,
            weight: FontWeight.w500,
            color: state == CookTimerState.due
                ? AnsiColors.gone
                : AnsiColors.ink,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          timerSheetLine(timer, now),
          style: ansiMono(size: 11.5, color: AnsiColors.muted),
        ),
        const SizedBox(height: 14),
        _Progress(share: timer.remainingShare(now), state: state),
        const SizedBox(height: 18),
        if (state == CookTimerState.due)
          Row(
            children: [
              Expanded(
                child: FButton(
                  variant: FButtonVariant.outline,
                  onPress: () => notifier.adjust(timerId, kTimerNudge),
                  child: const Text('+1 min'),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: FButton(
                  variant: FButtonVariant.destructive,
                  onPress: () => notifier.stop(timerId),
                  child: const Text('Stop'),
                ),
              ),
            ],
          )
        else
          Row(
            children: [
              Expanded(
                child: FButton(
                  onPress: () => state == CookTimerState.paused
                      ? notifier.resume(timerId)
                      : notifier.pause(timerId),
                  child: Text(
                    state == CookTimerState.paused ? 'Resume' : 'Pause',
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: FButton(
                  variant: FButtonVariant.outline,
                  onPress: () => notifier.adjust(timerId, -kTimerNudge),
                  child: const Text('−1 min'),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: FButton(
                  variant: FButtonVariant.outline,
                  onPress: () => notifier.adjust(timerId, kTimerNudge),
                  child: const Text('+1 min'),
                ),
              ),
            ],
          ),
        if (state != CookTimerState.due) ...[
          const SizedBox(height: 8),
          FButton(
            variant: FButtonVariant.ghost,
            onPress: () => notifier.stop(timerId),
            child: Text('Cancel · back to $range'),
          ),
        ],
      ],
    );
  }
}

/// The line under the count: what it counts from and when it rings.
String timerSheetLine(CookTimer timer, DateTime now) {
  final range = formatTimerRange(timer.lowSeconds, timer.highSeconds);
  final total = formatTimerClock(timer.total);
  final ofWhat =
      timer.lowSeconds != timer.highSeconds &&
          timer.total.inSeconds ==
              midpointSeconds(timer.lowSeconds, timer.highSeconds)
      ? 'of $total, the middle of $range'
      : 'of $total';
  return switch (timer.stateAt(now)) {
    CookTimerState.running =>
      '$ofWhat · rings at ${formatClockTime(timer.endsAt!)}',
    CookTimerState.paused => 'paused · $ofWhat',
    CookTimerState.due => 'rang at ${formatClockTime(timer.endsAt!)}',
  };
}

class _Progress extends StatelessWidget {
  const _Progress({required this.share, required this.state});

  final double share;
  final CookTimerState state;

  @override
  Widget build(BuildContext context) => ClipRRect(
    borderRadius: BorderRadius.circular(3),
    child: SizedBox(
      height: 6,
      child: Stack(
        fit: StackFit.expand,
        children: [
          const ColoredBox(color: AnsiColors.line),
          FractionallySizedBox(
            alignment: Alignment.centerLeft,
            widthFactor: share,
            child: ColoredBox(
              color: state == CookTimerState.paused
                  ? AnsiColors.muted
                  : AnsiColors.herb,
            ),
          ),
        ],
      ),
    ),
  );
}
