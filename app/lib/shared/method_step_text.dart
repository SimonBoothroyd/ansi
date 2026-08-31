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
    final spans = foldMethod(step, lineById: lineById, factor: factor);
    return Text.rich(
      TextSpan(
        children: [
          for (final span in spans)
            switch (span) {
              MethodTextSpan(:final text) => TextSpan(text: text),
              MethodChipSpan(:final label, :final amount) => WidgetSpan(
                alignment: PlaceholderAlignment.middle,
                child: MethodChip(
                  label: label,
                  amount: amount,
                  textSize: textSize,
                ),
              ),
              MethodTimerSpan(:final text) => WidgetSpan(
                alignment: PlaceholderAlignment.middle,
                child: MethodChip(label: text, timer: true, textSize: textSize),
              ),
            },
        ],
        style: miseSans(size: textSize, height: 1.5),
      ),
    );
  }
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
