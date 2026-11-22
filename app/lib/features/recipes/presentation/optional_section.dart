/// OPTIONAL on a recipe page a week owns: each optional ingredient with the
/// recipe's own words for how it is used, and the tick that answers for it.
library;

import 'package:flutter/widgets.dart';
import 'package:forui/forui.dart';

import '../../../core/theme/ansi_theme.dart';
import '../../../core/theme/ansi_tokens.dart';
import '../../../core/units/macros.dart';
import '../../../shared/ansi_micro_label.dart';
import '../../ingredients/presentation/macro_line_text.dart';
import '../domain/line_display.dart';
import '../domain/method_uses.dart';
import 'ingredient_line.dart';
import 'recipe_chip.dart';

/// The key of one optional ingredient's card: its first line's id.
ValueKey<String> optionalCardKey(String lineId) =>
    ValueKey('optional-card-$lineId');

/// The section, under the recipe's other ingredients. With [reveal] it brings
/// itself on screen: the page was opened to answer it.
class OptionalSection extends StatefulWidget {
  const OptionalSection({required this.cards, this.reveal = false, super.key});

  final List<OptionalCard> cards;
  final bool reveal;

  @override
  State<OptionalSection> createState() => _OptionalSectionState();
}

class _OptionalSectionState extends State<OptionalSection> {
  @override
  void initState() {
    super.initState();
    if (!widget.reveal) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      // To its end where it fits, then never past its start: the first
      // ingredient is always on screen.
      Scrollable.ensureVisible(
        context,
        alignmentPolicy: ScrollPositionAlignmentPolicy.keepVisibleAtEnd,
      ).ignore();
      Scrollable.ensureVisible(
        context,
        alignmentPolicy: ScrollPositionAlignmentPolicy.keepVisibleAtStart,
      ).ignore();
    });
  }

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(top: 18),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const AnsiMicroLabel('Optional'),
        for (final card in widget.cards)
          Padding(padding: const EdgeInsets.only(top: 8), child: card),
      ],
    ),
  );
}

/// One optional ingredient: its box, name and amount, and under them every
/// step that uses it, quoted. Where the method links none, its note is all
/// there is to say. The whole card is the target.
class OptionalCard extends StatelessWidget {
  const OptionalCard({
    required this.uses,
    required this.steps,
    required this.included,
    this.onToggle,
    this.onOpenSubRecipe,
    this.macroLine,
    this.detail,
    this.onFix,
    super.key,
  });

  /// At the amounts shown.
  final LineUses uses;
  final List<StepUse> steps;
  final bool included;

  /// Null where the week states an amount for it: that is changed in the
  /// week's editor.
  final VoidCallback? onToggle;
  final ValueChanged<String>? onOpenSubRecipe;

  /// Its figures while included, where the page prints line figures.
  final Macros? macroLine;

  /// Why it has none, or what it costs.
  final String? detail;

  /// The fix [detail] implies.
  final VoidCallback? onFix;

  @override
  Widget build(BuildContext context) {
    final first = uses.uses.first;
    final target = first.subRecipe;
    final open = onOpenSubRecipe;
    final notes = uses.notes.join(' + ');
    final amount = [
      for (final use in uses.uses)
        if (amountOfLineItem(use) case final a when a.isNotEmpty) a,
    ].join(' + ');
    final small = ansiMono(size: 10.5, color: AnsiColors.muted);

    final card = Container(
      constraints: const BoxConstraints(minHeight: 48),
      padding: const EdgeInsets.all(11),
      decoration: BoxDecoration(
        color: included ? AnsiColors.herbSoft : AnsiColors.surface,
        border: Border.all(color: included ? AnsiColors.herb : AnsiColors.line),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 20,
            height: 20,
            decoration: BoxDecoration(
              color: included ? AnsiColors.herb : AnsiColors.surface,
              border: Border.all(
                color: included ? AnsiColors.herb : AnsiColors.line,
                width: 1.6,
              ),
              borderRadius: BorderRadius.circular(6),
            ),
            child: included
                ? const Icon(
                    FLucideIcons.check,
                    size: 13,
                    color: AnsiColors.surface,
                  )
                : null,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: target != null
                          ? Align(
                              alignment: Alignment.centerLeft,
                              // A door of its own: the sub-recipe may have
                              // optional ingredients too.
                              child: RecipeChip(
                                title: target.title,
                                onTap: open == null
                                    ? null
                                    : () => open(target.id),
                              ),
                            )
                          : Text.rich(
                              TextSpan(
                                children: [
                                  TextSpan(
                                    text: uses.ingredientName,
                                    style: ansiSans(
                                      size: 16,
                                      weight: FontWeight.w500,
                                    ),
                                  ),
                                  ...noteSpans(notes, size: 16),
                                  ...removedIngredientSpans(
                                    removed: uses.uses.any(
                                      (u) => u.ingredientDeleted,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                    ),
                    if (amount.isNotEmpty) ...[
                      const SizedBox(width: 10),
                      ConstrainedBox(
                        constraints: const BoxConstraints(
                          maxWidth: kLineAmountWidth,
                        ),
                        child: Text(
                          amount,
                          textAlign: TextAlign.right,
                          style: ansiMono(size: 13, color: AnsiColors.muted),
                        ),
                      ),
                    ],
                  ],
                ),
                if (target != null && notes.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Text(notes, style: small),
                  ),
                for (final step in steps)
                  Padding(
                    padding: const EdgeInsets.only(top: 5),
                    child: _Quote(step),
                  ),
                if (macroLine case final macros?)
                  Padding(
                    padding: const EdgeInsets.only(top: 5),
                    child: MacroLineText(macros, style: small),
                  )
                else if (detail case final words?)
                  Padding(
                    padding: const EdgeInsets.only(top: 5),
                    child: GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onTap: onFix,
                      child: Text(words, style: small),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );

    return Semantics(
      checked: included,
      child: FTappable(
        onPress: onToggle,
        behavior: HitTestBehavior.opaque,
        semanticsLabel: first.subRecipe?.title ?? uses.ingredientName,
        child: card,
      ),
    );
  }
}

/// `Step 2  “…and scatter with coriander.”`, the ingredient in ink.
class _Quote extends StatelessWidget {
  const _Quote(this.use);

  final StepUse use;

  @override
  Widget build(BuildContext context) {
    final words = ansiSans(size: 13, color: AnsiColors.muted);
    return Text.rich(
      TextSpan(
        style: words,
        children: [
          TextSpan(
            text: 'Step ${use.step}  ',
            style: ansiMono(size: 11, color: AnsiColors.herbDeep),
          ),
          TextSpan(text: '“${use.before}'),
          TextSpan(
            text: use.word,
            style: ansiSans(size: 13, weight: FontWeight.w600),
          ),
          TextSpan(text: '${use.after}”'),
        ],
      ),
    );
  }
}
