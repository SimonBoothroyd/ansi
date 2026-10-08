/// The timers' chrome around every screen.
///
/// - [TimerDock]: one full-width row while anything runs — the timer that
///   needs you first, as step · the recipe's whole title · count — and
///   **+N** for the rest, which opens [showTimerList]. Above the bar on a
///   tab; at the screen's foot on a pushed page ([TimerFrame]).
/// - [TimerBand]: a due timer, loud, under the status bar, with +1 min and
///   Stop.
/// - [TimerSideList]: on a desk, the opened list held in the sidebar.
/// - [TimerTabTitle]: on the web, the tab's title counts.
///
/// A title is cut at its end, never shortened to a word: *Slow-Cooker* and
/// *Sticky* name nothing.
library;

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:forui/forui.dart';
import 'package:go_router/go_router.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

import '../../../core/theme/ansi_theme.dart';
import '../../../core/theme/ansi_tokens.dart';
import '../../../shared/ansi_layout.dart';
import '../../../shared/ansi_modals.dart';
import '../../../shared/ansi_sheet_shell.dart';
import '../../../shared/ansi_side_nav.dart';
import '../../../shared/guarded_navigation.dart';
import '../../../shared/timer_wash.dart';
import '../data/timer_providers.dart';
import '../domain/cook_timer.dart';
import 'timer_sheet.dart';

/// Opens [timer]'s step: scrolls the recipe page when it is the one on
/// screen, pushes it at the step otherwise.
void openTimerStep(BuildContext context, WidgetRef ref, CookTimer timer) {
  final path = GoRouter.of(context).state.uri.path;
  if (path == '/recipes/${timer.recipeId}') {
    ref
        .read(methodStepFocusProvider.notifier)
        .focus(timer.recipeId, timer.step);
  } else {
    context.pushOnce('/recipes/${timer.recipeId}?step=${timer.step}');
  }
}

/// The band above and the dock below whatever the shell navigator shows,
/// inside the content pane. Built by the router's outer shell, so a push
/// keeps it; it also answers a notification's tap by opening that step.
class TimerFrame extends ConsumerWidget {
  const TimerFrame({required this.child, super.key});

  final Widget child;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    ref.listen(timerOpenRequestProvider, (_, timer) {
      if (timer == null) return;
      ref.read(timerOpenRequestProvider.notifier).clear();
      openTimerStep(context, ref, timer);
    });
    final timers = ref.watch(cookTimersProvider);
    final form = AnsiShell.of(context);
    // The tab shell draws its own dock above the bar; a desk's sidebar holds
    // the list instead.
    final tabRoot = ansiBranchLocations.contains(
      GoRouter.of(context).state.uri.path,
    );
    final dock = switch (form) {
      AnsiShell.bar => !tabRoot,
      AnsiShell.rail => true,
      AnsiShell.sidebar => false,
    };
    final docked = dock && !timers.isEmpty && !_keyboardUp(context);
    final band = timers.due.isNotEmpty;
    if (!docked && !band) return child;
    return Column(
      children: [
        if (band)
          SafeArea(
            bottom: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
              child: TimerBand(timer: timers.due.first, now: timers.now),
            ),
          ),
        Expanded(
          child: MediaQuery.removePadding(
            context: context,
            removeTop: band,
            removeBottom: docked,
            child: child,
          ),
        ),
        if (docked) const SafeArea(top: false, child: TimerDock()),
      ],
    );
  }
}

bool _keyboardUp(BuildContext context) =>
    MediaQuery.viewInsetsOf(context).bottom > 0;

/// A due timer: the step and the recipe's whole title on their own line,
/// the overtime counting, and +1 min and Stop on the next.
class TimerBand extends ConsumerWidget {
  const TimerBand({required this.timer, required this.now, super.key});

  final CookTimer timer;
  final DateTime now;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final notifier = ref.read(cookTimersProvider.notifier);
    // A phone gives the title its own line and the verbs the next; wider,
    // they sit at the end of the one row.
    final narrow = AnsiLayout.of(context) == AnsiLayout.compact;
    final verbs = [
      _BandButton(
        label: '+1 min',
        onPress: () => notifier.adjust(timer.id, kTimerNudge),
      ),
      const SizedBox(width: 8),
      _BandButton(
        label: 'Stop',
        solid: true,
        onPress: () => notifier.stop(timer.id),
      ),
    ];
    return Semantics(
      liveRegion: true,
      container: true,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: AnsiColors.gone,
          borderRadius: BorderRadius.circular(14),
        ),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 11, 12, 11),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              FTappable(
                onPress: () => openTimerStep(context, ref, timer),
                semanticsLabel:
                    'Step ${timer.step + 1} is done, ${timer.recipeTitle}',
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Step ${timer.step + 1} is done',
                            style: ansiSans(
                              size: 14,
                              weight: FontWeight.w600,
                              color: AnsiColors.surface,
                            ),
                          ),
                          const SizedBox(height: 1),
                          Text(
                            timer.recipeTitle,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: ansiSans(
                              size: 13,
                              color: AnsiColors.surface,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 10),
                    Text(
                      formatTimerClock(timer.left(now)),
                      style: ansiMono(
                        size: 16,
                        weight: FontWeight.w500,
                        color: AnsiColors.surface,
                      ),
                    ),
                    if (!narrow) ...[const SizedBox(width: 14), ...verbs],
                  ],
                ),
              ),
              if (narrow) ...[
                const SizedBox(height: 8),
                Row(mainAxisAlignment: MainAxisAlignment.end, children: verbs),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _BandButton extends StatelessWidget {
  const _BandButton({
    required this.label,
    required this.onPress,
    this.solid = false,
  });

  final String label;
  final VoidCallback onPress;
  final bool solid;

  @override
  Widget build(BuildContext context) => FTappable(
    onPress: onPress,
    semanticsLabel: label,
    child: Container(
      constraints: const BoxConstraints(minHeight: 36, minWidth: 64),
      alignment: Alignment.center,
      padding: const EdgeInsets.symmetric(horizontal: 14),
      decoration: BoxDecoration(
        color: solid ? AnsiColors.surface : null,
        border: Border.all(color: const Color(0x8CFFFFFF)),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Text(
        label,
        style: ansiSans(
          size: 13,
          weight: FontWeight.w600,
          color: solid ? AnsiColors.gone : AnsiColors.surface,
        ),
      ),
    ),
  );
}

/// The dock: one row, the rest behind **+N**. Nothing while no timer is
/// held or the keyboard is up.
class TimerDock extends ConsumerWidget {
  const TimerDock({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final timers = ref.watch(cookTimersProvider);
    if (timers.isEmpty || _keyboardUp(context)) return const SizedBox.shrink();
    final docked = timers.docked;
    final first = docked.first;
    final more = docked.length - 1;
    final awake = ref.watch(keepScreenOnProvider);
    final note = ref.watch(webTabNoteProvider);
    return DecoratedBox(
      decoration: const BoxDecoration(
        color: AnsiColors.surface,
        border: Border(top: BorderSide(color: AnsiColors.line)),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(
                  child: TimerRow(
                    timer: first,
                    now: timers.now,
                    onPress: () => openTimerStep(context, ref, first),
                    onLongPress: () => showTimerSheet(context, first.id),
                  ),
                ),
                if (more > 0) ...[
                  const SizedBox(width: 6),
                  FTappable(
                    onPress: () => showTimerList(context),
                    semanticsLabel: '$more more timers',
                    child: Container(
                      constraints: const BoxConstraints(
                        minWidth: 44,
                        minHeight: 40,
                      ),
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: AnsiColors.paper,
                        border: Border.all(color: AnsiColors.line),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Text(
                        '+$more',
                        style: ansiMono(size: 12, weight: FontWeight.w500),
                      ),
                    ),
                  ),
                ],
                if (awake) ...[
                  const SizedBox(width: 8),
                  const Icon(
                    FLucideIcons.sun,
                    size: 16,
                    color: AnsiColors.herb,
                    semanticLabel: 'Screen kept on',
                  ),
                ],
              ],
            ),
            if (note) ...[
              const SizedBox(height: 6),
              DecoratedBox(
                decoration: BoxDecoration(
                  color: AnsiColors.caution,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 9,
                    vertical: 6,
                  ),
                  child: Text(
                    'Keep this tab open — a closed tab can’t ring.',
                    style: ansiMono(size: 11, color: AnsiColors.cautionInk),
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// One timer as the dock's row: the step in a mono column, the recipe's
/// whole title cut at its end, and the count.
class TimerRow extends StatelessWidget {
  const TimerRow({
    required this.timer,
    required this.now,
    required this.onPress,
    this.onLongPress,
    super.key,
  });

  final CookTimer timer;
  final DateTime now;
  final VoidCallback onPress;
  final VoidCallback? onLongPress;

  @override
  Widget build(BuildContext context) {
    final state = timer.stateAt(now);
    final ink = timerInk(state);
    final count = formatTimerClock(timer.left(now));
    return FTappable(
      onPress: onPress,
      onLongPress: onLongPress,
      semanticsLabel: _spoken(timer, state, count),
      child: TimerWash(
        state: state,
        share: timer.remainingShare(now),
        radius: 10,
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
        child: Row(
          children: [
            Text(
              '${timer.step + 1}',
              style: ansiMono(
                size: 11,
                weight: FontWeight.w600,
                color: state == CookTimerState.running ? AnsiColors.herb : ink,
              ),
            ),
            const SizedBox(width: 9),
            Expanded(
              child: Text(
                timer.recipeTitle,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: ansiSans(size: 13, color: ink),
              ),
            ),
            const SizedBox(width: 8),
            Text(
              count,
              style: ansiMono(size: 13, weight: FontWeight.w500, color: ink),
            ),
          ],
        ),
      ),
    );
  }
}

String _spoken(CookTimer timer, CookTimerState state, String count) {
  final what = '${timer.recipeTitle}, step ${timer.step + 1}';
  return switch (state) {
    CookTimerState.running => '$what, $count left',
    CookTimerState.paused => '$what, paused at $count',
    CookTimerState.due => '$what, done',
  };
}

/// The dock opened: every timer, its title whole on up to two lines, one
/// verb beside its count.
Future<void> showTimerList(BuildContext context) {
  // The rows open a step from the dock's own place, not the sheet's.
  final host = context;
  return showAnsiSheet<void>(
    context: context,
    builder: (sheetContext) => _TimerList(
      onOpen: (ref, timer) {
        Navigator.of(sheetContext).pop();
        if (host.mounted) openTimerStep(host, ref, timer);
      },
      close: () => Navigator.of(sheetContext).maybePop(),
    ),
  );
}

class _TimerList extends ConsumerWidget {
  const _TimerList({required this.onOpen, required this.close});

  final void Function(WidgetRef ref, CookTimer timer) onOpen;
  final VoidCallback close;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    ref.listen(cookTimersProvider, (_, timers) {
      if (timers.isEmpty) close();
    });
    final timers = ref.watch(cookTimersProvider);
    final docked = timers.docked;
    return AnsiSheetShell(
      title: docked.length == 1 ? '1 timer' : '${docked.length} timers',
      centerTitle: false,
      dismiss: AnsiSheetDismiss.close,
      children: [
        const SizedBox(height: 12),
        for (final t in docked) ...[
          TimerListRow(timer: t, now: timers.now, onOpen: () => onOpen(ref, t)),
          const SizedBox(height: 6),
        ],
      ],
    );
  }
}

/// One timer in the opened list or the sidebar: the title on up to two
/// lines, the step and its ring time under it, the count, and — unless
/// [compact] — one verb.
class TimerListRow extends ConsumerWidget {
  const TimerListRow({
    required this.timer,
    required this.now,
    required this.onOpen,
    this.compact = false,
    super.key,
  });

  final CookTimer timer;
  final DateTime now;
  final VoidCallback onOpen;
  final bool compact;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = timer.stateAt(now);
    final ink = timerInk(state);
    final count = formatTimerClock(timer.left(now));
    final notifier = ref.read(cookTimersProvider.notifier);
    final meta = switch (state) {
      CookTimerState.running =>
        compact
            ? 'step ${timer.step + 1}'
            : 'step ${timer.step + 1} · rings at '
                  '${formatClockTime(timer.endsAt!)}',
      CookTimerState.paused =>
        // The dashed edge already says it in the sidebar's narrow column.
        compact ? 'step ${timer.step + 1}' : 'step ${timer.step + 1} · paused',
      CookTimerState.due =>
        compact
            ? 'step ${timer.step + 1}'
            : 'step ${timer.step + 1} · rang at '
                  '${formatClockTime(timer.endsAt!)}',
    };
    return TimerWash(
      state: state,
      share: timer.remainingShare(now),
      radius: 12,
      padding: EdgeInsets.fromLTRB(compact ? 9 : 12, 9, compact ? 9 : 8, 9),
      child: Row(
        children: [
          Expanded(
            child: FTappable(
              onPress: onOpen,
              onLongPress: () => showTimerSheet(context, timer.id),
              semanticsLabel: _spoken(timer, state, count),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          timer.recipeTitle,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: ansiSans(
                            size: compact ? 12.5 : 14,
                            weight: FontWeight.w500,
                            color: state == CookTimerState.running
                                ? AnsiColors.ink
                                : ink,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          meta,
                          style: ansiMono(
                            size: 10.5,
                            color: state == CookTimerState.due
                                ? AnsiColors.surface
                                : AnsiColors.muted,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    count,
                    style: ansiMono(
                      size: compact ? 12.5 : 16,
                      weight: FontWeight.w500,
                      color: state == CookTimerState.running
                          ? AnsiColors.ink
                          : ink,
                    ),
                  ),
                ],
              ),
            ),
          ),
          if (!compact) ...[
            const SizedBox(width: 8),
            switch (state) {
              CookTimerState.due => _BandButton(
                label: 'Stop',
                solid: true,
                onPress: () => notifier.stop(timer.id),
              ),
              CookTimerState.paused => _RowVerb(
                icon: FLucideIcons.play,
                label: 'Resume',
                onPress: () => notifier.resume(timer.id),
              ),
              CookTimerState.running => _RowVerb(
                icon: FLucideIcons.pause,
                label: 'Pause',
                onPress: () => notifier.pause(timer.id),
              ),
            },
          ],
        ],
      ),
    );
  }
}

class _RowVerb extends StatelessWidget {
  const _RowVerb({
    required this.icon,
    required this.label,
    required this.onPress,
  });

  final IconData icon;
  final String label;
  final VoidCallback onPress;

  @override
  Widget build(BuildContext context) => FTappable(
    onPress: onPress,
    semanticsLabel: label,
    child: Container(
      width: 40,
      height: 40,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: AnsiColors.surface,
        border: Border.all(color: AnsiColors.line),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Icon(icon, size: 16, color: AnsiColors.ink),
    ),
  );
}

/// On a desk the dock is the opened list, always open, in the sidebar above
/// the footer door — the one surface that survives a push there. Nothing
/// while no timer is held.
class TimerSideList extends ConsumerWidget {
  const TimerSideList({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final timers = ref.watch(cookTimersProvider);
    if (timers.isEmpty) return const SizedBox.shrink();
    final docked = timers.docked;
    final awake = ref.watch(keepScreenOnProvider);
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(height: 1, color: AnsiColors.line),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: Text('TIMERS · ${docked.length}', style: ansiLabel()),
              ),
              if (awake)
                const Icon(
                  FLucideIcons.sun,
                  size: 14,
                  color: AnsiColors.herb,
                  semanticLabel: 'Screen kept on',
                ),
            ],
          ),
          const SizedBox(height: 8),
          for (final t in docked) ...[
            TimerListRow(
              timer: t,
              now: timers.now,
              compact: true,
              onOpen: () => openTimerStep(context, ref, t),
            ),
            const SizedBox(height: 6),
          ],
        ],
      ),
    );
  }
}

/// On the web, the tab's title counts the soonest timer down, so a desk
/// with other tabs open still sees it. Elsewhere it is [child] alone.
class TimerTabTitle extends ConsumerWidget {
  const TimerTabTitle({required this.child, required this.title, super.key});

  final Widget child;

  /// The app's own title, for when nothing runs.
  final String title;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (!kIsWeb) return child;
    final timers = ref.watch(cookTimersProvider);
    final first = timers.isEmpty ? null : timers.docked.first;
    return Title(
      title: first == null
          ? title
          : '⏱ ${formatTimerClock(first.left(timers.now))} · $title',
      color: AnsiColors.herb,
      child: child,
    );
  }
}
