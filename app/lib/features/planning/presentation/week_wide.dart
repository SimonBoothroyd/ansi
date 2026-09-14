/// The Week at [AnsiLayout.expanded] — **one day, large, beside the week that
/// scrolls.**
///
/// The owner's ruling, after seeing the matrix on his real household: *"option
/// C is the closest, I like the left panel … Remember on web / iPad we can
/// easily scroll. Clarity over compactness wins."* The matrix answered the
/// wrong question. It fitted seven days into one screenful, and the price was a
/// clipped 11 px line per meal, a bordered card around every one of them, and
/// `from Sunday's batch` said fifteen times. A desk has vertical room and a
/// scroll wheel; it does not have to be a calendar.
///
/// So the pane is two:
///
/// * **The day pane** (560, fixed) draws ONE day at reading size — today by
///   default, or the day the person picked on the right. Each meal gets its
///   slot, who eats it, what cooks (`cooks today · batch of 6 · feeds Mon, Tue,
///   Wed`), its `−`, and one line of its own macros *as served to the eaters*.
///   The day's ledger is pinned to the foot, so the meals may scroll past it
///   and the numbers stay where they were.
/// * **The agenda** (the rest) is the whole week as a vertical list that
///   scrolls: a heading per day, one `3 661 kcal · 3 meals` line under it, and
///   the meals as single Spectral lines that WRAP rather than truncate. One
///   quiet `›` per day makes it the day pane's day.
///
/// **The batch story leaves the right pane, deliberately.** No cook markers, no
/// batch ticks, no leaders, no per-day grams. Nothing on the agenda says
/// Wednesday's dinner is Monday's leftovers — that reads in the day pane, one
/// tap away, and in Cook. Clarity was bought by moving the relationship rather
/// than by stating it better, and that is the trade the owner took.
///
/// **It is the phone's week, not a second one.** One view model
/// (`week_view_models.dart`), one vocabulary (`week_macro_widgets.dart`,
/// `week_format.dart`) and one set of doors — a meal's `−` runs the same undo,
/// its eaters open the same editor, its title opens the same page, and the add
/// door is [AddMealLine] with its own day. What changes is the shape and, in
/// the wide form, the wording of the numbers: words where the phone has glyphs,
/// because a 560 px pane has the room a 320 px strip never had.
///
/// **Nothing here is dragged.** The week has no `move`, so a meal changes day
/// by being removed and added again, and every target is drawn.
library;

import 'package:flutter/widgets.dart';
import 'package:forui/forui.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

import '../../../core/theme/ansi_theme.dart';
import '../../../core/theme/ansi_tokens.dart';
import '../../../core/week_shape.dart';
import '../../../shared/ansi_layout.dart';
import '../../../shared/ansi_scroll.dart';
import '../../../shared/ansi_tap.dart';
import '../../../shared/guarded_navigation.dart';
import '../../account/data/household_providers.dart';
import '../../cook_plan/domain/cook_plan.dart';
import '../domain/planning.dart';
import 'copy_last_week.dart';
import 'week_format.dart';
import 'week_macro_widgets.dart';
import 'week_view_models.dart';
import 'week_widgets.dart';

/// The day pane's width. Fixed, at every expanded width: it is a measure for
/// one day of reading, and the agenda beside it is what gives when the window
/// narrows to an iPad's 1180 — the names still set on one line there, so what
/// is spent is slack, not type.
const _panePx = 560.0;

/// The eater mark the agenda prints beside a meal, or null when it would add
/// nothing.
///
/// A meal both members eat is the household's ordinary case, and printing
/// `SA` on nineteen lines out of twenty is noise that hides the twentieth. So
/// the mark appears only where the meal is NOT for everyone: `A` on the oats
/// Ana alone eats, and `nobody` — the phone's own word — on a meal with no
/// eaters at all — a real state the day's macro line already refuses on.
String? eaterMark(PlanEntry entry, List<Member> roster) {
  final eaters = entry.eaterIds.toSet();
  if (eaters.isEmpty) return 'nobody';
  if (roster.isNotEmpty && roster.every((m) => eaters.contains(m.id))) {
    return null;
  }
  return [
    for (final m in roster)
      if (eaters.contains(m.id)) m.initial,
  ].join(' ');
}

/// Consecutive same-slot runs of a day's entries, grouped under one label.
///
/// `entriesForDay` is already slot-ordered, so a run is contiguous; the
/// comparison is case-insensitive for the same reason [defaultMealSlot] is — a
/// day that typed `dinner` belongs under Dinner, not beside it.
List<List<PlanEntry>> slotGroupsOf(List<PlanEntry> entries) {
  final groups = <List<PlanEntry>>[];
  for (final e in entries) {
    if (groups.isNotEmpty &&
        groups.last.first.mealSlot.toLowerCase() == e.mealSlot.toLowerCase()) {
      groups.last.add(e);
    } else {
      groups.add([e]);
    }
  }
  return groups;
}

class WeekWide extends StatelessWidget {
  const WeekWide({
    required this.weekStart,
    required this.plan,
    required this.roster,
    required this.lens,
    required this.scope,
    required this.cookPlan,
    required this.todayDayOfWeek,
    required this.selectedDay,
    required this.onSelectDay,
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

  /// The day the left pane draws, already resolved — today when the week on
  /// screen contains it, the week's first day otherwise.
  ///
  /// It lives in the LOCATION (`/week?day=YYYY-MM-DD`), which is what makes a
  /// refresh land back on it; [onSelectDay] restates the location and the new
  /// day arrives back through here. See `WeekView.dayKey`.
  final int selectedDay;

  /// The `›`: stand on another day. It restates the location rather than
  /// pushing, so browser back leaves the week instead of walking back through
  /// every day that was read.
  final void Function(int dayOfWeek) onSelectDay;

  /// Opens the add flow on one day — the phone card's own door, with its day.
  final void Function(int dayOfWeek) onAddMeal;

  /// Offered only while the week is empty and there is a week behind it.
  final VoidCallback? onCopyLastWeek;

  @override
  Widget build(BuildContext context) {
    final day = selectedDay;
    final copy = onCopyLastWeek;
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
        Expanded(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SizedBox(
                width: _panePx,
                child: Container(
                  decoration: const BoxDecoration(
                    border: Border(right: BorderSide(color: AnsiColors.line)),
                  ),
                  child: _DayPane(
                    weekStart: weekStart,
                    dayOfWeek: day,
                    entries: plan?.entriesForDay(day) ?? const [],
                    roster: roster,
                    lens: lens.value,
                    scope: scope,
                    cookPlan: cookPlan,
                    todayDayOfWeek: todayDayOfWeek,
                    onAddMeal: () => onAddMeal(day),
                  ),
                ),
              ),
              Expanded(
                child: _Agenda(
                  weekStart: weekStart,
                  plan: plan,
                  roster: roster,
                  lens: lens.value,
                  scope: scope,
                  todayDayOfWeek: todayDayOfWeek,
                  selectedDay: day,
                  onSelectDay: onSelectDay,
                  onAddMeal: onAddMeal,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

/// ONE day, drawn large: the day it is, its meals at reading size, its add
/// door, and its ledger pinned to the foot.
class _DayPane extends ConsumerWidget {
  const _DayPane({
    required this.weekStart,
    required this.dayOfWeek,
    required this.entries,
    required this.roster,
    required this.lens,
    required this.scope,
    required this.cookPlan,
    required this.todayDayOfWeek,
    required this.onAddMeal,
  });

  final DateTime weekStart;
  final int dayOfWeek;
  final List<PlanEntry> entries;
  final List<Member> roster;
  final String? lens;
  final String scope;
  final CookPlan? cookPlan;

  /// Today's offset within the week on screen, or null when the week on screen
  /// is not the one containing today — what makes `cooks today` true.
  final int? todayDayOfWeek;
  final VoidCallback onAddMeal;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isToday = todayDayOfWeek == dayOfWeek;
    return Padding(
      padding: const EdgeInsets.fromLTRB(30, 26, 30, 22),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // The eyebrow is drawn only when the day IS today. A day the person
          // chose needs no label — its name is the heading, and a permanent
          // strip that sometimes says nothing is a strip that says nothing.
          if (isToday)
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Row(
                children: [
                  Text(
                    'TODAY',
                    style: ansiMono(
                      size: 10,
                      color: AnsiColors.herb,
                      weight: FontWeight.w500,
                      letterSpacing: 2,
                    ),
                  ),
                  const SizedBox(width: 12),
                  const Expanded(
                    child: SizedBox(
                      height: 1,
                      child: ColoredBox(color: AnsiColors.line),
                    ),
                  ),
                ],
              ),
            ),
          Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Flexible(
                child: Text(
                  ref.watch(weekShapeProvider).labelFull(dayOfWeek),
                  style: ansiSerif(size: 38, weight: FontWeight.w500),
                ),
              ),
              const SizedBox(width: 14),
              Text(
                formatDayDate(weekStart, dayOfWeek),
                style: ansiMono(size: 12, color: AnsiColors.muted),
              ),
            ],
          ),
          // The meals scroll; the ledger below does not. A five-meal Monday is
          // taller than an iPad's 758 px, and on the web a pane scrolls without
          // ceremony — what must not scroll away is the day's total.
          Expanded(
            child: SingleChildScrollView(
              padding: ansiScrollPadding(
                context,
                const EdgeInsets.only(top: 20, bottom: 6),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  for (final group in slotGroupsOf(entries))
                    for (final (i, entry) in group.indexed)
                      _PaneMeal(
                        entry: entry,
                        slot: i == 0 ? group.first.mealSlot : null,
                        roster: roster,
                        lens: lens,
                        // D8: a meal this person is not eating is dimmed, not
                        // gone — a day somebody else cooks for themselves is
                        // not an empty day.
                        dimmed: lens != null && !entry.eaterIds.contains(lens),
                        cookPlan: cookPlan,
                        todayDayOfWeek: todayDayOfWeek,
                      ),
                  // The phone's one add door, in every state: `add a meal`, or
                  // `nothing planned` on a day that holds nothing — which is
                  // how this pane says a day is empty.
                  Padding(
                    padding: const EdgeInsets.only(top: 22),
                    child: AddMealLine(
                      empty: entries.isEmpty,
                      onTap: onAddMeal,
                      padding: const EdgeInsets.symmetric(vertical: 13),
                    ),
                  ),
                ],
              ),
            ),
          ),
          DayLedger(
            macros: ref.watch(dayMacrosProvider(dayOfWeek, lens)),
            scope: scope,
          ),
        ],
      ),
    );
  }
}

/// One meal in the day pane: its slot, who eats it, what cooks, and what it is
/// worth as served.
///
/// The same facts the phone row prints, in the same words and through the same
/// targets — at reading size, and with one line the phone has no room for: the
/// meal's own macros ([MealMacroLine]).
class _PaneMeal extends ConsumerWidget {
  const _PaneMeal({
    required this.entry,
    required this.slot,
    required this.roster,
    required this.lens,
    required this.dimmed,
    required this.cookPlan,
    required this.todayDayOfWeek,
  });

  final PlanEntry entry;

  /// The slot label, on the FIRST meal of a run only — two dishes in one slot
  /// are one slot, said once.
  final String? slot;
  final List<Member> roster;
  final String? lens;
  final bool dimmed;
  final CookPlan? cookPlan;

  /// Today's offset within the week on screen — see [cookMarkerLabel].
  final int? todayDayOfWeek;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final snack = entry.isIngredient;
    final plan = cookPlan;
    // A SNACK has no cook marker, and that is a ruling (A-D5): nothing about a
    // protein bar is cooked. Its stated amount sits in the marker's place.
    final marker = plan == null || snack
        ? null
        : cookMarkerFor(
            plan,
            recipeId: entry.recipeId!,
            dayOfWeek: entry.dayOfWeek,
            mealSlot: entry.mealSlot,
          );
    final weekKey = isoDateOf(ref.watch(viewedWeekStartProvider));
    final route = mealTitleRoute(entry, weekKey: weekKey);
    final edited =
        (ref.watch(viewedWeekOverridesProvider).asData?.value[entry.recipeId] ??
                const [])
            .isNotEmpty;
    return Opacity(
      opacity: dimmed ? 0.38 : 1,
      child: Container(
        margin: const EdgeInsets.only(top: 22),
        padding: const EdgeInsets.only(top: 20),
        decoration: const BoxDecoration(
          border: Border(top: BorderSide(color: AnsiColors.line)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                if (slot != null)
                  Text(
                    slot!.toUpperCase(),
                    style: ansiMono(
                      size: 9.5,
                      color: AnsiColors.muted,
                      weight: FontWeight.w500,
                      letterSpacing: 1.5,
                    ),
                  ),
                const Spacer(),
                EatersTarget(
                  entry: entry,
                  roster: roster,
                  portions: portionsChipFor(entry, roster),
                ),
                RemoveTarget(entry: entry, roster: roster),
              ],
            ),
            GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: route == null ? null : () => context.pushOnce(route),
              child: Padding(
                padding: const EdgeInsets.only(top: 4, bottom: 10),
                child: Text(
                  mealTitleText(entry),
                  // No truncation anywhere in this pane: a name that needs two
                  // lines takes two. `Clarity over compactness wins.`
                  style: entry.title == null
                      ? ansiSerif(size: 22, color: AnsiColors.muted)
                      // A snack is VISIBLY not a recipe (A-D5) — the dish's
                      // emphasis is what says "there is a page behind this".
                      : ansiSerif(
                          size: 24,
                          weight: snack ? FontWeight.w400 : FontWeight.w500,
                        ),
                ),
              ),
            ),
            if (marker != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                // wrap, not ellipsis: half of `from Tuesday's batch` names the
                // wrong day.
                child: CookMarkerLine(
                  marker: marker,
                  todayDayOfWeek: todayDayOfWeek,
                  wrap: true,
                ),
              ),
            if (edited)
              const Padding(
                padding: EdgeInsets.only(bottom: 8),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: EditedForThisWeekMark(),
                ),
              ),
            // The snack's amount sits exactly where a cook marker would — the
            // line says what this meal IS, since nothing about it is cooked.
            if (snack)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Text(
                  snackAmount(entry),
                  style: ansiMono(size: 11.5, color: AnsiColors.muted),
                ),
              ),
            // What the owner asked for on top of C3: the recipe's macros, per
            // meal, beside the day's. Read through the day total's own
            // function so the parts cannot disagree with the sum.
            MealMacroLine(
              macros: ref.watch(mealMacrosProvider(entry.id, lens)),
            ),
          ],
        ),
      ),
    );
  }
}

/// The whole week as a vertical agenda that scrolls.
///
/// Seven headings from the household's first day, each with its energy line,
/// its meals as single wrapping lines, its add door and — unless it is the day
/// already open at left — one quiet `›`.
class _Agenda extends ConsumerWidget {
  const _Agenda({
    required this.weekStart,
    required this.plan,
    required this.roster,
    required this.lens,
    required this.scope,
    required this.todayDayOfWeek,
    required this.selectedDay,
    required this.onSelectDay,
    required this.onAddMeal,
  });

  final DateTime weekStart;
  final WeekPlan? plan;
  final List<Member> roster;
  final String? lens;
  final String scope;
  final int? todayDayOfWeek;
  final int selectedDay;
  final void Function(int dayOfWeek) onSelectDay;
  final void Function(int dayOfWeek) onAddMeal;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(26, 26, 26, 10),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Text(
                'THE WEEK',
                style: ansiMono(
                  size: 10,
                  color: AnsiColors.muted,
                  weight: FontWeight.w500,
                  letterSpacing: 2,
                ),
              ),
              const SizedBox(width: 12),
              Text(
                formatWeekSpan(weekStart),
                style: ansiMono(size: 10, color: AnsiColors.muted),
              ),
            ],
          ),
        ),
        Expanded(
          child: ListView(
            padding: ansiScrollPadding(
              context,
              const EdgeInsets.only(bottom: 26),
            ),
            children: [
              for (var d = 0; d < 7; d++)
                _AgendaDay(
                  weekStart: weekStart,
                  dayOfWeek: d,
                  entries: plan?.entriesForDay(d) ?? const [],
                  roster: roster,
                  lens: lens,
                  scope: scope,
                  isToday: todayDayOfWeek == d,
                  selected: selectedDay == d,
                  onSelect: () => onSelectDay(d),
                  onAddMeal: () => onAddMeal(d),
                ),
            ],
          ),
        ),
      ],
    );
  }
}

/// One day of the agenda.
class _AgendaDay extends ConsumerWidget {
  const _AgendaDay({
    required this.weekStart,
    required this.dayOfWeek,
    required this.entries,
    required this.roster,
    required this.lens,
    required this.scope,
    required this.isToday,
    required this.selected,
    required this.onSelect,
    required this.onAddMeal,
  });

  final DateTime weekStart;
  final int dayOfWeek;
  final List<PlanEntry> entries;
  final List<Member> roster;
  final String? lens;
  final String scope;
  final bool isToday;
  final bool selected;
  final VoidCallback onSelect;
  final VoidCallback onAddMeal;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final shape = ref.watch(weekShapeProvider);
    final empty = entries.isEmpty;
    return Container(
      decoration: BoxDecoration(
        color: selected ? AnsiColors.herbSoft : null,
        border: Border(
          top: const BorderSide(color: AnsiColors.line),
          // The lit day carries a herb rule down its left edge — the same mark
          // the phone's day card gives today, spent here on the day that is
          // open at left.
          left: BorderSide(
            color: selected ? AnsiColors.herb : const Color(0x00000000),
            width: 3,
          ),
        ),
      ),
      padding: const EdgeInsets.fromLTRB(23, 11, 26, 13),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // The heading is the target that opens the day at left; the `›` is
          // what draws it, and the day already open draws none (there is
          // nowhere to go).
          AnsiTap(
            onTap: selected ? null : onSelect,
            // The heading is the door, and the `›` only draws it — so the
            // ground is the whole heading rather than the glyph at its end.
            radius: 4,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.baseline,
              textBaseline: TextBaseline.alphabetic,
              children: [
                Text(
                  shape.labelFull(dayOfWeek),
                  style: ansiSerif(
                    size: 20,
                    weight: FontWeight.w500,
                    color: selected
                        ? AnsiColors.herbDeep
                        : empty
                        ? AnsiColors.muted
                        : AnsiColors.ink,
                  ),
                ),
                const SizedBox(width: 11),
                Text(
                  formatDayDate(weekStart, dayOfWeek),
                  style: ansiMono(size: 11, color: AnsiColors.muted),
                ),
                if (isToday) ...[
                  const SizedBox(width: 11),
                  Text(
                    'TODAY',
                    style: ansiMono(
                      size: 9,
                      color: AnsiColors.herb,
                      weight: FontWeight.w500,
                      letterSpacing: 1.6,
                    ),
                  ),
                ],
                const Spacer(),
                if (!selected)
                  const Icon(
                    FLucideIcons.chevronRight,
                    size: 15,
                    color: AnsiColors.muted,
                  ),
                // The `›` keeps its own ink: this row's ground is a heading's,
                // and a whole day name stepping to herb-deep on hover would
                // read as the day being selected.
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: DayEnergyLine(
              macros: ref.watch(dayMacrosProvider(dayOfWeek, lens)),
              scope: scope,
            ),
          ),
          for (final group in slotGroupsOf(entries))
            Padding(
              padding: const EdgeInsets.only(top: 10),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    group.first.mealSlot.toUpperCase(),
                    style: ansiMono(
                      size: 9.5,
                      color: AnsiColors.muted,
                      weight: FontWeight.w500,
                      letterSpacing: 1.6,
                    ),
                  ),
                  for (final entry in group)
                    _AgendaMeal(
                      entry: entry,
                      roster: roster,
                      dimmed: lens != null && !entry.eaterIds.contains(lens),
                    ),
                ],
              ),
            ),
          AddMealLine(
            empty: empty,
            onTap: onAddMeal,
            divider: false,
            padding: const EdgeInsets.only(top: 11),
          ),
        ],
      ),
    );
  }
}

/// One meal as a single agenda line: the dish, an eater mark where it adds
/// something, and the `−`.
///
/// No cook marker, no batch tick, no portions chip, no macro figure. Those are
/// the day pane's, and saying them here is what made the matrix unreadable.
class _AgendaMeal extends ConsumerWidget {
  const _AgendaMeal({
    required this.entry,
    required this.roster,
    required this.dimmed,
  });

  final PlanEntry entry;
  final List<Member> roster;
  final bool dimmed;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final weekKey = isoDateOf(ref.watch(viewedWeekStartProvider));
    final route = mealTitleRoute(entry, weekKey: weekKey);
    final mark = eaterMark(entry, roster);
    return Opacity(
      opacity: dimmed ? 0.38 : 1,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: route == null ? null : () => context.pushOnce(route),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Text(
                  mealTitleText(entry),
                  // Wrapping allowed, truncation never: the longest name in
                  // the owner's week sets on one line here with room to spare,
                  // and a name that does not fit is still worth all of it.
                  style: ansiSerif(
                    size: 16.5,
                    weight: FontWeight.w400,
                    color: entry.title == null
                        ? AnsiColors.muted
                        : AnsiColors.ink,
                  ).copyWith(height: 1.4),
                ),
              ),
            ),
          ),
          if (mark != null)
            Padding(
              padding: const EdgeInsets.only(left: 10, top: 7),
              child: Text(
                mark,
                style: ansiMono(size: 10, color: AnsiColors.muted),
              ),
            ),
          RemoveTarget(entry: entry, roster: roster),
        ],
      ),
    );
  }
}
