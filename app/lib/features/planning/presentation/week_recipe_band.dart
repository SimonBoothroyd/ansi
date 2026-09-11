/// The one band a recipe page prints when it was opened FROM a week that plans
/// the recipe — "Planned Tue · Sat this week", and "edited for this week" when
/// the week varies it.
///
/// It exists because the variant door shipped in one place only, at the foot of
/// the meal editor sheet, and the two surfaces that actually hold a week — the
/// Week's dish row and the Cook card — both dropped it on the way to the recipe
/// page. The band is what makes the page's second ⋯ item legible before it is
/// tapped: without it, "Edit for this week" on a page reached from the Library
/// would be a menu item about a week nobody is looking at.
///
/// It draws nothing but the fact. The door is the menu item beside it, because
/// a band that is also a button competes with the page's own title.
library;

import 'package:flutter/widgets.dart';

import '../../../core/theme/ansi_theme.dart';
import '../../../core/theme/ansi_tokens.dart';
import '../../../core/words.dart';
import 'week_variant_format.dart';

class PlannedThisWeekBand extends StatelessWidget {
  const PlannedThisWeekBand({
    required this.days,
    required this.edited,
    super.key,
  });

  /// The days of that week which plan this recipe, ascending. Never empty —
  /// the page decides whether there is a band to draw, so an empty list means
  /// no arrival and no band at all (see `weekRecipePlacement`).
  final List<int> days;

  /// Whether the week varies the recipe, in the words every surface with a
  /// week uses for it.
  final bool edited;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
      decoration: BoxDecoration(
        color: AnsiColors.herbSoft,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Text(
        plannedThisWeekLine(days, kWeekdayShort, edited: edited),
        style: ansiMono(size: 10.5, color: AnsiColors.herbDeep),
      ),
    );
  }
}
