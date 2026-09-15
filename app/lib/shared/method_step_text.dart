/// The ONE renderer for a tokenized method step — prose interleaved with
/// ingredient and timer chips, produced by the pure [foldMethod] (never
/// render-time text matching, ADR-0004).
///
/// The recipe page and the import review screen show the same method with the
/// same chips. The only thing that legitimately varies between them is the
/// prose type size — and, on the recipe page alone, whether a chip can be
/// *ticked off*. Every knob for that is null by default, so a surface that
/// hands none of them over renders exactly what it always did.
///
/// **Two struck states, and they must not read alike.** A chip can be crossed
/// off by the cook ([MethodStepText.struckChips], [MethodStepText.stepStruck])
/// — *I have added that* — or left out by the week
/// ([MethodStepText.weekExcluded]) — *we are not cooking that this time*. The
/// first is muted **and** ruled through, the Shop's own "got it" style; the
/// second is muted only. One is a thing you did, the other a thing the plan
/// says, and a cook glancing back at a step has to be able to tell them apart.
library;

import 'package:flutter/widgets.dart';
import 'package:forui/forui.dart';

import '../core/theme/ansi_theme.dart';
import '../core/theme/ansi_tokens.dart';
import '../core/units/units.dart';
import '../features/recipes/domain/method_step.dart';
import '../features/recipes/domain/recipe.dart';

/// Renders [step]'s tokens, deriving each chip's live amount from [lineById]
/// (scaled by [factor]). [textSize] is the prose size; the chips size with it.
///
/// ## Ticking off
///
/// A chip is addressed by its **ordinal in the step** — the nth ingredient chip
/// in reading order, counting a collective's constituents as the chips they
/// are and skipping timers, which are never tappable. That ordinal is the whole
/// identity: the caller holds the set, so a chip identifies itself by where it
/// is rather than by a line id, and two chips on the same line tick
/// independently (a cook adds the garlic twice).
///
/// [stepStruck] is the step's own answer and it wins over every chip in it,
/// because text decoration does not cross into a [WidgetSpan]: a struck step
/// whose chips stayed live would be a ruled sentence with bright words in it.
/// It does not *clear* the chips' own state — striking a step and un-striking
/// it leaves each chip exactly as the cook had it.
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

  /// The ordinals of the chips the cook has ticked off. Null on a surface that
  /// does not tick anything off.
  final Set<int>? struckChips;

  /// Whether the whole step is ticked off — its prose ruled through and every
  /// chip in it struck with it.
  final bool stepStruck;

  /// Ticks the chip at that ordinal. Null leaves every chip inert, with no tap
  /// target, no cursor and no focus stop — which is what the import review and
  /// the editor's preview want.
  final ValueChanged<int>? onToggleChip;

  /// The line ids a week leaves out. Their chips read muted, never ruled
  /// through: see the library doc on the two struck states.
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
          // The portion/quantity rides on the label chip; the constituents
          // that follow are names only — and they, not the prose, are what
          // abuts this chip, so there is nothing to deduplicate against.
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
                // A mixture is out only when everything in it is out — one
                // excluded constituent leaves the mixture itself live, and
                // says so on the constituent's own chip.
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

  /// A blank-labelled collective as the run it actually is — `Kale, Avocado,
  /// Garlic` — full-size chips, no parentheses (there is no label to bracket),
  /// any step-named portion riding on the first.
  ///
  /// One span per chip with real text between them, never one chip label
  /// holding every name: a chip is one atomic box to the line breaker, so a
  /// seven-ingredient catch-all would run straight off a phone screen instead
  /// of wrapping. Same mechanics as [_constituentSpans].
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

  /// A collective chip's constituents as `(a b c)`.
  ///
  /// One span per chip with real whitespace between them, never a single
  /// WidgetSpan holding a Row: a WidgetSpan is an atomic box to the line
  /// breaker, so a packed run of eight constituents would overflow the step
  /// instead of wrapping onto the next line.
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

/// The imprecise unit words a chip can print as its amount — `pinch`, `dash`,
/// `handful`, `to taste`. An imprecise line has no number, so the fold gives
/// the chip its unit's word.
final _impreciseWords = {
  for (final unit in kAllUnits)
    if (unit.family == UnitFamily.imprecise) unit.label.toLowerCase(),
};

/// [amount], unless the prose that follows the chip already says it.
///
/// An imprecise line's amount IS a phrase of the sentence, and a source step
/// usually writes it out: with the pill printed too, "Season with salt to
/// taste" reads *salt to taste to taste*. The rule is narrow on purpose — only
/// an imprecise word, and only when the very next prose opens with it — so a
/// chip whose sentence does not repeat the word keeps its pill and nothing is
/// lost.
///
/// It lives here rather than in `foldMethod` because it is a fact about two
/// adjacent spans, and the fold is a per-token map: the renderer is the first
/// place that holds the chip and the prose after it at once.
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
/// An **ingredient** chip is the ingredient's word set bold in `herbDeep`,
/// with — when the fold derived one — its live [amount] in a small herb-soft
/// mono pill after it. No box around the word: a step is a sentence, and a
/// boxed noun in the middle of one breaks the reading. The pill is the marked
/// thing because the number is the part that is live, moving with the scaler.
/// Nothing pads the chip sideways either, so the comma after it hugs the word.
///
/// A [timer] chip keeps its outlined paper pill and clock glyph: it is not a
/// word in the sentence, it is a measurement the step hands you. It is also
/// the one chip that never ticks off: a duration is not a thing you add.
///
/// **[struck]** is the cook's tick — the word muted and ruled through, the
/// pill's ground dropping from the herb wash to the hairline. **[weekStruck]**
/// is the week leaving the line out — the same muting, and deliberately no
/// rule, so the two never read as one another. The geometry does not move
/// under either: a struck chip occupies the pixels it did, because a sentence
/// that reflows as you tick through it is a sentence you lose your place in.
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

  /// Ticked off by the cook this session: muted **and** ruled through.
  final bool struck;

  /// Left out by the week this page was opened from: muted only.
  final bool weekStruck;

  /// Toggles [struck]. Null leaves the chip inert — no target, no cursor, no
  /// focus stop.
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    // A ref the fold could name neither from its label nor from its line item
    // would render as a bare number — say so instead of showing a naked digit.
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
    // Labelled, so the sweep that bans a bare tap around a lone glyph does not
    // apply — and a word-wide target needs no growing on a phone.
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
