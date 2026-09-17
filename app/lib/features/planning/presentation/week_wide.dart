/// The Week at [AnsiLayout.expanded] — **the week to scan at left, one day to
/// read at right.**
///
/// The owner's ruling, after using the built screen on his own household:
/// *"left and right duplicate too much information, and text on left looks big
/// and angry… maybe the two panes should swap sides, and the days of week pane
/// should be a more compact repr."* Every dish was set twice, once at 24 px in
/// the pane and once at 16.5 px beside it, and the screen read as two lists
/// arguing rather than as a week with a day open in it.
///
/// So the two panes swap and change voice:
///
/// * **The agenda** (340, fixed) is the whole week, small enough to scan in one
///   go. A day is a heading — its name, its date, `TODAY` where it is, and what
///   it holds at the right edge — then **every meal as ONE wrapping run** in
///   the mono at 10.5, names whole, a faint `·` between them and an eater mark
///   only where the meal is not for everyone; then the day's own [MacroStrip].
///   No slot labels, no `−`, no add door: the run is for reading, and the doors
///   are all one tap away in the pane.
/// * **The day pane** (the rest) draws ONE day as a page — today by default, or
///   the day the person picked at left. Each meal gets its slot, who eats it,
///   what cooks, its `−` and its own macros as the muted strip; the day's
///   ledger is pinned to the foot, where the grams are spelt out. It is the
///   only place a meal is added.
/// * **The week band** pins to the agenda's foot ([WeekFootBand]): the week's
///   total in the same strip its days draw, over `avg N · n of 7 days`.
///
/// **Every name, in the small voice.** The run wraps rather than listing one
/// meal per line, and it never truncates — a five-meal day takes three lines at
/// 340, which is what every name costs and what was chosen over `and 3 more`.
///
/// **The batch story stays out of the agenda.** No cook markers, no batch
/// ticks, no leaders. Nothing at left says Wednesday's dinner is Monday's
/// leftovers — that reads in the pane, one tap away, and in Cook.
///
/// **It is the phone's week, not a second one.** One view model
/// (`week_view_models.dart`), one vocabulary (`week_macro_widgets.dart`,
/// `week_format.dart`) and one set of doors — a meal's `−` runs the same undo,
/// its eaters open the same editor, its title opens the same page, and the add
/// door is [AddMealLine] with its own day. The numbers are the phone's strip on
/// both sides; only the pinned ledger has the room to spell its grams out, and
/// it is the one line that does.
///
/// **Nothing here is dragged.** The week has no `move`, so a meal changes day
/// by being removed and added again, and every target is drawn.
library;

import 'package:flutter/widgets.dart';
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
import '../../ingredients/presentation/macro_line_text.dart';
import '../domain/planning.dart';
import 'copy_last_week.dart';
import 'week_format.dart';
import 'week_macro_widgets.dart';
import 'week_view_models.dart';
import 'week_widgets.dart';

/// The agenda's width. Fixed, at every expanded width: it holds the longest
/// name in the household's week inside the run and the day's whole macro strip
/// without scaling it, and the day pane beside it is what gives when the window
/// narrows to an iPad's 1180 — what is spent there is reading slack, not type.
const _agendaPx = 340.0;

/// How wide the day pane's meals and its ledger are allowed to get.
///
/// The pane takes whatever the window leaves, but a dish, a cook marker and a
/// macro strip are lines of reading and a 800 px line of reading is not one.
/// The day's name and date sit outside the cap, at the pane's own edge, so the
/// heading still spans the pane it belongs to.
const _readingPx = 600.0;

/// The run's quiet marks: the `·` between two names, and the eater initial
/// after one. Muted, thinned — they are punctuation among the names rather
/// than names, and at 10.5 a second full-strength ink would read as a word.
final _runQuiet = AnsiColors.muted.withValues(alpha: 0.6);

/// A meal the lens is not on, in the run. The agenda draws a day's meals as
/// ONE line and cannot lift a name out of it, so D8's dimming is the ink's own
/// alpha here rather than an [Opacity] around a row — the same fading, at the
/// only scope the run has.
final _runDimmed = AnsiColors.muted.withValues(alpha: 0.38);

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

/// A day's meals as ONE line: every name whole, a faint `·` between them, and
/// an eater mark where [eaterMark] has something to say.
///
/// One voice for the whole run — a snack is muted like everything else in it.
/// What a meal *is* reads in the pane, where a dish's weight tells a recipe
/// from a handful of almonds; here the line is a list of names to scan, and a
/// second ink in it would be a distinction nobody asked the agenda for.
///
/// **One exception, and it is not an ink**: a meal eaten OUT carries a hollow
/// dot before its name. The agenda's other rows are all things the week will
/// cook or buy, and this one is neither — a fact worth seeing while scanning
/// seven days, and the only fact in the run that changes what the days below
/// it mean. It stays in the run's own voice: the same size, the same muted
/// colour, an outline rather than a second colour.
List<InlineSpan> mealRunSpans(
  List<PlanEntry> entries, {
  required List<Member> roster,
  required String? lens,
}) {
  final spans = <InlineSpan>[];
  for (final entry in entries) {
    if (spans.isNotEmpty) {
      spans.add(
        TextSpan(
          text: ' · ',
          style: ansiMono(size: 10.5, color: _runQuiet),
        ),
      );
    }
    // D8: a meal this person is not eating fades, it does not leave — a day
    // somebody else cooks for themselves is not an empty day.
    final dimmed = lens != null && !entry.eaterIds.contains(lens);
    final name = ansiMono(
      size: 10.5,
      color: dimmed ? _runDimmed : AnsiColors.muted,
    );
    if (entry.kind == PlanEntryKind.out) {
      // Drawn through the macro line's own span builder, which sits a glyph
      // on the middle of the digits' ink rather than on the font's ascent
      // midpoint — the alignment a run at this size cannot afford to get
      // wrong. Its semantic label is the word the mark replaces.
      spans
        ..add(
          macroUnitSpan(kMealOutIcon, label: 'eaten out', style: name),
        )
        ..add(TextSpan(text: ' ', style: name));
    }
    spans.add(TextSpan(text: mealTitleText(entry), style: name));
    final mark = eaterMark(entry, roster);
    if (mark != null) {
      spans.add(
        TextSpan(
          text: mark,
          // Smaller and quieter than the name it belongs to, so it reads as a
          // mark ON the name rather than as another meal.
          style: ansiMono(
            size: 8.5,
            color: dimmed ? _runDimmed : _runQuiet,
            letterSpacing: 0.4,
          ),
        ),
      );
    }
  }
  return spans;
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

  /// The day the right pane draws, already resolved — today when the week on
  /// screen contains it, the week's first day otherwise.
  ///
  /// It lives in the LOCATION (`/week?day=YYYY-MM-DD`), which is what makes a
  /// refresh land back on it; [onSelectDay] restates the location and the new
  /// day arrives back through here. See `WeekView.dayKey`.
  final int selectedDay;

  /// Stand on another day. It restates the location rather than pushing, so
  /// browser back leaves the week instead of walking back through every day
  /// that was read.
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
                width: _agendaPx,
                child: DecoratedBox(
                  decoration: const BoxDecoration(
                    border: Border(right: BorderSide(color: AnsiColors.line)),
                  ),
                  child: _Agenda(
                    weekStart: weekStart,
                    plan: plan,
                    roster: roster,
                    lens: lens.value,
                    scope: scope,
                    todayDayOfWeek: todayDayOfWeek,
                    selectedDay: day,
                    onSelectDay: onSelectDay,
                  ),
                ),
              ),
              Expanded(
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
            ],
          ),
        ),
      ],
    );
  }
}

/// ONE day as a page: the day it is, its meals at reading size, its add door,
/// and its ledger pinned to the foot.
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
      padding: const EdgeInsets.fromLTRB(30, 22, 34, 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // The eyebrow is drawn only when the day IS today. A day the person
          // chose needs no label — its name is the heading, and a permanent
          // strip that sometimes says nothing is a strip that says nothing.
          if (isToday)
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
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
                  style: ansiSerif(
                    size: AnsiType.title,
                    weight: FontWeight.w500,
                  ),
                ),
              ),
              const SizedBox(width: 12),
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
                const EdgeInsets.only(top: 12, bottom: 6),
              ),
              child: _Reading(
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
                          dimmed:
                              lens != null && !entry.eaterIds.contains(lens),
                          cookPlan: cookPlan,
                          todayDayOfWeek: todayDayOfWeek,
                        ),
                    // The week's ONE add door, in every state: `add a meal`, or
                    // `nothing planned` on a day that holds nothing — which is
                    // how this pane says a day is empty. The agenda has none:
                    // seven doors onto a list nobody adds from are seven doors.
                    Padding(
                      padding: const EdgeInsets.only(top: 12),
                      child: AddMealLine(
                        empty: entries.isEmpty,
                        onTap: onAddMeal,
                        padding: const EdgeInsets.symmetric(vertical: 11),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          _Reading(
            child: DayLedger(
              macros: ref.watch(dayMacrosProvider(dayOfWeek, lens)),
              scope: scope,
            ),
          ),
        ],
      ),
    );
  }
}

/// One column of reading in the day pane, at [_readingPx], left-aligned in
/// whatever width the window leaves.
class _Reading extends StatelessWidget {
  const _Reading({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) => Align(
    alignment: Alignment.centerLeft,
    child: ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: _readingPx),
      child: child,
    ),
  );
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
    final kind = entry.kind;
    final snack = kind == PlanEntryKind.ingredient;
    final out = kind == PlanEntryKind.out;
    final plan = cookPlan;
    // Only a RECIPE has a cook marker, and that is a ruling (A-D5): nothing
    // about a protein bar or a canteen lunch is cooked. What the meal IS takes
    // the marker's place — a snack's amount, a meal out's tag and figures.
    final marker = plan == null || kind != PlanEntryKind.recipe
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
        margin: const EdgeInsets.only(top: 10),
        padding: const EdgeInsets.only(top: 10),
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
                padding: const EdgeInsets.only(top: 2, bottom: 6),
                child: Text(
                  mealTitleText(entry),
                  // No truncation anywhere in this pane: a name that needs two
                  // lines takes two. `Clarity over compactness wins.`
                  style: entry.title == null
                      ? ansiSerif(size: AnsiType.row, color: AnsiColors.muted)
                      // Three weights for three kinds (A-D5) — the dish's
                      // emphasis is what says "there is a page behind this",
                      // so a snack reads plainer and a meal eaten out, which
                      // has no page at all, reads plain and italic.
                      : out
                      ? ansiSerif(
                          size: AnsiType.row,
                          weight: FontWeight.w400,
                        ).copyWith(fontStyle: FontStyle.italic)
                      : snack
                      ? ansiSerif(
                          size: AnsiType.row,
                          weight: FontWeight.w400,
                          color: AnsiColors.muted,
                        )
                      : ansiSerif(size: AnsiType.row, weight: FontWeight.w500),
                ),
              ),
            ),
            if (marker != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 6),
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
                padding: EdgeInsets.only(bottom: 6),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: EditedForThisWeekMark(),
                ),
              ),
            // The snack's amount sits exactly where a cook marker would — the
            // line says what this meal IS, since nothing about it is cooked.
            if (snack)
              Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Text(
                  snackAmount(entry),
                  style: ansiMono(size: 11, color: AnsiColors.muted),
                ),
              ),
            // And a meal eaten out says the same thing in its own terms.
            if (out)
              Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: OutMealLine(entry: entry, size: 11),
              ),
            // The recipe's macros, per meal, beside the day's — read through
            // the day total's own function so the parts cannot disagree with
            // the sum, and drawn in the strip every other line here speaks.
            MealMacroLine(
              macros: ref.watch(mealMacrosProvider(entry.id, lens)),
            ),
          ],
        ),
      ),
    );
  }
}

/// The whole week as a vertical agenda, with the week's own band at its foot.
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
  });

  final DateTime weekStart;
  final WeekPlan? plan;
  final List<Member> roster;
  final String? lens;
  final String scope;
  final int? todayDayOfWeek;
  final int selectedDay;
  final void Function(int dayOfWeek) onSelectDay;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(22, 22, 22, 8),
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
          // This list keeps no scroll gutter, and it is the one pane that
          // does not: a day's own 18 px right padding already clears the thumb
          // by the air the gutter is made of, and adding it here would inset
          // the lit day's wash from the edge it is drawn to.
          child: ListView(
            padding: const EdgeInsets.only(bottom: 10),
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
                ),
            ],
          ),
        ),
        WeekFootBand(macros: ref.watch(weekMacrosProvider(lens)), scope: scope),
      ],
    );
  }
}

/// One day of the agenda: a heading, every meal in one run, and the day's
/// macro strip.
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

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final shape = ref.watch(weekShapeProvider);
    final macros = ref.watch(dayMacrosProvider(dayOfWeek, lens));
    final empty = entries.isEmpty;
    return AnsiTap(
      // The whole day is the door — there is nothing else on it to aim at, and
      // a `›` at the end of a row that is entirely a target only says where
      // the target is not. The day already open has nowhere to go.
      onTap: selected ? null : onSelect,
      radius: 0,
      child: Container(
        decoration: BoxDecoration(
          color: selected ? AnsiColors.herbSoft : null,
          border: Border(
            top: const BorderSide(color: AnsiColors.line),
            // The lit day carries a herb rule down its left edge — the same
            // mark the phone's day card gives today, spent here on the day
            // that is open beside it.
            left: BorderSide(
              color: selected ? AnsiColors.herb : const Color(0x00000000),
              width: 3,
            ),
          ),
        ),
        padding: const EdgeInsets.fromLTRB(17, 11, 18, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.baseline,
              textBaseline: TextBaseline.alphabetic,
              children: [
                Text(
                  shape.labelFull(dayOfWeek),
                  style: ansiSerif(
                    size: AnsiType.small,
                    weight: FontWeight.w500,
                    color: selected
                        ? AnsiColors.herbDeep
                        : empty
                        ? AnsiColors.muted
                        : AnsiColors.ink,
                  ),
                ),
                const SizedBox(width: 9),
                Text(
                  formatDayDate(weekStart, dayOfWeek),
                  style: ansiMono(size: 10.5, color: AnsiColors.muted),
                ),
                if (isToday) ...[
                  const SizedBox(width: 9),
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
                const SizedBox(width: 10),
                // What the day HOLDS, at the right edge: the figures are the
                // strip below, so the heading counts. It takes the rest of the
                // row and wraps rather than shortening — `no meals for Ana
                // Maria` is a whole sentence or it is a wrong one.
                Expanded(
                  child: Text(
                    dayCountLabel(macros, scope: scope),
                    textAlign: TextAlign.end,
                    style: ansiMono(
                      size: 10.5,
                      color: empty ? _runQuiet : AnsiColors.muted,
                    ),
                  ),
                ),
              ],
            ),
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: empty
                  // An empty day says so where its run would be, in the words
                  // the add door says it in — and never `0 kcal`.
                  ? Text(
                      'nothing planned',
                      style: ansiMono(
                        size: 10.5,
                        color: _runQuiet,
                      ).copyWith(fontStyle: FontStyle.italic, height: 1.55),
                    )
                  : Text.rich(
                      TextSpan(
                        children: mealRunSpans(
                          entries,
                          roster: roster,
                          lens: lens,
                        ),
                      ),
                      style: const TextStyle(height: 1.55),
                    ),
            ),
            if (macros.isRefused)
              // No strip at all: a day that resolved nothing has no number to
              // draw, and it names the meal that stopped it — [DayEnergyLine]'s
              // own refusal, which is the app's one wording for this.
              Padding(
                padding: const EdgeInsets.only(top: 5),
                child: DayEnergyLine(macros: macros, scope: scope, size: 11.5),
              )
            else if (macros.total != null)
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: MacroStrip(macros: macros.total!),
              ),
          ],
        ),
      ),
    );
  }
}
