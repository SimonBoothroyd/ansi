/// The Week at [AnsiLayout.expanded] — the same week, drawn as a matrix.
///
/// Seven day columns across, and down the side the slots the week **actually
/// has**: `meal_slot` is free text, so a fixed four-row grid would draw rows
/// nobody planned and refuse the one somebody typed. The rows are the union of
/// the slots present in the week on screen, in the app's own slot order
/// ([mealSlotRank]), and a week with nothing in it has none — seven day heads,
/// the copy chip and the add doors, and quiet paper between them.
///
/// **It is the phone's week, not a second one.** One view model
/// (`week_view_models.dart`), one set of words (`week_macro_widgets.dart`,
/// `week_format.dart`) and one set of doors: a card's eaters open the same meal
/// editor, its `−` runs the same undo, its title opens the same recipe page,
/// and a column's `＋ add a meal` is the day card's own door with its own day.
/// What changes is the shape.
///
/// **What is pinned, and what scrolls.** The head row and the column feet stay
/// put while the rows between them scroll, because a day with five meals must
/// not push another day's add door or its total off screen. The whole matrix
/// shares ONE vertical scroll — seven independent scroll views would let the
/// rows fall out of line with each other and with the gutter that names them.
///
/// **Nothing here is dragged.** The week has no `move` operation, so a card
/// must not look like a tile that could be dragged into one: it is worked
/// exactly as the phone row is — a meal changes day by being removed and added
/// again — and every target is drawn, with no hover-only controls anywhere.
library;

import 'package:flutter/widgets.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

import '../../../core/theme/ansi_theme.dart';
import '../../../core/theme/ansi_tokens.dart';
import '../../../core/week_shape.dart';
import '../../../shared/ansi_layout.dart';
import '../../../shared/guarded_navigation.dart';
import '../../account/data/household_providers.dart';
import '../../cook_plan/domain/cook_plan.dart';
import '../domain/planning.dart';
import 'copy_last_week.dart';
import 'week_format.dart';
import 'week_macro_widgets.dart';
import 'week_view_models.dart';
import 'week_widgets.dart';

/// The gutter that names each slot row. Wide enough for the longest default
/// slot at the label's own size, because a slot is printed in the words the
/// week stores — `BREAKFAST`, never `Bkfst`.
const _gutter = 74.0;

/// The slot rows the week on screen has, in the app's slot order.
///
/// Case-insensitively deduped, keeping the first spelling seen, so a day that
/// typed `dinner` shares Dinner's row rather than opening a second one — the
/// same equivalence [defaultMealSlot] and [mealSlotRank] use. Custom slots sort
/// after the four defaults and, among themselves, by where they first appear.
List<String> slotRowsOf(WeekPlan? plan) {
  final seen = <String, String>{};
  for (final entry in plan?.entries ?? const <PlanEntry>[]) {
    seen.putIfAbsent(entry.mealSlot.trim().toLowerCase(), () => entry.mealSlot);
  }
  final slots = seen.values.toList();
  final indexed = [for (final (i, s) in slots.indexed) (i, s)]
    ..sort((a, b) {
      final ra = mealSlotRank(a.$2);
      final rb = mealSlotRank(b.$2);
      return ra != rb ? ra.compareTo(rb) : a.$1.compareTo(b.$1);
    });
  return [for (final p in indexed) p.$2];
}

class WeekMatrix extends StatelessWidget {
  const WeekMatrix({
    required this.weekStart,
    required this.plan,
    required this.roster,
    required this.lens,
    required this.scope,
    required this.cookPlan,
    required this.todayDayOfWeek,
    required this.onAddMeal,
    required this.onCopyLastWeek,
    super.key,
  });

  final DateTime weekStart;
  final WeekPlan? plan;
  final List<Member> roster;

  /// null = Everyone; a member id = that person's lens (D8: it dims, it does
  /// not remove).
  final ValueNotifier<String?> lens;

  /// Whose numbers these are — `Everyone` or a member's display name.
  final String scope;
  final CookPlan? cookPlan;
  final int? todayDayOfWeek;

  /// Opens the add flow on one day — the day card's own door, carrying its day.
  final void Function(int dayOfWeek) onAddMeal;

  /// Offered only while the week is empty and there is a week behind it.
  final VoidCallback? onCopyLastWeek;

  @override
  Widget build(BuildContext context) {
    final slots = slotRowsOf(plan);
    final copy = onCopyLastWeek;
    // A matrix is a view that USES the width, so it belongs in the full-width
    // pane the tab shell offers a branch root that opts out of the 640 measure.
    // It fills whatever width it is handed and caps nothing itself.
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        WeekLensRow(lens: lens, roster: roster),
        CopyLastWeekNotice(weekStart: weekStart),
        if (copy != null)
          Padding(
            padding: const EdgeInsets.only(top: 10),
            child: Align(child: CopyLastWeekChip(onTap: copy)),
          ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
          child: _HeadRow(weekStart: weekStart, todayDayOfWeek: todayDayOfWeek),
        ),
        // Flexible, not Expanded: a week of three slot rows draws its feet
        // directly under the last row, the way the grid does, and only a week
        // too tall for the window scrolls under feet parked at the bottom.
        Flexible(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (final slot in slots)
                  _SlotRow(
                    slot: slot,
                    plan: plan,
                    roster: roster,
                    lens: lens.value,
                    cookPlan: cookPlan,
                    todayDayOfWeek: todayDayOfWeek,
                  ),
              ],
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 0),
          child: _FootRow(scope: scope, lens: lens.value, onAddMeal: onAddMeal),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          child: _MacroBand(scope: scope, lens: lens.value),
        ),
      ],
    );
  }
}

/// The seven day names and dates, pinned above the rows. Today reads in herb
/// and carries the phone's own TODAY tag.
class _HeadRow extends ConsumerWidget {
  const _HeadRow({required this.weekStart, required this.todayDayOfWeek});

  final DateTime weekStart;
  final int? todayDayOfWeek;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final shape = ref.watch(weekShapeProvider);
    // IntrinsicHeight, here and on every other row: the seven columns are one
    // grid, so a cell's rule and its paper have to run the height of the row
    // rather than of its own contents — and `stretch` alone cannot, because
    // nothing above these rows bounds their height.
    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const SizedBox(width: _gutter),
          for (var d = 0; d < 7; d++)
            Expanded(
              child: Container(
                padding: const EdgeInsets.fromLTRB(6, 0, 6, 9),
                decoration: BoxDecoration(
                  border: Border(
                    left: d == 0
                        ? BorderSide.none
                        : const BorderSide(color: AnsiColors.line),
                  ),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      shape.labelFull(d),
                      overflow: TextOverflow.ellipsis,
                      style: ansiSerif(
                        size: 14,
                        color: todayDayOfWeek == d
                            ? AnsiColors.herbDeep
                            : AnsiColors.ink,
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.only(top: 2),
                      child: Text(
                        formatDayDate(weekStart, d),
                        style: ansiMono(size: 9.5, color: AnsiColors.muted),
                      ),
                    ),
                    if (todayDayOfWeek == d)
                      Padding(
                        padding: const EdgeInsets.only(top: 4),
                        child: _TodayTag(),
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

class _TodayTag extends StatelessWidget {
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
    decoration: BoxDecoration(
      color: AnsiColors.herbSoft,
      borderRadius: BorderRadius.circular(999),
    ),
    child: Text(
      'TODAY',
      style: ansiMono(size: 9, color: AnsiColors.herbDeep, letterSpacing: 1),
    ),
  );
}

/// One slot row: the gutter naming it, then that slot's cell on each of the
/// seven days. As tall as its own tallest day and no taller.
class _SlotRow extends StatelessWidget {
  const _SlotRow({
    required this.slot,
    required this.plan,
    required this.roster,
    required this.lens,
    required this.cookPlan,
    required this.todayDayOfWeek,
  });

  final String slot;
  final WeekPlan? plan;
  final List<Member> roster;
  final String? lens;
  final CookPlan? cookPlan;
  final int? todayDayOfWeek;

  @override
  Widget build(BuildContext context) {
    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(
            width: _gutter,
            child: Container(
              padding: const EdgeInsets.fromLTRB(0, 11, 8, 0),
              decoration: const BoxDecoration(
                border: Border(top: BorderSide(color: AnsiColors.line)),
              ),
              child: Text(
                slot.toUpperCase(),
                textAlign: TextAlign.right,
                overflow: TextOverflow.ellipsis,
                style: ansiMono(
                  size: 9.5,
                  color: AnsiColors.muted,
                  letterSpacing: 0.8,
                ),
              ),
            ),
          ),
          for (var d = 0; d < 7; d++)
            Expanded(
              child: _Cell(
                entries: [
                  for (final e in plan?.entriesForDay(d) ?? const <PlanEntry>[])
                    if (e.mealSlot.trim().toLowerCase() ==
                        slot.trim().toLowerCase())
                      e,
                ],
                roster: roster,
                lens: lens,
                cookPlan: cookPlan,
                todayDayOfWeek: todayDayOfWeek,
              ),
            ),
        ],
      ),
    );
  }
}

/// One day's cell in one slot row. An EMPTY cell carries no control at all: a
/// box with a `+` in it manufactures emptiness seven times a row, and the day
/// already has its one add door at the foot of its column.
class _Cell extends StatelessWidget {
  const _Cell({
    required this.entries,
    required this.roster,
    required this.lens,
    required this.cookPlan,
    required this.todayDayOfWeek,
  });

  final List<PlanEntry> entries;
  final List<Member> roster;
  final String? lens;
  final CookPlan? cookPlan;
  final int? todayDayOfWeek;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(6),
      decoration: const BoxDecoration(
        color: AnsiColors.paper,
        border: Border(
          top: BorderSide(color: AnsiColors.line),
          left: BorderSide(color: AnsiColors.line),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (final (i, e) in entries.indexed)
            Padding(
              padding: EdgeInsets.only(top: i == 0 ? 0 : 6),
              child: _MealCard(
                entry: e,
                roster: roster,
                // D8: a meal this person is not eating is dimmed, not gone.
                dimmed: lens != null && !e.eaterIds.contains(lens),
                cookPlan: cookPlan,
                todayDayOfWeek: todayDayOfWeek,
              ),
            ),
        ],
      ),
    );
  }
}

/// One meal: the phone dish row's anatomy compacted into a card.
///
/// The same facts, in the same words — the title (clamped to two lines, because
/// a third turns a row into a paragraph), the cook marker with its mini
/// fresh→gone bar, `edited for this week` where the week varies the recipe, a
/// snack's stated amount, the portions chip, the eaters and the `−`. And the
/// same three targets, all drawn: title, eaters, remove.
class _MealCard extends ConsumerWidget {
  const _MealCard({
    required this.entry,
    required this.roster,
    required this.dimmed,
    required this.cookPlan,
    required this.todayDayOfWeek,
  });

  final PlanEntry entry;
  final List<Member> roster;
  final bool dimmed;
  final CookPlan? cookPlan;
  final int? todayDayOfWeek;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final snack = entry.isIngredient;
    final deleted = entry.title == null;
    final plan = cookPlan;
    // A SNACK has no cook marker: nothing about a protein bar is cooked. Its
    // stated amount sits in the marker's place instead.
    final marker = plan == null || snack
        ? null
        : cookMarkerFor(
            plan,
            recipeId: entry.recipeId!,
            dayOfWeek: entry.dayOfWeek,
            mealSlot: entry.mealSlot,
          );
    final weekKey = isoDateOf(ref.watch(viewedWeekStartProvider));
    final edited =
        (ref.watch(viewedWeekOverridesProvider).asData?.value[entry.recipeId] ??
                const [])
            .isNotEmpty;
    final portions = portionsChipFor(entry, roster);

    return Opacity(
      opacity: dimmed ? 0.38 : 1,
      child: Container(
        padding: const EdgeInsets.fromLTRB(7, 6, 7, 7),
        decoration: BoxDecoration(
          color: AnsiColors.surface,
          border: Border.all(color: AnsiColors.line),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            GestureDetector(
              behavior: HitTestBehavior.opaque,
              // The title opens the thing it NAMES, with the week it is
              // planned in; a deleted target has no page, so it is inert.
              onTap: deleted
                  ? null
                  : () => context.pushOnce(
                      snack
                          ? '/ingredients/${entry.ingredientId}'
                          : '/recipes/${entry.recipeId}?week=$weekKey',
                    ),
              child: Text(
                entry.title ??
                    (snack ? '(deleted ingredient)' : '(deleted recipe)'),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: deleted
                    ? ansiSans(size: 12, color: AnsiColors.muted, height: 1.25)
                    : ansiSans(
                        size: 12,
                        height: 1.25,
                        color: snack ? AnsiColors.ink : AnsiColors.herbDeep,
                        weight: snack ? FontWeight.w400 : FontWeight.w600,
                      ),
              ),
            ),
            if (marker != null)
              Padding(
                padding: const EdgeInsets.only(top: 5),
                child: CookMarkerLine(
                  marker: marker,
                  todayDayOfWeek: todayDayOfWeek,
                  wrap: true,
                ),
              ),
            // In a column this narrow the mark STACKS under the cook marker
            // rather than sitting beside it: nothing fits beside anything.
            if (edited)
              const Padding(
                padding: EdgeInsets.only(top: 4),
                child: EditedForThisWeekMark(),
              ),
            if (snack)
              Padding(
                padding: const EdgeInsets.only(top: 5),
                child: Text(
                  snackAmount(entry),
                  style: ansiMono(size: 10, color: AnsiColors.muted),
                ),
              ),
            if (portions != null)
              Padding(
                padding: const EdgeInsets.only(top: 5),
                child: PortionsChip(portions: portions),
              ),
            Row(
              children: [
                Expanded(
                  child: EatersTarget(
                    entry: entry,
                    roster: roster,
                    // The chip has its own line above: at this width it cannot
                    // share one with the avatars.
                    portions: null,
                  ),
                ),
                RemoveTarget(entry: entry, roster: roster),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// The pinned column feet: each day's one `＋ add a meal`, in every state, and
/// under it the day's energy and its denominator.
class _FootRow extends ConsumerWidget {
  const _FootRow({
    required this.scope,
    required this.lens,
    required this.onAddMeal,
  });

  final String scope;
  final String? lens;
  final void Function(int dayOfWeek) onAddMeal;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const SizedBox(width: _gutter),
          for (var d = 0; d < 7; d++)
            Expanded(
              child: Container(
                decoration: const BoxDecoration(
                  border: Border(left: BorderSide(color: AnsiColors.line)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // Never `nothing planned` here: the column foot says `add a
                    // meal` in every state, and the day's own emptiness is said
                    // by the line under it.
                    AddMealLine(
                      empty: false,
                      onTap: () => onAddMeal(d),
                      padding: const EdgeInsets.fromLTRB(6, 8, 6, 0),
                    ),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(6, 8, 6, 10),
                      child: DayMacroFootLine(
                        macros: ref.watch(dayMacrosProvider(d, lens)),
                        scope: scope,
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

/// The rest of each day's macro line, one block per column, under the matrix.
///
/// A second full-width band is what this treatment costs: it pushes the matrix
/// up by its own height and is the first thing under the fold on a short
/// window. What it buys is the day's figures under the day, in the phone's own
/// words, without squeezing them into a 111 px foot.
class _MacroBand extends ConsumerWidget {
  const _MacroBand({required this.scope, required this.lens});

  final String scope;
  final String? lens;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(
            width: _gutter,
            child: Container(
              padding: const EdgeInsets.fromLTRB(0, 10, 8, 0),
              decoration: const BoxDecoration(
                border: Border(top: BorderSide(color: AnsiColors.line)),
              ),
              child: Text(
                'PER DAY',
                textAlign: TextAlign.right,
                style: ansiMono(
                  size: 9,
                  color: AnsiColors.muted,
                  letterSpacing: 1,
                ),
              ),
            ),
          ),
          for (var d = 0; d < 7; d++)
            Expanded(
              child: Container(
                padding: const EdgeInsets.fromLTRB(6, 9, 6, 10),
                decoration: const BoxDecoration(
                  color: AnsiColors.paper,
                  border: Border(
                    top: BorderSide(color: AnsiColors.line),
                    left: BorderSide(color: AnsiColors.line),
                  ),
                ),
                child: DayMacroBandCell(
                  macros: ref.watch(dayMacrosProvider(d, lens)),
                  scope: scope,
                ),
              ),
            ),
        ],
      ),
    );
  }
}
