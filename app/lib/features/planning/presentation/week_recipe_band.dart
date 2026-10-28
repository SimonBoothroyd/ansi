/// The band a recipe page prints when opened from a week that plans the recipe:
/// the line-size week strip (the cook days underlined, a dot on a day a meal
/// eats from an earlier cook), plus "edited for this week" when the week varies
/// it. It gives the page's "Edit for this week" menu item its context. No
/// fills: the hero keeps those for its chips.
library;

import 'package:flutter/widgets.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

import '../../../core/theme/ansi_theme.dart';
import '../../../core/theme/ansi_tokens.dart';
import '../../../shared/week_strip.dart';
import '../../account/data/household_providers.dart';
import '../../cook_plan/presentation/cook_format.dart' show stripDaysOfAll;
import '../../recipes/presentation/recipe_view_models.dart';
import 'week_format.dart';
import 'week_variant_format.dart';

class PlannedThisWeekBand extends ConsumerWidget {
  const PlannedThisWeekBand({
    required this.days,
    required this.edited,
    this.recipeId,
    super.key,
  });

  /// The days of that week which plan this recipe, ascending. Never empty: the
  /// page draws no band without a placement (see `weekRecipePlacement`).
  final List<int> days;

  /// Whether the week varies the recipe.
  final bool edited;

  /// The recipe, whose shelf life tells a cook day from a day eaten out of the
  /// fridge. Without it every planned day is drawn as a cook day.
  final String? recipeId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final id = recipeId;
    final recipe = id == null
        ? null
        : ref
              .watch(recipeListProvider)
              .asData
              ?.value
              .where((r) => r.id == id)
              .firstOrNull;
    final strip = recipe == null
        ? [
            for (var day = 0; day < 7; day++)
              WeekStripDay(
                fill: days.contains(day)
                    ? WeekStripFill.cooked
                    : WeekStripFill.none,
                eats: days.contains(day),
              ),
          ]
        : stripDaysOfAll(
            weekBatchesOf(
              days,
              keepsForDays: recipe.keepsForDays,
              freezable: recipe.freezable,
              freezerDays: recipe.freezerDays,
            ),
          );
    return Row(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        WeekStrip(
          days: strip,
          shape: ref.watch(weekShapeProvider),
          size: WeekStripSize.line,
        ),
        if (edited) ...[
          const SizedBox(width: 10),
          Flexible(
            child: Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: Text(
                kEditedForThisWeek,
                style: ansiMono(size: 11, color: AnsiColors.herbDeep),
              ),
            ),
          ),
        ],
      ],
    );
  }
}
