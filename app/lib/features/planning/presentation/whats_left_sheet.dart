/// *What's left*: the one place *Use up*'s reasoning is visible.
/// Last week's spare fresh food, each with how it was worked out, then the
/// recipes that would use it, scored, with the line under which nothing is
/// offered. Opened from the picker's *what's left ›* and nowhere else.
library;

import 'package:flutter/widgets.dart';

import '../../../core/theme/ansi_theme.dart';
import '../../../core/theme/ansi_tokens.dart';
import '../../../shared/ansi_modals.dart';
import '../../../shared/ansi_sheet_shell.dart';
import '../domain/use_up.dart';
import 'use_up_block.dart' show spareAmount, spareUseLabel;
import 'use_up_view_models.dart';

/// `500 g in · 200 g used`: how a spare amount was worked out.
String spareHowLine(SpareFood s) =>
    '${spareAmount(s.bought, s.unit, s.pieceBasisAmount)} in · '
    '${spareAmount(s.used, s.unit, s.pieceBasisAmount)} used';

/// Opens *what's left* over [view].
Future<void> showWhatsLeftSheet(BuildContext context, UseUpView view) =>
    showAnsiSheet<void>(
      context: context,
      builder: (_) => _WhatsLeftSheet(view: view),
    );

class _WhatsLeftSheet extends StatelessWidget {
  const _WhatsLeftSheet({required this.view});

  final UseUpView view;

  @override
  Widget build(BuildContext context) {
    final offered = {for (final s in view.offered) s.recipeId};
    final notOffered = [
      for (final s in view.scored.take(5))
        if (!offered.contains(s.recipeId)) s,
    ];
    final best = view.scored.isEmpty ? 0.0 : view.scored.first.score;
    final label = ansiMono(
      size: 9.5,
      color: AnsiColors.muted,
      letterSpacing: 1,
    );
    return AnsiSheetShell(
      title: "What's left",
      subtitle: "from last week's shop",
      centerTitle: false,
      scrollable: true,
      children: [
        const SizedBox(height: 14),
        Text('FRESH, NOT USED', style: label),
        const SizedBox(height: 4),
        for (final s in view.spare)
          _Line(
            name: s.name,
            how: spareHowLine(s),
            amount: spareAmount(s.amount, s.unit, s.pieceBasisAmount),
          ),
        if (view.scored.isNotEmpty) ...[
          const SizedBox(height: 18),
          Text('RECIPES THAT USE MOST OF IT', style: label),
          const SizedBox(height: 2),
          Text(
            'by what the amounts they use cost',
            style: ansiSans(size: 12, color: AnsiColors.muted),
          ),
          const SizedBox(height: 6),
          for (final s in view.offered)
            _Scored(suggestion: s, best: best, offered: true),
          if (notOffered.isNotEmpty) ...[
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 10),
              child: Row(
                children: [
                  Expanded(child: Container(height: 1, color: AnsiColors.line)),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    child: Text('NOT SUGGESTED', style: label),
                  ),
                  Expanded(child: Container(height: 1, color: AnsiColors.line)),
                ],
              ),
            ),
            for (final s in notOffered)
              _Scored(suggestion: s, best: best, offered: false),
          ],
        ],
        const SizedBox(height: 12),
      ],
    );
  }
}

class _Line extends StatelessWidget {
  const _Line({required this.name, required this.how, required this.amount});

  final String name;
  final String how;
  final String amount;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(vertical: 10),
    decoration: const BoxDecoration(
      border: Border(top: BorderSide(color: AnsiColors.line)),
    ),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.baseline,
      textBaseline: TextBaseline.alphabetic,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(name, style: ansiSans(size: 14, weight: FontWeight.w500)),
              Text(how, style: ansiSans(size: 12, color: AnsiColors.muted)),
            ],
          ),
        ),
        Text(amount, style: ansiMono(size: 13, color: AnsiColors.herbDeep)),
      ],
    ),
  );
}

/// One scored recipe: its name, the spare food it uses, and a bar of its score
/// against the best.
class _Scored extends StatelessWidget {
  const _Scored({
    required this.suggestion,
    required this.best,
    required this.offered,
  });

  final UseUpSuggestion suggestion;
  final double best;
  final bool offered;

  @override
  Widget build(BuildContext context) {
    final share = best <= 0 ? 0.0 : (suggestion.score / best).clamp(0.0, 1.0);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            suggestion.title,
            style: ansiSans(
              size: 14,
              weight: offered ? FontWeight.w600 : FontWeight.w400,
              color: offered ? AnsiColors.ink : AnsiColors.muted,
            ),
          ),
          Text(
            [for (final u in suggestion.uses) spareUseLabel(u)].join(' · '),
            style: ansiSans(size: 12, color: AnsiColors.muted),
          ),
          const SizedBox(height: 6),
          ClipRRect(
            borderRadius: BorderRadius.circular(3),
            child: SizedBox(
              height: 6,
              child: Stack(
                children: [
                  const Positioned.fill(
                    child: ColoredBox(color: AnsiColors.line),
                  ),
                  FractionallySizedBox(
                    widthFactor: share,
                    child: ColoredBox(
                      color: offered ? AnsiColors.herb : AnsiColors.muted,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
