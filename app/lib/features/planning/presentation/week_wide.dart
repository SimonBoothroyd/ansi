/// The Week at [AnsiLayout.expanded]: a compact agenda of the whole week at
/// left, one day to read at right.
///
/// The agenda draws each day as a heading, its meals as one wrapping mono run
/// (names never truncated) and its [MacroStrip]; it has no doors and no cook
/// markers. The day pane draws one day with each meal's slot, eaters, cook
/// marker, `−` and macros, its ledger pinned to the foot; it is the only place
/// a meal is added. Both panes share the phone's view model, wording and
/// targets.
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

/// The agenda's fixed width; the day pane takes what the window leaves.
const _agendaPx = 340.0;

/// The cap on the day pane's line length. The day's heading sits outside it.
const _readingPx = 600.0;

/// The run's punctuation ink: the `·` between names and the eater initial.
final _runQuiet = AnsiColors.muted.withValues(alpha: 0.6);

/// A meal the lens is not on, in the run. The run is one text line, so dimming
/// is the ink's alpha rather than an [Opacity] around a row.
final _runDimmed = AnsiColors.muted.withValues(alpha: 0.38);

/// The eater mark the agenda prints beside a meal: null when everyone eats it,
/// an initial per eater otherwise, `nobody` when it has no eaters.
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

/// A day's meals as one line: every name whole, a faint `·` between them, an
/// [eaterMark] where there is one, and a hollow dot before a meal eaten out.
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
    // A meal this person is not eating fades; it does not leave.
    final dimmed = lens != null && !entry.eaterIds.contains(lens);
    final name = ansiMono(
      size: 10.5,
      color: dimmed ? _runDimmed : AnsiColors.muted,
    );
    if (entry.kind == PlanEntryKind.out) {
      // The macro line's span builder centres the glyph on the digits' ink, not
      // the font's ascent midpoint. Its semantic label is the word it replaces.
      spans
        ..add(macroUnitSpan(kMealOutIcon, label: 'eaten out', style: name))
        ..add(TextSpan(text: ' ', style: name));
    }
    spans.add(TextSpan(text: mealTitleText(entry), style: name));
    final mark = eaterMark(entry, roster);
    if (mark != null) {
      spans.add(
        TextSpan(
          text: mark,
          // Smaller and quieter than the name, so it reads as a mark on it.
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

/// Consecutive same-slot runs of a day's entries. `entriesForDay` is
/// slot-ordered, so a run is contiguous; the comparison is case-insensitive
/// like [defaultMealSlot].
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

  /// null = Everyone; a member id = that person's lens.
  final ValueNotifier<String?> lens;

  /// Whose numbers these are — `Everyone` or a member's display name.
  final String scope;
  final CookPlan? cookPlan;
  final int? todayDayOfWeek;

  /// The day the right pane draws, resolved from `/week?day=`: today when the
  /// week contains it, else the week's first day. See `WeekView.dayKey`.
  final int selectedDay;

  /// Stand on another day. Restates the location rather than pushing, so
  /// browser back leaves the week.
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

/// One day as a page: its meals at reading size, its add door, and its ledger
/// pinned to the foot.
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

  /// Today's offset within the week on screen, or null when that week does not
  /// contain today.
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
          // The eyebrow is drawn only when the day is today.
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
          // The meals scroll; the ledger below does not.
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
                          // A meal this person is not eating is dimmed, not
                          // removed.
                          dimmed:
                              lens != null && !entry.eaterIds.contains(lens),
                          cookPlan: cookPlan,
                          todayDayOfWeek: todayDayOfWeek,
                        ),
                    // The wide Week's one add door; it says `nothing planned`
                    // on an empty day.
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

/// One column of reading at [_readingPx], left-aligned.
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

/// One meal in the day pane: the phone row's facts and targets at reading size,
/// plus the meal's own macros ([MealMacroLine]).
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

  /// The slot label, on the first meal of a same-slot run only.
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
    // Only a recipe has a cook marker; a snack shows its amount and a meal out
    // its tag and figures instead.
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
                  // No truncation in this pane: a long name wraps.
                  style: entry.title == null
                      ? ansiSerif(size: AnsiType.row, color: AnsiColors.muted)
                      // A recipe reads emphasised, a snack plainer, a meal out
                      // plain italic.
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
                // Wrap, not ellipsis: half of `from Tuesday's batch` names the
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
            // The snack's amount sits where a cook marker would.
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
            // Read through the day total's own function so the parts match the
            // sum.
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
          // No scroll gutter here: a day's own right padding already clears the
          // thumb, and a gutter would inset the lit day's wash from the edge.
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

/// One day of the agenda: a heading, every meal in one run, and the day's macro
/// strip.
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
      // The whole day is the target; the open day has nowhere to go.
      onTap: selected ? null : onSelect,
      radius: 0,
      child: Container(
        decoration: BoxDecoration(
          color: selected ? AnsiColors.herbSoft : null,
          border: Border(
            top: const BorderSide(color: AnsiColors.line),
            // The open day carries a herb rule down its left edge.
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
                // What the day holds, at the right edge. It wraps rather than
                // shortening.
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
                  // An empty day says so where its run would be, never `0
                  // kcal`.
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
              // A day that resolved nothing draws no strip; [DayEnergyLine]
              // names the refusal.
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
