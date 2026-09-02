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
/// The week itself is a position, not a singleton — see `week_header.dart`
/// (D2) and `week_view_models.dart` (D3).
library;

import 'package:flutter/widgets.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:forui/forui.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

import '../../../core/theme/ansi_theme.dart';
import '../../../core/theme/ansi_tokens.dart';
import '../../../shared/dashed_border_box.dart';
import '../../../shared/guarded_navigation.dart';
import '../../cook_plan/domain/cook_plan.dart';
import '../../cook_plan/presentation/cook_view_models.dart';
import '../data/planning_providers.dart';
import '../domain/planning.dart';
import 'confirm_meal_sheet.dart';
import 'entry_sheet.dart';
import 'recipe_picker_sheet.dart';
import 'week_format.dart';
import 'week_header.dart';
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
    final roster = ref.watch(membersProvider).asData?.value ?? const <Member>[];
    final lastWeek = ref.watch(lastWeekProvider).asData?.value;
    final repo = ref.read(planningRepositoryProvider);

    // The cook markers are a READ of the derivation the Cook tab draws, for
    // this same week (D6). Null while it loads — a row simply has no second
    // line until it arrives.
    final cookPlan = ref.watch(currentCookPlanProvider).asData?.value;

    // "cooks today" is only true of the week containing today.
    final isThisWeek = weekStart == ref.watch(currentWeekStartProvider);
    final todayDayOfWeek = isThisWeek ? DateTime.now().weekday - 1 : null;

    // null = Shared; a member id = the Per-person lens on that eater.
    final lens = useState<String?>(null);
    final mode = useState(WeekMode.presentation);

    return FScaffold(
      // "Copy last week" used to live in a header `⋯`, a lens-bar chip AND the
      // empty-state button. It now has ONE permanent home — the switcher menu
      // (D2) — plus the empty-week chip below.
      header: FHeader.nested(
        title: const WeekSwitcher(),
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
        error: (e, _) {
          debugPrint('week load failed: $e');
          return Center(
            child: Text(
              'Could not load the week.',
              textAlign: TextAlign.center,
              style: ansiMono(size: 13, color: AnsiColors.muted),
            ),
          );
        },
        data: (plan) => (plan == null || plan.entries.isEmpty)
            ? _EmptyWeek(weekStart: weekStart)
            : ListView(
                padding: const EdgeInsets.only(top: 8, bottom: 24),
                children: [
                  const ViewedWeekBanner(),
                  _LensBar(
                    lens: lens,
                    roster: roster,
                    hasLastWeek: lastWeek != null,
                    onCopyLastWeek: () => repo.copyLastWeek(weekStart),
                  ),
                  for (var d = 0; d < 7; d++)
                    _DayCard(
                      weekStart: weekStart,
                      dayOfWeek: d,
                      entries: plan.entriesForDay(d),
                      roster: roster,
                      lens: lens.value,
                      mode: mode.value,
                      cookPlan: cookPlan,
                      todayDayOfWeek: todayDayOfWeek,
                    ),
                ],
              ),
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

/// The Shared/Per-person toggle, the "copy last week" chip, and (in per-person
/// mode) the eater selector.
class _LensBar extends StatelessWidget {
  const _LensBar({
    required this.lens,
    required this.roster,
    required this.hasLastWeek,
    required this.onCopyLastWeek,
  });

  final ValueNotifier<String?> lens;
  final List<Member> roster;
  final bool hasLastWeek;
  final VoidCallback onCopyLastWeek;

  @override
  Widget build(BuildContext context) {
    final perPerson = lens.value != null;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              _SegToggle(
                perPerson: perPerson,
                onShared: () => lens.value = null,
                onPerPerson: () =>
                    lens.value = roster.isEmpty ? null : roster.first.id,
              ),
              const Spacer(),
              if (hasLastWeek)
                GestureDetector(
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
            ],
          ),
          if (perPerson) ...[
            const SizedBox(height: 10),
            Row(
              children: [
                for (final (i, m) in roster.indexed)
                  Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onTap: () => lens.value = m.id,
                      child: Container(
                        padding: const EdgeInsets.fromLTRB(6, 5, 12, 5),
                        decoration: BoxDecoration(
                          color: lens.value == m.id
                              ? AnsiColors.herbSoft
                              : AnsiColors.surface,
                          border: Border.all(
                            color: lens.value == m.id
                                ? AnsiColors.herb
                                : AnsiColors.line,
                          ),
                          borderRadius: BorderRadius.circular(999),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            EaterAvatar(member: m, color: memberColor(i)),
                            const SizedBox(width: 6),
                            Text(m.displayName, style: ansiSans(size: 13)),
                          ],
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

class _SegToggle extends StatelessWidget {
  const _SegToggle({
    required this.perPerson,
    required this.onShared,
    required this.onPerPerson,
  });

  final bool perPerson;
  final VoidCallback onShared;
  final VoidCallback onPerPerson;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        color: AnsiColors.paper,
        border: Border.all(color: AnsiColors.line),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _seg('Shared', !perPerson, onShared),
          _seg('Per-person', perPerson, onPerPerson),
        ],
      ),
    );
  }

  Widget _seg(String label, bool selected, VoidCallback onTap) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
        decoration: BoxDecoration(
          color: selected ? AnsiColors.surface : AnsiColors.paper,
          borderRadius: BorderRadius.circular(999),
        ),
        child: Text(
          label,
          style: ansiSans(
            size: 13,
            color: selected ? AnsiColors.ink : AnsiColors.muted,
            weight: selected ? FontWeight.w600 : FontWeight.w400,
          ),
        ),
      ),
    );
  }
}

/// One day of the week as a card: its name and date, its meals grouped by
/// slot, and — in edit mode — the dashed add-meal door.
class _DayCard extends StatelessWidget {
  const _DayCard({
    required this.weekStart,
    required this.dayOfWeek,
    required this.entries,
    required this.roster,
    required this.lens,
    required this.mode,
    required this.cookPlan,
    required this.todayDayOfWeek,
  });

  final DateTime weekStart;
  final int dayOfWeek;
  final List<PlanEntry> entries;
  final List<Member> roster;
  final String? lens;
  final WeekMode mode;
  final CookPlan? cookPlan;
  final int? todayDayOfWeek;

  @override
  Widget build(BuildContext context) {
    // Per-person lens: keep only entries the selected eater is part of.
    final visible = lens == null
        ? entries
        : entries.where((e) => e.eaterIds.contains(lens)).toList();

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
          child: _body(context, groups, visible, isToday),
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
    required this.mode,
    required this.cookPlan,
    required this.todayDayOfWeek,
  });

  final PlanEntry entry;
  final List<Member> roster;
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

/// The blank-week state: a CTA to plan the first meal or copy last week, with a
/// small reference list of last week's meals (design board "New week").
class _EmptyWeek extends ConsumerWidget {
  const _EmptyWeek({required this.weekStart});

  final DateTime weekStart;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final repo = ref.read(planningRepositoryProvider);
    final lastWeek = ref.watch(lastWeekProvider);

    return ListView(
      padding: const EdgeInsets.fromLTRB(24, 40, 24, 32),
      children: [
        const Icon(FLucideIcons.calendarDays, size: 44, color: AnsiColors.herb),
        const SizedBox(height: 14),
        Text(
          'A blank week',
          textAlign: TextAlign.center,
          style: ansiSerif(size: 24),
        ),
        const SizedBox(height: 8),
        Text(
          'Add what you feel like eating — Ansi works out the cooking and '
          'shopping.',
          textAlign: TextAlign.center,
          style: ansiMono(size: 12, color: AnsiColors.muted),
        ),
        const SizedBox(height: 22),
        FButton(
          onPress: () =>
              _addMealFlow(context, weekStart: weekStart, dayOfWeek: 0),
          child: const Text('Plan a meal'),
        ),
        const SizedBox(height: 10),
        lastWeek.when(
          loading: () => const SizedBox.shrink(),
          error: (_, _) => const SizedBox.shrink(),
          data: (last) => last == null
              ? const SizedBox.shrink()
              : Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    FButton(
                      variant: FButtonVariant.outline,
                      onPress: () => repo.copyLastWeek(weekStart),
                      child: const Text('Copy last week'),
                    ),
                    const SizedBox(height: 26),
                    _LastWeekReference(week: last),
                  ],
                ),
        ),
      ],
    );
  }
}

class _LastWeekReference extends StatelessWidget {
  const _LastWeekReference({required this.week});

  final WeekPlan week;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'Last week, for reference',
          style: ansiMono(size: 10, color: AnsiColors.muted, letterSpacing: 1),
        ),
        const SizedBox(height: 8),
        for (final e in week.entries)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 5),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    '${kWeekdayShort[e.dayOfWeek]} · '
                    '${e.recipeTitle ?? '(deleted recipe)'}',
                    style: ansiMono(size: 12),
                  ),
                ),
                Text(
                  '${e.portionsOrDefault}',
                  style: ansiMono(size: 12, color: AnsiColors.muted),
                ),
              ],
            ),
          ),
      ],
    );
  }
}
