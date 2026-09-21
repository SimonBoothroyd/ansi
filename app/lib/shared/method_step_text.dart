/// The one renderer for a tokenized method step: prose interleaved with
/// ingredient and timer chips from the pure [foldMethod] (ADR-0004).
///
/// Two struck states that must not read alike: ticked off by the cook is
/// muted and ruled through; left out by the week
/// ([MethodStepText.weekExcluded]) is muted only.
library;

import 'package:flutter/widgets.dart';
import 'package:forui/forui.dart';

import '../core/theme/ansi_theme.dart';
import '../core/theme/ansi_tokens.dart';
import '../core/units/units.dart';
import '../features/recipes/domain/method_step.dart';
import '../features/recipes/domain/recipe.dart';

/// Renders [step]'s tokens, deriving each chip's live amount from [lineById]
/// scaled by [factor]. [textSize] is the prose size; the chips size with it.
///
/// A chip is addressed by its ordinal among the step's ingredient chips
/// (constituents counted, timers skipped), so two chips on one line tick
/// independently. [stepStruck] overrides every chip, because text decoration
/// does not cross into a [WidgetSpan]; it does not clear the chips' own state.
class MethodStepText extends StatelessWidget {
  const MethodStepText({
    required this.step,
    required this.lineById,
    this.factor = 1,
    this.textSize = 16,
    this.struckChips,
    this.stepStruck = false,
    this.onToggleChip,
    this.weekExcluded = const {},
    super.key,
  });

  final MethodStep step;
  final Map<String, LineItem> lineById;
  final double factor;
  final double textSize;

  /// The ordinals of the chips ticked off. Null where nothing ticks off.
  final Set<int>? struckChips;

  /// Whether the whole step is ticked off.
  final bool stepStruck;

  /// Ticks the chip at that ordinal. Null leaves every chip inert.
  final ValueChanged<int>? onToggleChip;

  /// The line ids a week leaves out. Their chips read muted, never ruled.
  final Set<String> weekExcluded;

  @override
  Widget build(BuildContext context) {
    final spans = foldMethod(step, lineById: lineById, factor: factor);
    final children = <InlineSpan>[];
    var chip = 0;
    for (var i = 0; i < spans.length; i++) {
      final span = spans[i];
      switch (span) {
        case MethodTextSpan(:final text):
          children.add(TextSpan(text: text));
        case MethodTimerSpan(:final text):
          children.add(
            _chip(MethodChip(label: text, timer: true, textSize: textSize)),
          );
        case MethodChipSpan(
          :final label,
          :final amount,
          :final constituents,
          :final lineIds,
        ):
          // A collective with no label of its own IS its constituents.
          if (label.isEmpty && constituents.isNotEmpty) {
            children.addAll(
              _collectiveRun(constituents, lineIds, amount, chip),
            );
            chip += constituents.length;
            break;
          }
          // The portion rides on the label chip; the constituents that follow
          // are names only.
          children.add(
            _chip(
              MethodChip(
                label: label,
                amount: constituents.isEmpty
                    ? _unrepeatedAmount(
                        amount,
                        i + 1 < spans.length ? spans[i + 1] : null,
                      )
                    : amount,
                textSize: textSize,
                struck: _struck(chip),
                // A mixture is out only when every constituent is out.
                weekStruck: lineIds.isNotEmpty && lineIds.every(_excluded),
                onTap: _toggle(chip),
              ),
            ),
          );
          chip++;
          if (constituents.isNotEmpty) {
            children.addAll(_constituentSpans(constituents, lineIds, chip));
            chip += constituents.length;
          }
      }
    }
    final prose = ansiSans(size: textSize, height: 1.5);
    return Text.rich(
      TextSpan(
        children: children,
        style: stepStruck
            ? prose.copyWith(
                color: AnsiColors.muted,
                decoration: TextDecoration.lineThrough,
              )
            : prose,
      ),
    );
  }

  bool _struck(int chip) =>
      stepStruck || (struckChips?.contains(chip) ?? false);

  bool _excluded(String lineId) => weekExcluded.contains(lineId);

  VoidCallback? _toggle(int chip) {
    final onToggle = onToggleChip;
    return onToggle == null ? null : () => onToggle(chip);
  }

  /// A blank-labelled collective as a run of chips: `Kale, Avocado, Garlic`.
  ///
  /// One span per chip with real text between them: a chip is one atomic box
  /// to the line breaker, so a single chip holding every name would overflow
  /// instead of wrapping.
  Iterable<InlineSpan> _collectiveRun(
    List<String> names,
    List<String> lineIds,
    String? amount,
    int firstChip,
  ) sync* {
    for (var i = 0; i < names.length; i++) {
      if (i > 0) yield const TextSpan(text: ', ');
      yield _chip(
        MethodChip(
          label: names[i],
          amount: i == 0 ? amount : null,
          textSize: textSize,
          struck: _struck(firstChip + i),
          weekStruck: i < lineIds.length && _excluded(lineIds[i]),
          onTap: _toggle(firstChip + i),
        ),
      );
    }
  }

  /// A collective chip's constituents as `(a b c)`, one span per chip so the
  /// run wraps (see [_collectiveRun]).
  Iterable<InlineSpan> _constituentSpans(
    List<String> constituents,
    List<String> lineIds,
    int firstChip,
  ) sync* {
    yield const TextSpan(text: ' (');
    for (var i = 0; i < constituents.length; i++) {
      if (i > 0) yield const TextSpan(text: ' ');
      yield _chip(
        MethodChip(
          label: constituents[i],
          textSize: textSize - 1,
          struck: _struck(firstChip + i),
          weekStruck: i < lineIds.length && _excluded(lineIds[i]),
          onTap: _toggle(firstChip + i),
        ),
      );
    }
    yield const TextSpan(text: ')');
  }

  WidgetSpan _chip(MethodChip chip) =>
      WidgetSpan(alignment: PlaceholderAlignment.middle, child: chip);
}

/// The imprecise unit words a chip prints as its amount, having no number.
final _impreciseWords = {
  for (final unit in kAllUnits)
    if (unit.family == UnitFamily.imprecise) unit.label.toLowerCase(),
};

/// [amount], unless it is an imprecise word the very next prose opens with,
/// which would read "salt to taste to taste".
///
/// Here rather than in `foldMethod` because it needs the chip and the prose
/// after it together.
String? _unrepeatedAmount(String? amount, MethodSpan? next) {
  if (amount == null) return null;
  if (!_impreciseWords.contains(amount.toLowerCase())) return amount;
  if (next is! MethodTextSpan) return amount;
  final prose = next.text
      .replaceFirst(RegExp('^[\\s,.;:!?()\'"–—-]+'), '')
      .toLowerCase();
  return prose.startsWith(amount.toLowerCase()) ? null : amount;
}

/// One inline chip.
///
/// An ingredient chip is its word in bold `herbDeep`, unboxed, with its live
/// [amount] in a small mono pill. A [timer] chip keeps its outlined pill and
/// clock glyph and never ticks off. [struck] mutes and rules through;
/// [weekStruck] only mutes. Neither moves the geometry, so the step never
/// reflows as it is ticked through.
class MethodChip extends StatelessWidget {
  const MethodChip({
    required this.label,
    this.amount,
    this.timer = false,
    this.textSize = 16,
    this.struck = false,
    this.weekStruck = false,
    this.onTap,
    super.key,
  });

  final String label;
  final String? amount;
  final bool timer;
  final double textSize;

  /// Ticked off by the cook: muted and ruled through.
  final bool struck;

  /// Left out by the week: muted only.
  final bool weekStruck;

  /// Toggles [struck]. Null leaves the chip inert.
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    // A ref the fold could not name would render as a bare number.
    final text = label.trim().isEmpty && !timer ? 'ingredient' : label;
    if (timer) return _timer(text);

    final amount = this.amount;
    final muted = struck || weekStruck;
    final chip = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          text,
          style: ansiSans(
            size: textSize - 1,
            color: muted ? AnsiColors.muted : AnsiColors.herbDeep,
            weight: FontWeight.w600,
          ).copyWith(decoration: struck ? TextDecoration.lineThrough : null),
        ),
        if (amount != null) ...[
          const SizedBox(width: 4),
          DecoratedBox(
            decoration: BoxDecoration(
              color: muted ? AnsiColors.line : AnsiColors.herbSoft,
              borderRadius: BorderRadius.circular(5),
            ),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
              child: Text(
                amount,
                style: ansiMono(
                  size: 12,
                  color: muted ? AnsiColors.muted : AnsiColors.herb,
                ),
              ),
            ),
          ),
        ],
      ],
    );
    final onTap = this.onTap;
    if (onTap == null) return chip;
    // Labelled, so the structural ban on a bare tap around a lone glyph does
    // not apply.
    return FTappable(
      onPress: onTap,
      semanticsLabel: text,
      behavior: HitTestBehavior.opaque,
      child: chip,
    );
  }

  Widget _timer(String text) => Padding(
    padding: const EdgeInsets.symmetric(horizontal: 1),
    child: DecoratedBox(
      decoration: BoxDecoration(
        color: AnsiColors.paper,
        border: Border.all(color: AnsiColors.line),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(FLucideIcons.timer, size: 12, color: AnsiColors.muted),
            const SizedBox(width: 4),
            Text(text, style: ansiMono(size: 12)),
          ],
        ),
      ),
    ),
  );
}
