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
///
/// **One line, no fill.** It sits between the title and the chip row, and a
/// filled band there made three stacked shapes before the recipe started. A
/// calendar glyph and a mono line carry the same fact at a fraction of the
/// weight, leaving the chips as the only filled thing above the tabs.
library;

import 'package:flutter/widgets.dart';
import 'package:forui/forui.dart';

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
            plannedThisWeekLine(days, kWeekdayShort, edited: edited),
            style: ansiMono(size: 11, color: AnsiColors.herbDeep),
          ),
        ),
      ],
    );
  }
}
