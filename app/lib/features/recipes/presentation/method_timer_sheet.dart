/// The timer sheet. Timers come only from the extractor, from this sheet, or
/// from text the user selected and asked to have read; typed prose is never
/// pattern-matched into one (ADR-0004).
///
/// Steppers rather than free text, because a parser fails "an hour or so"
/// silently. Ragged values are kept: [formatTimerRange] prints "6 min 30 s".
library;

import 'package:flutter/widgets.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:forui/forui.dart';

import '../../../core/theme/ansi_theme.dart';
import '../../../core/theme/ansi_tokens.dart';
import '../../../shared/ansi_modals.dart';
import '../../../shared/ansi_sheet_shell.dart';
import '../../../shared/ansi_stepper_row.dart';
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

/// Opens the timer sheet, seeded with [lowSeconds]/[highSeconds] when editing a
/// timer or reading a selection. [removable] draws *Remove timer*.
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

  /// The sentence either side of the timer, so "Goes in as" shows the real
  /// line.
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

    return AnsiSheetShell(
      title: 'Timer',
      centerTitle: false,
      children: [
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
                  onChanged: (v) => high.value = v < low.value ? low.value : v,
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
    );
  }
}

/// Minutes and seconds, each on its own stepper. Seconds move in 15 s notches
/// without wrapping.
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
    return AnsiStepperRow(
      small: true,
      onDecrement: value <= 0 ? null : () => onChanged(value - step),
      onIncrement: value >= max ? null : () => onChanged(value + step),
      value: SizedBox(
        width: 44,
        child: Text(
          '$value',
          textAlign: TextAlign.center,
          style: ansiMono(size: 16, weight: FontWeight.w600),
        ),
      ),
      trailing: Padding(
        padding: const EdgeInsets.only(left: 6),
        child: Text(suffix, style: ansiMono(size: 12, color: AnsiColors.muted)),
      ),
    );
  }
}
