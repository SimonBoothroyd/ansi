/// The ground a kitchen timer is drawn on, in its four states: ready (the
/// recipe's words, outlined), running (a herb wash that drains as it goes),
/// paused (dashed and muted) and due (Gone red). The method's chip, the
/// dock's row and the dock's list all draw on it, so a timer reads the same
/// wherever it is.
library;

import 'package:flutter/widgets.dart';

import '../core/theme/ansi_tokens.dart';
import '../features/timers/domain/cook_timer.dart';
import 'dashed_border_box.dart';

/// The running wash's edge: herb at a third, so the box holds its shape on
/// white as the wash drains out of it.
const _runningLine = Color(0x552C6A3A);

/// The ink a timer's words take on its ground. Null is a timer not started.
Color timerInk(CookTimerState? state) => switch (state) {
  null => AnsiColors.ink,
  CookTimerState.running => AnsiColors.herbDeep,
  CookTimerState.paused => AnsiColors.muted,
  CookTimerState.due => AnsiColors.surface,
};

class TimerWash extends StatelessWidget {
  const TimerWash({
    required this.state,
    required this.child,
    this.share = 1,
    this.radius = 6,
    this.padding = const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
    super.key,
  });

  /// Null for a timer not started.
  final CookTimerState? state;

  /// The share of the count still to go, 1 to 0; the wash covers that much.
  final double share;
  final double radius;
  final EdgeInsetsGeometry padding;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final shape = BorderRadius.circular(radius);
    return switch (state) {
      CookTimerState.paused => DashedBorderBox(
        color: AnsiColors.muted,
        radius: radius,
        padding: padding,
        child: child,
      ),
      _ => DecoratedBox(
        decoration: BoxDecoration(
          borderRadius: shape,
          border: Border.all(
            color: switch (state) {
              CookTimerState.running => _runningLine,
              CookTimerState.due => AnsiColors.gone,
              _ => AnsiColors.line,
            },
          ),
          color: switch (state) {
            null => AnsiColors.paper,
            CookTimerState.due => AnsiColors.gone,
            _ => null,
          },
          gradient: state == CookTimerState.running
              ? LinearGradient(
                  colors: const [
                    AnsiColors.herbSoft,
                    AnsiColors.herbSoft,
                    AnsiColors.surface,
                    AnsiColors.surface,
                  ],
                  stops: [0, share, share, 1],
                )
              : null,
        ),
        child: Padding(padding: padding, child: child),
      ),
    };
  }
}
