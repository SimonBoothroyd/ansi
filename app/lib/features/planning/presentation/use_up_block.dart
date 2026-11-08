/// *Leftovers*: what is already cooked or bought, offered first in the
/// planning picker. The fridge rows still good for the day, then the freezer
/// rows, each soonest to go off first with what is left and its date (a tap
/// plans a meal from it, not cooked again and not bought), then the recipes
/// that would use the most of last week's spare fresh food.
library;

import 'package:flutter/widgets.dart';
import 'package:forui/forui.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

import '../../../core/theme/ansi_theme.dart';
import '../../../core/theme/ansi_tokens.dart';
import '../../../core/units/number_format.dart';
import '../../../core/units/portions.dart';
import '../../../core/units/units.dart';
import '../../../shared/ansi_tap.dart';
import '../../account/data/household_providers.dart';
import '../../cook_plan/domain/leftovers.dart';
import '../../cook_plan/presentation/leftover_format.dart';
import '../domain/use_up.dart';
import 'week_view_models.dart';

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

/// The *Leftovers* block at the head of the planning picker: the fridge rows
/// good for the day, the freezer rows, then the recipes that would use the
/// most of last week's spare food, with *what's left ›* opening the
/// reasoning. An empty shelf draws no subhead.
class UseUpBlock extends ConsumerWidget {
  const UseUpBlock({
    required this.leftovers,
    required this.onPick,
    this.suggestions = const [],
    this.onPickRecipe,
    this.onWhatsLeft,
    super.key,
  });

  /// The rows good for the day, fridge first, soonest to go off first.
  final List<Leftover> leftovers;

  final ValueChanged<Leftover> onPick;

  /// The recipes offered to use up last week's spare food, best first.
  final List<UseUpSuggestion> suggestions;

  final ValueChanged<UseUpSuggestion>? onPickRecipe;

  /// Opens the *what's left* pane; null draws no link.
  final VoidCallback? onWhatsLeft;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final today = ref.watch(todayProvider);
    final label = ansiMono(
      size: 9.5,
      color: AnsiColors.muted,
      letterSpacing: 1,
    );
    final fridge = [
      for (final l in leftovers)
        if (l.place == LeftoverPlace.fridge) l,
    ];
    final freezer = [
      for (final l in leftovers)
        if (l.place == LeftoverPlace.freezer) l,
    ];
    List<Widget> shelf(
      String name,
      Color ink,
      List<Leftover> rows, {
      bool chill = false,
    }) => [
      if (rows.isNotEmpty)
        Padding(
          padding: const EdgeInsets.only(bottom: 6),
          child: Row(
            children: [
              if (chill) ...[
                Icon(FLucideIcons.snowflake, size: 9, color: ink),
                const SizedBox(width: 4),
              ],
              Text(name, style: label.copyWith(color: ink)),
            ],
          ),
        ),
      for (final left in rows)
        Padding(
          padding: const EdgeInsets.only(bottom: 6),
          child: _LeftoverRow(
            left: left,
            today: today,
            onTap: () => onPick(left),
          ),
        ),
    ];
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
            'Leftovers',
            style: ansiMono(
              size: 10,
              color: AnsiColors.herbDeep,
              letterSpacing: 1,
            ),
          ),
          const SizedBox(height: 8),
          ...shelf('FRIDGE', AnsiColors.muted, fridge),
          if (fridge.isNotEmpty && freezer.isNotEmpty)
            const SizedBox(height: 4),
          ...shelf('FREEZER', AnsiColors.chillInk, freezer, chill: true),
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

/// One row offered: the dish, then `1 left · till Mon` (with the fridge's
/// `leftover` tag), `2 left · till Jan` from the freezer, or `2 left` and a
/// `freeze by Mon` tag for a fridge row that has to go in by then.
class _LeftoverRow extends ConsumerWidget {
  const _LeftoverRow({
    required this.left,
    required this.today,
    required this.onTap,
  });

  final Leftover left;
  final DateTime today;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final shape = ref.watch(weekShapeProvider);
    final frozen = left.place == LeftoverPlace.freezer;
    final freezeBy = frozen && left.freezeBy != null;
    final when = leftoverWhen(left, today, shape);
    final ink = frozen ? AnsiColors.chillInk : AnsiColors.herbDeep;
    return Semantics(
      button: true,
      label: '${left.title}, ${leftCount(left.portions)}, $when',
      child: ExcludeSemantics(
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: onTap,
          child: Container(
            constraints: const BoxConstraints(minHeight: 48),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
            decoration: BoxDecoration(
              color: AnsiColors.surface,
              border: Border.all(
                color: frozen ? AnsiColors.chillLine : AnsiColors.line,
              ),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(left.title, style: ansiSerif(size: AnsiType.row)),
                const SizedBox(height: 3),
                Row(
                  children: [
                    if (!frozen) ...[
                      const LeftoverTag(place: LeftoverPlace.fridge),
                      const SizedBox(width: 6),
                    ],
                    Flexible(
                      child: Text(
                        freezeBy
                            ? '${leftCount(left.portions)} ·'
                            : '${leftCount(left.portions)} · $when',
                        overflow: TextOverflow.ellipsis,
                        style: ansiMono(size: 10, color: ink),
                      ),
                    ),
                    if (freezeBy) ...[
                      const SizedBox(width: 6),
                      LeftoverTag(place: LeftoverPlace.freezer, label: when),
                    ],
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

  final Leftover leftover;

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
            LeftoverTag(place: leftover.place),
            const SizedBox(width: 6),
            Flexible(
              child: Text(
                leftoverLine(
                  leftover,
                  ref.watch(todayProvider),
                  ref.watch(weekShapeProvider),
                ),
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

/// The tag a meal from a leftover wears in the picker, on the confirm sheet
/// and on its Week row: the fridge's green, or the freezer's blue with a
/// snowflake. A meal that no longer adds up keeps its colour and adds its
/// [warning] in amber.
class LeftoverTag extends StatelessWidget {
  const LeftoverTag({
    required this.place,
    this.label = 'leftover',
    this.warning,
    this.size = 9.5,
    super.key,
  });

  final LeftoverPlace place;

  /// `leftover`, or `freeze by Mon` where the picker offers a fridge row
  /// that has to go in by then.
  final String label;

  /// What is wrong with the meal on its day, if anything.
  final LeftoverWarning? warning;

  final double size;

  @override
  Widget build(BuildContext context) {
    final frozen = place == LeftoverPlace.freezer;
    final ink = frozen ? AnsiColors.chillInk : AnsiColors.herbDeep;
    final warned = warning;
    final words = warned == null
        ? Text(
            label,
            style: ansiMono(size: size, color: ink),
          )
        : Text.rich(
            TextSpan(
              text: label,
              children: [
                TextSpan(
                  text: ' · ${leftoverWarningWords(warned)}',
                  style: ansiMono(size: size, color: AnsiColors.cautionInk),
                ),
              ],
            ),
            style: ansiMono(size: size, color: ink),
          );
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
      decoration: BoxDecoration(
        color: frozen ? AnsiColors.chill : AnsiColors.herbSoft,
        borderRadius: BorderRadius.circular(6),
      ),
      child: frozen
          ? Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(FLucideIcons.snowflake, size: size, color: ink),
                const SizedBox(width: 3),
                words,
              ],
            )
          : words,
    );
  }
}
