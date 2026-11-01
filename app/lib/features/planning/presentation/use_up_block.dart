/// *Use up*: what last week left, offered first in the planning picker (plan
/// 0059). Cooked leftovers still good for the day, each with its portions and
/// its use-by — a tap plans a meal from it, not cooked again and not bought —
/// then the recipes that would use the most of last week's spare fresh food.
library;

import 'package:flutter/widgets.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

import '../../../core/theme/ansi_theme.dart';
import '../../../core/theme/ansi_tokens.dart';
import '../../../core/units/number_format.dart';
import '../../../core/units/portions.dart';
import '../../../core/units/units.dart';
import '../../../core/week_shape.dart';
import '../../../shared/ansi_tap.dart';
import '../../account/data/household_providers.dart';
import '../../cook_plan/domain/leftovers.dart';
import '../domain/use_up.dart';

/// `1¾ portions · good until Mon`: what is left of a batch and the last day it
/// is good, by the household's own day names.
String leftoverRowLine(BatchLeftover left, WeekShape shape) =>
    '${formatPortions(left.portions)} · ${goodUntil(left, shape)}';

/// `good until Mon`: a leftover's use-by by the household's own day names.
String goodUntil(BatchLeftover left, WeekShape shape) =>
    'good until ${shape.labelShort(shape.offsetOf(left.useBy))}';

/// `300 g spinach`, `½ onion`: one spare ingredient a suggestion uses.
String spareUseLabel(SpareUse use) =>
    '${spareAmount(use.amount, use.unit, use.pieceBasisAmount)} '
    '${use.name.toLowerCase()}';

/// An amount of spare food as a kitchen says it: a count when the row states
/// a piece weight (`½`, to the nearest quarter), else its weight or volume
/// (`300 g`). A count too small to say a quarter of falls back to the weight.
String spareAmount(double amount, Unit unit, double? pieceBasisAmount) {
  final piece = pieceBasisAmount;
  if (piece != null && piece > 0) {
    final count = (amount / piece * 4).round() / 4;
    if (count > 0) return formatFraction(count);
  }
  return '${formatAmountIn(amount, unit)} ${unit.label}';
}

/// The *Use up* block at the head of the planning picker: cooked leftovers
/// good for the day, then the recipes that would use the most of last week's
/// spare food, with *what's left ›* opening the reasoning.
class UseUpBlock extends ConsumerWidget {
  const UseUpBlock({
    required this.leftovers,
    required this.onPick,
    this.suggestions = const [],
    this.onPickRecipe,
    this.onWhatsLeft,
    super.key,
  });

  /// Leftovers good for the day, soonest use-by first.
  final List<BatchLeftover> leftovers;

  final ValueChanged<BatchLeftover> onPick;

  /// The recipes offered to use up last week's spare food, best first.
  final List<UseUpSuggestion> suggestions;

  final ValueChanged<UseUpSuggestion>? onPickRecipe;

  /// Opens the *what's left* pane; null draws no link.
  final VoidCallback? onWhatsLeft;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final shape = ref.watch(weekShapeProvider);
    final label = ansiMono(
      size: 9.5,
      color: AnsiColors.muted,
      letterSpacing: 1,
    );
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 6),
      decoration: BoxDecoration(
        color: AnsiColors.herbSoft,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'Use up',
            style: ansiMono(
              size: 10,
              color: AnsiColors.herbDeep,
              letterSpacing: 1,
            ),
          ),
          const SizedBox(height: 8),
          if (leftovers.isNotEmpty && suggestions.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Text('LEFTOVERS', style: label),
            ),
          for (final left in leftovers)
            Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: _LeftoverRow(
                left: left,
                line: leftoverRowLine(left, shape),
                onTap: () => onPick(left),
              ),
            ),
          if (suggestions.isNotEmpty) ...[
            Padding(
              padding: EdgeInsets.only(
                top: leftovers.isEmpty ? 0 : 6,
                bottom: 6,
              ),
              child: Row(
                children: [
                  Expanded(child: Text("USES LAST WEEK'S SHOP", style: label)),
                  if (onWhatsLeft case final open?)
                    AnsiTap(
                      onTap: open,
                      semanticsLabel: "What's left from last week's shop",
                      child: Padding(
                        padding: const EdgeInsets.symmetric(vertical: 6),
                        child: Text(
                          "what's left ›",
                          style: ansiSans(
                            size: 12,
                            color: AnsiColors.herbDeep,
                            weight: FontWeight.w500,
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
            for (final s in suggestions)
              Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: _SuggestionRow(
                  suggestion: s,
                  onTap: () => onPickRecipe?.call(s),
                ),
              ),
          ],
        ],
      ),
    );
  }
}

class _SuggestionRow extends StatelessWidget {
  const _SuggestionRow({required this.suggestion, required this.onTap});

  final UseUpSuggestion suggestion;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final uses = [for (final u in suggestion.uses) spareUseLabel(u)];
    return Semantics(
      button: true,
      label: '${suggestion.title}, uses ${uses.join(', ')}',
      child: ExcludeSemantics(
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: onTap,
          child: Container(
            constraints: const BoxConstraints(minHeight: 48),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
            decoration: BoxDecoration(
              color: AnsiColors.surface,
              border: Border.all(color: AnsiColors.line),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(suggestion.title, style: ansiSerif(size: AnsiType.row)),
                const SizedBox(height: 5),
                Wrap(
                  spacing: 5,
                  runSpacing: 4,
                  children: [
                    for (final u in uses)
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 3,
                        ),
                        decoration: BoxDecoration(
                          border: Border.all(color: AnsiColors.line),
                          borderRadius: BorderRadius.circular(999),
                        ),
                        child: Text(
                          u,
                          style: ansiMono(size: 10, color: AnsiColors.herbDeep),
                        ),
                      ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _LeftoverRow extends StatelessWidget {
  const _LeftoverRow({
    required this.left,
    required this.line,
    required this.onTap,
  });

  final BatchLeftover left;
  final String line;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Semantics(
    button: true,
    label: '${left.title}, leftover, $line',
    child: ExcludeSemantics(
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: Container(
          constraints: const BoxConstraints(minHeight: 48),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
          decoration: BoxDecoration(
            color: AnsiColors.surface,
            border: Border.all(color: AnsiColors.line),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(left.title, style: ansiSerif(size: AnsiType.row)),
                    const SizedBox(height: 3),
                    Row(
                      children: [
                        const LeftoverPill(),
                        const SizedBox(width: 6),
                        Flexible(
                          child: Text(
                            line,
                            overflow: TextOverflow.ellipsis,
                            style: ansiMono(
                              size: 10,
                              color: AnsiColors.herbDeep,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    ),
  );
}

/// What the confirm sheet says under a leftover's portions: what this meal
/// leaves of the batch, given the meal's [demand] in portions. Null while the
/// demand is unknown (no eaters yet).
({String text, bool tooMuch})? leftoverAfterLine({
  required double left,
  required double demand,
}) {
  if (demand <= 0) return null;
  final after = left - demand;
  if (after < -1e-9) {
    return (text: 'only ${formatPortions(left)} left', tooMuch: true);
  }
  if (after < 1e-9) return (text: 'uses all of it', tooMuch: false);
  return (
    text: '${formatFraction(after)} still left after this',
    tooMuch: false,
  );
}

/// The confirm sheet's card for a meal from a leftover: the dish, its tag and
/// what is left, and the promise that nothing is cooked or bought for it.
class LeftoverMealCard extends ConsumerWidget {
  const LeftoverMealCard({required this.leftover, super.key});

  final BatchLeftover leftover;

  @override
  Widget build(BuildContext context, WidgetRef ref) => Container(
    padding: const EdgeInsets.all(12),
    decoration: BoxDecoration(
      color: AnsiColors.surface,
      border: Border.all(color: AnsiColors.line),
      borderRadius: BorderRadius.circular(14),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(leftover.title, style: ansiSerif(size: AnsiType.row)),
        const SizedBox(height: 4),
        Row(
          children: [
            const LeftoverPill(),
            const SizedBox(width: 6),
            Flexible(
              child: Text(
                leftoverRowLine(leftover, ref.watch(weekShapeProvider)),
                overflow: TextOverflow.ellipsis,
                style: ansiMono(size: 10, color: AnsiColors.muted),
              ),
            ),
          ],
        ),
        const SizedBox(height: 6),
        Text(
          'Not cooked again, not bought',
          style: ansiSans(
            size: 12.5,
            color: AnsiColors.herbDeep,
            weight: FontWeight.w500,
          ),
        ),
      ],
    ),
  );
}

/// The `leftover` tag a meal from a batch wears in the picker and on the
/// confirm sheet.
class LeftoverPill extends StatelessWidget {
  const LeftoverPill({super.key});

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
    decoration: BoxDecoration(
      color: AnsiColors.herbSoft,
      borderRadius: BorderRadius.circular(6),
    ),
    child: Text(
      'leftover',
      style: ansiMono(size: 9.5, color: AnsiColors.herbDeep),
    ),
  );
}
