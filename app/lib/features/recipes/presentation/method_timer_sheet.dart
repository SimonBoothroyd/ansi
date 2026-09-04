/// The timer sheet (0022 D4, design board frame d) — a timer is data that
/// happens to read as words.
///
/// The only door. **Nothing sniffs your prose:** typing "roast for 25 minutes"
/// produces no timer, because pattern-matching prose into structured data at
/// edit time is render-time matching wearing a hat (ADR-0004), and it would
/// surprise the author more often than it helped. Timers come from the
/// extractor, from this sheet's steppers, or from a run of text the user
/// deliberately selected and asked us to read.
///
/// Steppers, not a free-text field: "1h30", "an hour or so" and "overnight"
/// all fail a parser silently, and a wrong countdown is worse than none. The
/// sheet also never rounds a ragged value away — [formatTimerRange] keeps
/// "6 min 30 s" on purpose, and so does this.
library;

import 'dart:math' as math;

import 'package:flutter/widgets.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:forui/forui.dart';

import '../../../core/theme/ansi_theme.dart';
import '../../../core/theme/ansi_tokens.dart';
import '../../../shared/ansi_modals.dart';
import '../domain/method_step.dart';

/// What the sheet resolved to: a span, or the request to unmake one.
sealed class TimerSheetResult {
  const TimerSheetResult();
}

/// The seconds to write. [highSeconds] equals [lowSeconds] for a single time.
final class TimerSet extends TimerSheetResult {
  const TimerSet(this.lowSeconds, this.highSeconds);

  final int lowSeconds;
  final int highSeconds;
}

/// Remove the timer, **keeping its words** — the sentence is untouched.
final class TimerRemoved extends TimerSheetResult {
  const TimerRemoved();
}

/// Opens the timer sheet, seeded with [lowSeconds]/[highSeconds] when editing
/// an existing timer (or with what a selection parsed to). [removable] draws
/// *Remove timer*, which only an existing timer has.
Future<TimerSheetResult?> showMethodTimerSheet(
  BuildContext context, {
  int? lowSeconds,
  int? highSeconds,
  bool removable = false,
  String prosePrefix = '',
  String proseSuffix = '',
}) => showAnsiSheet<TimerSheetResult>(
  context: context,
  builder: (sheetContext) => _TimerSheet(
    lowSeconds: lowSeconds,
    highSeconds: highSeconds,
    removable: removable,
    prosePrefix: prosePrefix,
    proseSuffix: proseSuffix,
    onDone: (result) => Navigator.of(sheetContext).pop(result),
  ),
);

class _TimerSheet extends HookWidget {
  const _TimerSheet({
    required this.removable,
    required this.prosePrefix,
    required this.proseSuffix,
    required this.onDone,
    this.lowSeconds,
    this.highSeconds,
  });

  final int? lowSeconds;
  final int? highSeconds;
  final bool removable;

  /// The sentence either side of where the timer lands, so "Goes in as" can
  /// show the real line rather than a bare duration.
  final String prosePrefix;
  final String proseSuffix;
  final ValueChanged<TimerSheetResult> onDone;

  @override
  Widget build(BuildContext context) {
    final low = useState<int>(lowSeconds ?? 600);
    final high = useState<int?>(
      highSeconds == null || highSeconds == lowSeconds ? null : highSeconds,
    );
    final end = high.value;
    final reads = formatTimerRange(low.value, end ?? low.value);

    return Container(
      decoration: const BoxDecoration(
        color: AnsiColors.paper,
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        border: Border(top: BorderSide(color: AnsiColors.line)),
      ),
      child: Padding(
        padding: EdgeInsets.only(
          left: 20,
          right: 20,
          top: 12,
          bottom:
              math.max(
                MediaQuery.viewInsetsOf(context).bottom,
                MediaQuery.paddingOf(context).bottom,
              ) +
              12,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: () => Navigator.of(context).pop(),
                  child: const Icon(FLucideIcons.x, size: 22),
                ),
                const SizedBox(width: 12),
                Text('Timer', style: ansiSerif(size: 18)),
              ],
            ),
            const SizedBox(height: 14),
            Text('FROM', style: ansiLabel()),
            const SizedBox(height: 6),
            _DurationStepper(
              seconds: low.value,
              onChanged: (v) {
                low.value = v;
                final e = high.value;
                if (e != null && e < v) high.value = v;
              },
            ),
            const SizedBox(height: 14),
            Row(
              children: [
                Text('TO', style: ansiLabel()),
                const SizedBox(width: 6),
                Text(
                  '· optional',
                  style: ansiMono(size: 11, color: AnsiColors.muted),
                ),
              ],
            ),
            const SizedBox(height: 6),
            if (end == null)
              Align(
                alignment: Alignment.centerLeft,
                child: FButton(
                  variant: FButtonVariant.ghost,
                  size: FButtonSizeVariant.sm,
                  prefix: const Icon(FLucideIcons.plus),
                  onPress: () => high.value = low.value + 300,
                  child: const Text('Add an end'),
                ),
              )
            else
              Row(
                children: [
                  Expanded(
                    child: _DurationStepper(
                      seconds: end,
                      onChanged: (v) =>
                          high.value = v < low.value ? low.value : v,
                    ),
                  ),
                  FButton.icon(
                    variant: FButtonVariant.ghost,
                    onPress: () => high.value = null,
                    child: const Icon(FLucideIcons.x),
                  ),
                ],
              ),
            const SizedBox(height: 18),
            Text('GOES IN AS', style: ansiLabel()),
            const SizedBox(height: 6),
            Text(
              '$prosePrefix$reads$proseSuffix',
              style: ansiSans(size: 14, height: 1.4),
            ),
            const SizedBox(height: 16),
            FButton(
              onPress: () => onDone(TimerSet(low.value, end ?? low.value)),
              child: Text(removable ? 'Save' : 'Insert'),
            ),
            if (removable) ...[
              const SizedBox(height: 8),
              FButton(
                variant: FButtonVariant.ghost,
                onPress: () => onDone(const TimerRemoved()),
                child: const Text('Remove timer · keeps the words'),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// Minutes and seconds, each on its own stepper. Seconds move in 15s notches
/// (and wrap nothing) so a ragged "6 min 30 s" is reachable without a keyboard
/// and nothing is ever rounded away.
class _DurationStepper extends StatelessWidget {
  const _DurationStepper({required this.seconds, required this.onChanged});

  final int seconds;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    final minutes = seconds ~/ 60;
    final rest = seconds % 60;
    return Row(
      children: [
        _Notch(
          value: minutes,
          suffix: 'min',
          onChanged: (v) => onChanged(v * 60 + rest),
        ),
        const SizedBox(width: 10),
        _Notch(
          value: rest,
          suffix: 's',
          step: 15,
          max: 45,
          onChanged: (v) => onChanged(minutes * 60 + v),
        ),
      ],
    );
  }
}

class _Notch extends StatelessWidget {
  const _Notch({
    required this.value,
    required this.suffix,
    required this.onChanged,
    this.step = 1,
    this.max = 600,
  });

  final int value;
  final String suffix;
  final int step;
  final int max;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        FButton.icon(
          size: FButtonSizeVariant.sm,
          onPress: value <= 0 ? null : () => onChanged(value - step),
          child: const Icon(FLucideIcons.minus),
        ),
        SizedBox(
          width: 44,
          child: Text(
            '$value',
            textAlign: TextAlign.center,
            style: ansiMono(size: 16, weight: FontWeight.w600),
          ),
        ),
        FButton.icon(
          size: FButtonSizeVariant.sm,
          onPress: value >= max ? null : () => onChanged(value + step),
          child: const Icon(FLucideIcons.plus),
        ),
        const SizedBox(width: 6),
        Text(suffix, style: ansiMono(size: 12, color: AnsiColors.muted)),
      ],
    );
  }
}
