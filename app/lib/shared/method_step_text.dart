/// The ONE renderer for a tokenized method step — prose interleaved with
/// ingredient and timer chips, produced by the pure [foldMethod] (never
/// render-time text matching, ADR-0004).
///
/// The recipe page and the import review screen show the same method with the
/// same chips; they used to carry two near-identical private copies of this
/// widget, which drifted. The only thing that legitimately varies between them
/// is the prose type size, so that is the only knob.
library;

import 'package:flutter/widgets.dart';
import 'package:forui/forui.dart';

import '../core/theme/mise_theme.dart';
import '../core/theme/mise_tokens.dart';
import '../features/recipes/domain/method_step.dart';
import '../features/recipes/domain/recipe.dart';

/// Renders [step]'s tokens, deriving each chip's live amount from [lineById]
/// (scaled by [factor]). [textSize] is the prose size; the chips size with it.
class MethodStepText extends StatelessWidget {
  const MethodStepText({
    required this.step,
    required this.lineById,
    this.factor = 1,
    this.textSize = 16,
    super.key,
  });

  final MethodStep step;
  final Map<String, LineItem> lineById;
  final double factor;
  final double textSize;

  @override
  Widget build(BuildContext context) {
    final children = <InlineSpan>[];
    for (final span in foldMethod(step, lineById: lineById, factor: factor)) {
      switch (span) {
        case MethodTextSpan(:final text):
          children.add(TextSpan(text: text));
        case MethodTimerSpan(:final text):
          children.add(
            _chip(MethodChip(label: text, timer: true, textSize: textSize)),
          );
        case MethodChipSpan(:final label, :final amount, :final constituents):
          // The portion/quantity rides on the label chip; the constituents
          // that follow are names only.
          children.add(
            _chip(MethodChip(label: label, amount: amount, textSize: textSize)),
          );
          if (constituents.isNotEmpty) {
            children.addAll(_constituentSpans(constituents));
          }
      }
    }
    return Text.rich(
      TextSpan(
        children: children,
        style: miseSans(size: textSize, height: 1.5),
      ),
    );
  }

  /// A collective chip's constituents as `(a b c)`.
  ///
  /// One span per chip with real whitespace between them, never a single
  /// WidgetSpan holding a Row: a WidgetSpan is an atomic box to the line
  /// breaker, so a packed run of eight constituents would overflow the step
  /// instead of wrapping onto the next line.
  Iterable<InlineSpan> _constituentSpans(List<String> constituents) sync* {
    yield const TextSpan(text: ' (');
    for (var i = 0; i < constituents.length; i++) {
      if (i > 0) yield const TextSpan(text: ' ');
      yield _chip(MethodChip(label: constituents[i], textSize: textSize - 1));
    }
    yield const TextSpan(text: ')');
  }

  WidgetSpan _chip(MethodChip chip) =>
      WidgetSpan(alignment: PlaceholderAlignment.middle, child: chip);
}

/// One inline chip. An ingredient chip is the herb-soft pill carrying the
/// ingredient [label] and, when the fold derived one, its live [amount]; a
/// [timer] chip is the outlined paper pill with the clock glyph. One widget
/// with a flag rather than two: they differ only in skin.
class MethodChip extends StatelessWidget {
  const MethodChip({
    required this.label,
    this.amount,
    this.timer = false,
    this.textSize = 16,
    super.key,
  });

  final String label;
  final String? amount;
  final bool timer;
  final double textSize;

  @override
  Widget build(BuildContext context) {
    // A ref the fold could name neither from its label nor from its line item
    // would render as a bare number — say so instead of showing a naked digit.
    final text = label.trim().isEmpty && !timer ? 'ingredient' : label;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 1),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: timer ? MiseColors.paper : MiseColors.herbSoft,
          border: timer ? Border.all(color: MiseColors.line) : null,
          borderRadius: BorderRadius.circular(6),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (timer) ...[
                const Icon(
                  FLucideIcons.timer,
                  size: 12,
                  color: MiseColors.muted,
                ),
                const SizedBox(width: 4),
              ],
              Text(
                text,
                style: timer
                    ? miseMono(size: 12)
                    : miseSans(
                        size: textSize - 1,
                        color: MiseColors.herbDeep,
                        weight: FontWeight.w600,
                      ),
              ),
              if (amount != null) ...[
                const SizedBox(width: 5),
                Text(
                  amount!,
                  style: miseMono(size: 12, color: MiseColors.herb),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
