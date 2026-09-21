/// The band a recipe page prints when opened from a week that plans the recipe:
/// "Planned Tue · Sat this week", plus "edited for this week" when the week
/// varies it. It gives the page's "Edit for this week" menu item its context.
/// One unfilled line, not a button.
library;

import 'package:flutter/widgets.dart';
import 'package:forui/forui.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

import '../../../core/theme/ansi_theme.dart';
import '../../../core/theme/ansi_tokens.dart';
import '../../account/data/household_providers.dart';
import 'week_variant_format.dart';

class PlannedThisWeekBand extends ConsumerWidget {
  const PlannedThisWeekBand({
    required this.days,
    required this.edited,
    super.key,
  });

  /// The days of that week which plan this recipe, ascending. Never empty: the
  /// page draws no band without a placement (see `weekRecipePlacement`).
  final List<int> days;

  /// Whether the week varies the recipe.
  final bool edited;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Padding(
          padding: EdgeInsets.only(top: 1),
          child: Icon(
            FLucideIcons.calendarDays,
            size: 12,
            color: AnsiColors.herbDeep,
          ),
        ),
        const SizedBox(width: 6),
        Expanded(
          child: Text(
            plannedThisWeekLine(
              days,
              ref.watch(weekShapeProvider).shortLabels,
              edited: edited,
            ),
            style: ansiMono(size: 11, color: AnsiColors.herbDeep),
          ),
        ),
      ],
    );
  }
}
