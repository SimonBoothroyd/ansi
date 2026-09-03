/// The Week — the meal-planning screen, and the INPUT to the derived
/// cook-plan / shopping pipeline (steps 5–6).
///
/// **One screen, two modes** (week redesign, D1). Presentation is the resting
/// state and answers "what are we eating": each dish row carries its cook
/// marker, its eaters and — when it differs from the eater count — its
/// portions. Edit puts the affordance layer back on: a dashed `＋ Add a meal`
/// under every day, and a `›` on every row.
///
/// The mode earns its existence because it changes **what a tap means** (D7):
/// in presentation a row opens the recipe, in edit it opens the entry sheet.
/// That is the whole justification — one widget tree, one macro path, a
/// density switch rather than a second screen.
///
/// **The numbers are honest** (D4). Each day card foots with its own macro
/// line and that line's denominator; the list foots with the week band. The
/// lens above the cards rescopes both — and DIMS the meals a person is not
/// eating rather than deleting them (D8), because a day somebody else cooks
/// for themselves is not an empty day.
///
/// **There is no blank-week page** (D5). A week with nothing in it is this
/// same screen with nothing in it: header, switcher, mode action, lens row,
/// seven day cards and the week band all render, exactly as they do for a full
/// week. The old `_EmptyWeek` hid the switcher — the one control that gets you
/// OUT of an empty week — swapped the screen out on a data condition, and
/// fired on `entries.isEmpty` too, so removing your last meal teleported you
/// off the grid mid-edit.
///
/// The week itself is a position, not a singleton — see `week_header.dart`
/// (D2) and `week_view_models.dart` (D3).
library;

import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:forui/forui.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

import '../../../core/theme/ansi_theme.dart';
import '../../../core/theme/ansi_tokens.dart';
import '../../../shared/ansi_error_state.dart';
import '../../../shared/dashed_border_box.dart';
import '../../../shared/guarded_navigation.dart';
import '../../../shared/write.dart';
import '../../cook_plan/domain/cook_plan.dart';
import '../../cook_plan/presentation/cook_view_models.dart';
import '../data/planning_providers.dart';
import '../domain/planning.dart';
import 'confirm_meal_sheet.dart';
import 'entry_sheet.dart';
import 'recipe_picker_sheet.dart';
import 'week_format.dart';
import 'week_header.dart';
import 'week_macro_widgets.dart';
import 'week_view_models.dart';
import 'week_widgets.dart';

const _kDefaultSlot = 'Dinner';

/// Which layer of the one screen is showing (D1).
enum WeekMode {
  /// The resting state: what we are eating.
  presentation,

  /// The affordances: add doors, row chevrons, the entry sheet.
  edit,
}

/// The two-step add flow: pick a recipe, then confirm slot/eaters/portions.
Future<void> _addMealFlow(
  BuildContext context, {
  required DateTime weekStart,
  required int dayOfWeek,
}) async {
  final recipe = await showRecipePickerSheet(
    context,
    dayOfWeek: dayOfWeek,
    slot: _kDefaultSlot,
  );
  if (recipe == null || !context.mounted) return;
  await showConfirmMealSheet(
    context,
    weekStart: weekStart,
    dayOfWeek: dayOfWeek,
    slot: _kDefaultSlot,
    recipe: recipe,
  );
}

class WeekView extends HookConsumerWidget {
  const WeekView({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final weekStart = ref.watch(viewedWeekStartProvider);
    final week = ref.watch(viewedWeekProvider);
    // Decorative emptiness, weighed (D6): an empty roster draws no avatars and
    // no lens chips. The week's own meals — the thing this screen is for — are
    // unaffected, and the roster arrives with the first sync.
    final roster = ref.watch(membersProvider).asData?.value ?? const <Member>[];
    // The cook markers are a READ of the derivation the Cook tab draws, for
    // this same week (D6). Null while it loads — a row simply has no second
    // line until it arrives.
    final cookPlan = ref.watch(currentCookPlanProvider).asData?.value;

    // "cooks today" is only true of the week containing today.
    // Read off [Today], not `DateTime.now()`: the Monday is the same all week,
    // so only the day provider re-fires this at a Tuesday midnight.
    final isThisWeek = weekStart == ref.watch(currentWeekStartProvider);
    final todayDayOfWeek = isThisWeek
        ? ref.watch(todayProvider).weekday - 1
        : null;

    final lastWeek = ref.watch(lastWeekProvider).asData?.value;
    final repo = ref.read(planningRepositoryProvider);

    // null = Everyone; a member id = that person's lens (D8: it dims, it does
    // not remove).
    final lens = useState<String?>(null);
    final mode = useState(WeekMode.presentation);
    final scope =
        roster
            .where((m) => m.id == lens.value)
            .map((m) => m.displayName)
            .firstOrNull ??
        'Everyone';

    return FScaffold(
      // A tab root sits INSIDE the shell's scaffold, which already shrinks
      // the branch area for the keyboard; a second scaffold subtracting the
      // same inset squeezes the content twice (Android showed a list a few
      // lines tall after the sign-in keyboard).
      resizeToAvoidBottomInset: false,
      // "Copy last week" used to live in a header `⋯`, a lens-bar chip AND the
      // empty-state button. It now has ONE permanent home — the switcher menu
      // (D2) — plus the empty-week chip below.
      header: FHeader.nested(
        title: WeekSwitcher(
          // The menu speaks in this tab's derivation — "9 meals" — for the
          // week on screen; the other rows stay bare.
          detailFor: (monday) => week.asData == null || monday != weekStart
              ? null
              : formatMealCount(week.asData!.value?.entries.length ?? 0),
        ),
        suffixes: [
          _ModeAction(
            mode: mode.value,
            onTap: () => mode.value = mode.value == WeekMode.presentation
                ? WeekMode.edit
                : WeekMode.presentation,
          ),
        ],
      ),
      child: week.when(
        loading: () => const Center(child: FCircularProgress()),
        error: (e, st) => AnsiErrorState(
          what: 'the week',
          error: e,
          stackTrace: st,
          onRetry: () => ref.invalidate(viewedWeekProvider),
        ),
        // `watchWeek` emitting null stops meaning "show a different screen"
        // and starts meaning "seven empty days" (D5).
        data: (plan) {
          final empty = plan == null || plan.entries.isEmpty;
          return ListView(
            padding: const EdgeInsets.only(top: 8, bottom: 24),
            children: [
              if (empty)
                _FirstMealBar(
                  weekStart: weekStart,
                  hasLastWeek: lastWeek != null,
                  onCopyLastWeek: () => unawaited(
                    ref.write(
                      context,
                      'copy last week',
                      () => repo.copyLastWeek(weekStart),
                    ),
                  ),
                ),
              _LensRow(lens: lens, roster: roster),
              for (var d = 0; d < 7; d++)
                _DayCard(
                  weekStart: weekStart,
                  dayOfWeek: d,
                  entries: plan?.entriesForDay(d) ?? const [],
                  roster: roster,
                  lens: lens.value,
                  scope: scope,
                  mode: mode.value,
                  cookPlan: cookPlan,
                  todayDayOfWeek: todayDayOfWeek,
                ),
              WeekMacroBand(
                macros: ref.watch(weekMacrosProvider(lens.value)),
                scope: scope,
              ),
            ],
          );
        },
      ),
    );
  }
}

/// `Edit` / `Done` — the one control that swaps the affordance layer (D1).
/// Text, not an icon: it names the state you are entering, which no glyph
/// does.
class _ModeAction extends StatelessWidget {
  const _ModeAction({required this.mode, required this.onTap});

  final WeekMode mode;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final editing = mode == WeekMode.edit;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
        child: Text(
          editing ? 'Done' : 'Edit',
          style: ansiSans(
            size: 14,
            color: AnsiColors.herbDeep,
            weight: editing ? FontWeight.w600 : FontWeight.w400,
          ),
        ),
      ),
    );
  }
}

/// The lens (D8): `Everyone · Ada · Jun`, sitting immediately above the first
/// day card — beside the numbers, because whose numbers you are reading is now
/// its only real consequence.
///
/// Selecting a person DIMS the meals they are not eating rather than removing
/// them. The old hard filter made a day the other person cooks for themselves
/// render as an empty day, which is false; and dimming makes the old `⇄
/// shared` tag redundant, because both avatars are right there.
///
/// `Shared` became `Everyone` because "shared" used to name both this lens and
/// a per-entry tag, and one of them had to give.
class _LensRow extends StatelessWidget {
  const _LensRow({required this.lens, required this.roster});

  final ValueNotifier<String?> lens;
  final List<Member> roster;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 0),
      child: Row(
        children: [
          Text('for', style: ansiMono(size: 10, color: AnsiColors.muted)),
          const SizedBox(width: 8),
          _LensChip(
            label: 'Everyone',
            selected: lens.value == null,
            onTap: () => lens.value = null,
          ),
          for (final (i, m) in roster.indexed)
            Padding(
              padding: const EdgeInsets.only(left: 8),
              child: _LensChip(
                label: m.displayName,
                selected: lens.value == m.id,
                avatar: EaterAvatar(member: m, color: memberColor(i)),
                onTap: () => lens.value = m.id,
              ),
            ),
        ],
      ),
    );
  }
}

class _LensChip extends StatelessWidget {
  const _LensChip({
    required this.label,
    required this.selected,
    required this.onTap,
    this.avatar,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;
  final Widget? avatar;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Container(
        padding: EdgeInsets.fromLTRB(avatar == null ? 12 : 5, 5, 12, 5),
        decoration: BoxDecoration(
          color: selected ? AnsiColors.herbSoft : AnsiColors.surface,
          border: Border.all(
            color: selected ? AnsiColors.herb : AnsiColors.line,
          ),
          borderRadius: BorderRadius.circular(999),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (avatar != null) ...[avatar!, const SizedBox(width: 6)],
            Text(
              label,
              style: ansiSans(
                size: 13,
                color: selected ? AnsiColors.ink : AnsiColors.muted,
                weight: selected ? FontWeight.w600 : FontWeight.w400,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// One day of the week as a card: its name and date, its meals grouped by
/// slot, and — in presentation the day's macro line, in edit the dashed
/// add-meal door (D1's density switch).
class _DayCard extends ConsumerWidget {
  const _DayCard({
    required this.weekStart,
    required this.dayOfWeek,
    required this.entries,
    required this.roster,
    required this.lens,
    required this.scope,
    required this.mode,
    required this.cookPlan,
    required this.todayDayOfWeek,
  });

  final DateTime weekStart;
  final int dayOfWeek;
  final List<PlanEntry> entries;
  final List<Member> roster;
  final String? lens;
  final String scope;
  final WeekMode mode;
  final CookPlan? cookPlan;
  final int? todayDayOfWeek;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // D8: the lens DIMS, it does not remove. Every meal on the day still
    // renders, so a day the other person cooks for themselves is not
    // mistaken for an empty one.
    final visible = entries;

    // entriesForDay is already slot-ordered, so same-slot entries are
    // contiguous — group consecutive runs under one slot label.
    final groups = <List<PlanEntry>>[];
    for (final e in visible) {
      if (groups.isNotEmpty &&
          groups.last.first.mealSlot.toLowerCase() ==
              e.mealSlot.toLowerCase()) {
        groups.last.add(e);
      } else {
        groups.add([e]);
      }
    }

    final isToday = todayDayOfWeek == dayOfWeek;
    return Stack(
      children: [
        Container(
          margin: const EdgeInsets.fromLTRB(16, 12, 16, 0),
          decoration: BoxDecoration(
            color: AnsiColors.paper,
            border: Border.all(color: AnsiColors.line),
            borderRadius: BorderRadius.circular(16),
          ),
          child: _body(context, ref, groups, visible, isToday),
        ),
        // The herb left rule pins today (D2). It is PAINTED over the card's
        // edge rather than being a thicker left border, because a rounded box
        // may not have per-side colours.
        if (isToday)
          Positioned(
            left: 16,
            top: 24,
            bottom: 12,
            child: Container(
              width: 3,
              decoration: const BoxDecoration(
                color: AnsiColors.herb,
                borderRadius: BorderRadius.horizontal(left: Radius.circular(2)),
              ),
            ),
          ),
      ],
    );
  }

  Widget _body(
    BuildContext context,
    WidgetRef ref,
    List<List<PlanEntry>> groups,
    List<PlanEntry> visible,
    bool isToday,
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 10),
          child: Row(
            children: [
              Text(kWeekdayFull[dayOfWeek], style: ansiSerif(size: 17)),
              const SizedBox(width: 8),
              // The date is load-bearing once weeks vary (D6).
              Text(
                formatDayDate(weekStart, dayOfWeek),
                style: ansiMono(size: 11, color: AnsiColors.muted),
              ),
              const Spacer(),
              if (isToday)
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 7,
                    vertical: 2,
                  ),
                  decoration: BoxDecoration(
                    color: AnsiColors.herbSoft,
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Text(
                    'TODAY',
                    style: ansiMono(
                      size: 9,
                      color: AnsiColors.herbDeep,
                      letterSpacing: 1,
                    ),
                  ),
                ),
            ],
          ),
        ),
        for (final group in groups)
          _SlotGroup(
            group: group,
            roster: roster,
            lens: lens,
            mode: mode,
            cookPlan: cookPlan,
            todayDayOfWeek: todayDayOfWeek,
          ),
        if (mode == WeekMode.edit)
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 4, 12, 12),
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () => _addMealFlow(
                context,
                weekStart: weekStart,
                dayOfWeek: dayOfWeek,
              ),
              child: DashedBorderBox(
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Icon(
                      FLucideIcons.plus,
                      size: 12,
                      color: AnsiColors.herb,
                    ),
                    const SizedBox(width: 5),
                    Text(
                      'Add a meal',
                      textAlign: TextAlign.center,
                      style: ansiMono(
                        size: 11,
                        color: AnsiColors.herb,
                        letterSpacing: 0.5,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          )
        else if (visible.isEmpty)
          // Presentation mode, nothing on this day: a quiet line where the
          // content would be, which is ITSELF the add door — so the first
          // meal lands on the day you pointed at (D5b).
          NothingPlannedLine(
            onTap: () => _addMealFlow(
              context,
              weekStart: weekStart,
              dayOfWeek: dayOfWeek,
            ),
          )
        else
          // The day's own honest total, with its denominator (D4).
          DayMacroLine(
            macros: ref.watch(dayMacrosProvider(dayOfWeek, lens)),
            scope: scope,
          ),
      ],
    );
  }
}

/// One meal slot within a day: the slot label once on the left, its dish(es)
/// stacked on the right.
class _SlotGroup extends StatelessWidget {
  const _SlotGroup({
    required this.group,
    required this.roster,
    required this.lens,
    required this.mode,
    required this.cookPlan,
    required this.todayDayOfWeek,
  });

  final List<PlanEntry> group;
  final List<Member> roster;
  final String? lens;
  final WeekMode mode;
  final CookPlan? cookPlan;
  final int? todayDayOfWeek;

  @override
  Widget build(BuildContext context) {
    // The board's week frame: the slot label sits in a left gutter ON THE
    // SAME LINE as the dish name (vertically centred with the row), never
    // floating above it — a multi-dish slot centres the label beside the
    // stack, exactly like the frame's split rows.
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 4, 12, 4),
      decoration: const BoxDecoration(
        border: Border(top: BorderSide(color: AnsiColors.line)),
      ),
      child: Row(
        children: [
          SizedBox(
            width: 62,
            child: Text(
              group.first.mealSlot.toUpperCase(),
              style: ansiMono(
                size: 10,
                color: AnsiColors.muted,
                letterSpacing: 0.5,
              ),
            ),
          ),
          Expanded(
            child: Column(
              children: [
                for (final e in group)
                  _DishRow(
                    entry: e,
                    roster: roster,
                    // D8: a meal this person is not eating is dimmed, not gone.
                    dimmed: lens != null && !e.eaterIds.contains(lens),
                    mode: mode,
                    cookPlan: cookPlan,
                    todayDayOfWeek: todayDayOfWeek,
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// A single dish within a slot.
///
/// Two lines, not one column of cells (D6, owner-ruled): the title with its
/// eaters (and a portions chip when the override differs) on the first, the
/// cook marker on the second — absent entirely for a single-meal cook, which
/// collapses the row back to one line.
///
/// The tap is the mode's whole justification (D7): presentation opens the
/// recipe, edit opens the entry sheet.
class _DishRow extends StatelessWidget {
  const _DishRow({
    required this.entry,
    required this.roster,
    required this.dimmed,
    required this.mode,
    required this.cookPlan,
    required this.todayDayOfWeek,
  });

  final PlanEntry entry;
  final List<Member> roster;
  final bool dimmed;
  final WeekMode mode;
  final CookPlan? cookPlan;
  final int? todayDayOfWeek;

  @override
  Widget build(BuildContext context) {
    final deleted = entry.recipeTitle == null;
    final editing = mode == WeekMode.edit;
    final plan = cookPlan;
    final marker = (editing || plan == null)
        ? null
        : cookMarkerFor(
            plan,
            recipeId: entry.recipeId,
            dayOfWeek: entry.dayOfWeek,
            mealSlot: entry.mealSlot,
          );
    final showPortions = entry.portionsOrDefault != entry.eaterIds.length;

    void onTap() {
      if (editing) {
        showEntrySheet(context, entry: entry);
      } else {
        // A deleted recipe has no page to open, so the row stays inert.
        context.pushOnce('/recipes/${entry.recipeId}');
      }
    }

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: (deleted && !editing) ? null : onTap,
      child: Opacity(
        opacity: dimmed ? 0.38 : 1,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      entry.recipeTitle ?? '(deleted recipe)',
                      style: deleted
                          ? ansiSans(size: 15, color: AnsiColors.muted)
                          : ansiSans(
                              size: 15,
                              color: AnsiColors.herbDeep,
                              weight: FontWeight.w600,
                            ),
                    ),
                  ),
                  if (showPortions) ...[
                    const SizedBox(width: 8),
                    PortionsChip(portions: entry.portionsOrDefault),
                  ],
                  const SizedBox(width: 8),
                  EaterAvatarStack(
                    roster: roster,
                    eaterIds: entry.eaterIds.toSet(),
                  ),
                  if (editing) ...[
                    const SizedBox(width: 6),
                    const Icon(
                      FLucideIcons.chevronRight,
                      size: 15,
                      color: AnsiColors.muted,
                    ),
                  ],
                ],
              ),
              if (marker != null)
                Padding(
                  padding: const EdgeInsets.only(top: 3),
                  child: CookMarkerLine(
                    marker: marker,
                    todayDayOfWeek: todayDayOfWeek,
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// The quiet line a day with no meals shows in presentation mode — and the
/// door that fills it. See D5b: every empty region carries the affordance
/// that would fill it, and the first tap lands where the user pointed.
class NothingPlannedLine extends StatelessWidget {
  const NothingPlannedLine({required this.onTap, super.key});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.fromLTRB(16, 10, 16, 14),
        decoration: const BoxDecoration(
          border: Border(top: BorderSide(color: AnsiColors.line)),
        ),
        child: Row(
          children: [
            const Icon(FLucideIcons.plus, size: 11, color: AnsiColors.muted),
            const SizedBox(width: 6),
            Text(
              'nothing planned',
              style: ansiMono(size: 11, color: AnsiColors.muted),
            ),
          ],
        ),
      ),
    );
  }
}

/// The empty week's one obvious door, at the top of the list.
///
/// Seven identical quiet lines have no focal point, so the primary lives here;
/// each day's own `nothing planned` line is still its add door, which is what
/// makes the first meal land on the day you MEANT (the old CTA always added to
/// Monday, `dayOfWeek: 0`).
///
/// `copy last week` sits beside it only while the week has zero entries. Its
/// permanent home is the switcher menu (D2).
class _FirstMealBar extends StatelessWidget {
  const _FirstMealBar({
    required this.weekStart,
    required this.hasLastWeek,
    required this.onCopyLastWeek,
  });

  final DateTime weekStart;
  final bool hasLastWeek;
  final VoidCallback onCopyLastWeek;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          FButton(
            prefix: const Icon(FLucideIcons.plus),
            onPress: () =>
                _addMealFlow(context, weekStart: weekStart, dayOfWeek: 0),
            child: const Text('Add the first meal'),
          ),
          if (hasLastWeek)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Align(
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: onCopyLastWeek,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 7,
                    ),
                    decoration: BoxDecoration(
                      color: AnsiColors.herbSoft,
                      borderRadius: BorderRadius.circular(999),
                    ),
                    child: Text(
                      'copy last week',
                      style: ansiMono(size: 11, color: AnsiColors.herbDeep),
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
