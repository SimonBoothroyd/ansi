/// The one line under the picked recipe on *Add to plan* that takes the
/// choice of optional ingredients to the recipe, where each can be read in the
/// step that uses it.
library;

import 'package:flutter/widgets.dart';
import 'package:forui/forui.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

import '../../../core/theme/ansi_theme.dart';
import '../../../core/theme/ansi_tokens.dart';
import '../../../core/words.dart';
import '../../../shared/ansi_tap.dart';
import '../../../shared/guarded_navigation.dart';
import '../../recipes/domain/optional_choices.dart';
import '../../recipes/presentation/recipe_view_models.dart';
import 'week_view_models.dart';

/// `2 optional ingredients · Choose in recipe ›`, and once some are picked
/// `With Coriander · Change ›`. Nothing for a dish with none.
///
/// It reads the sheet's unwritten picks ([OptionalPicks]), made on that
/// page.
class OptionalInRecipeDoor extends ConsumerWidget {
  const OptionalInRecipeDoor({
    required this.recipeId,
    required this.weekKey,
    required this.day,
    super.key,
  });

  final String recipeId;
  final String weekKey;

  /// The day being added, which the recipe page names.
  final int day;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final picks = ref.watch(optionalPicksProvider(weekKey, recipeId));
    final recipe = ref.watch(recipeByIdProvider(recipeId)).asData?.value;
    final week = ref.watch(weekOverridesForProvider(weekKey)).asData?.value;
    if (recipe == null || week == null) return const SizedBox.shrink();
    final choices = optionalChoices([
      for (final group in recipe.groups) ...group.items,
    ], week[recipeId] ?? const []);
    if (choices.isEmpty) return const SizedBox.shrink();

    final picked = [
      for (final c in choices)
        if (c.includedWith(picks)) c.name,
    ];
    final count = choices.length;
    return Container(
      margin: const EdgeInsets.only(top: 12),
      decoration: const BoxDecoration(
        border: Border(top: BorderSide(color: AnsiColors.line)),
      ),
      child: AnsiTap(
        onTap: () => context.pushOnce(
          recipePageRoute(recipeId, weekKey: weekKey, choosingDay: day),
        ),
        semanticsLabel: 'Choose optional ingredients in the recipe',
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: kAnsiTouchTarget),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  picked.isEmpty
                      ? '$count optional ${plural(count, 'ingredient')}'
                      : 'With ${picked.join(', ')}',
                  style: ansiSans(size: 13),
                ),
              ),
              const SizedBox(width: 8),
              Text(
                picked.isEmpty ? 'Choose in recipe' : 'Change',
                style: ansiSans(
                  size: 13,
                  color: AnsiColors.herbDeep,
                  weight: FontWeight.w500,
                ),
              ),
              const Icon(
                FLucideIcons.chevronRight,
                size: 14,
                color: AnsiColors.herbDeep,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
