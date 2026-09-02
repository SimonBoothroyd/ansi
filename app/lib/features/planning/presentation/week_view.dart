/// The Week — the meal-planning input screen. A single active week (the one
/// containing today, Monday-first) as a seven-day grid of day cards; under each
/// day you add meals (recipe · slot · eaters · portions). A Shared/Per-person
/// lens filters the week to one eater. An empty week offers "copy last week".
///
/// This is the INPUT to the derived cook-plan / shopping pipeline (steps 5–6) —
/// no batch or leftover thinking here (design board: "plan the week you want to
/// eat"). Planned weeks sync to the household like everything else (step 7).
library;

import 'package:flutter/widgets.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:forui/forui.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

import '../../../core/theme/ansi_theme.dart';
import '../../../core/theme/ansi_tokens.dart';
import '../../../shared/ansi_bottom_nav.dart';
import '../../../shared/dashed_border_box.dart';
import '../../../shared/guarded_navigation.dart';
import '../data/planning_providers.dart';
import '../domain/planning.dart';
import 'confirm_meal_sheet.dart';
import 'edit_eaters_dialog.dart';
import 'recipe_picker_sheet.dart';
import 'week_format.dart';
import 'week_view_models.dart';
import 'week_widgets.dart';

const _kDefaultSlot = 'Dinner';

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
    final weekStart = ref.watch(currentWeekStartProvider);
    final week = ref.watch(currentWeekProvider);
    final roster = ref.watch(membersProvider).asData?.value ?? const <Member>[];
    final lastWeek = ref.watch(lastWeekProvider).asData?.value;
    final repo = ref.read(planningRepositoryProvider);

    // null = Shared; a member id = the Per-person lens on that eater.
    final lens = useState<String?>(null);

    return FScaffold(
      footer: const AnsiBottomNav(current: AnsiTab.week),
      header: FHeader.nested(
        title: Text(formatWeekOf(weekStart), style: ansiHeaderTitle()),
        suffixes: [
          if (lastWeek != null)
            FPopoverMenu(
              menu: [
                FItemGroup(
                  children: [
                    FItem(
                      prefix: const Icon(FLucideIcons.copy),
                      title: const Text('Copy last week'),
                      onPress: () => repo.copyLastWeek(weekStart),
                    ),
                  ],
                ),
              ],
              builder: (context, controller, _) => FHeaderAction(
                icon: const Icon(FLucideIcons.ellipsis),
                onPress: controller.toggle,
              ),
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
                    ),
                ],
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

/// One day of the grid as a card: the day name, its meals grouped by slot, and
/// a dashed add-meal button.
class _DayCard extends StatelessWidget {
  const _DayCard({
    required this.weekStart,
    required this.dayOfWeek,
    required this.entries,
    required this.roster,
    required this.lens,
  });

  final DateTime weekStart;
  final int dayOfWeek;
  final List<PlanEntry> entries;
  final List<Member> roster;
  final String? lens;

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

    return Container(
      margin: const EdgeInsets.fromLTRB(16, 12, 16, 0),
      decoration: BoxDecoration(
        color: AnsiColors.paper,
        border: Border.all(color: AnsiColors.line),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 10),
            child: Text(kWeekdayFull[dayOfWeek], style: ansiSerif(size: 17)),
          ),
          for (final group in groups)
            _SlotGroup(group: group, roster: roster, lens: lens),
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
          ),
        ],
      ),
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
  });

  final List<PlanEntry> group;
  final List<Member> roster;
  final String? lens;

  @override
  Widget build(BuildContext context) {
    // The board's week frame: the slot label sits in a left gutter ON THE
    // SAME LINE as the dish name (vertically centred with the row), never
    // floating above it — a multi-dish slot centres the label beside the
    // stack, exactly like the frame's split rows.
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 4, 8, 4),
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
                  _DishRow(entry: e, roster: roster, lens: lens),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// A single dish within a slot: name · eaters (or a "shared" tag in the
/// per-person lens) · a menu to edit eaters or remove it.
class _DishRow extends ConsumerWidget {
  const _DishRow({
    required this.entry,
    required this.roster,
    required this.lens,
  });

  final PlanEntry entry;
  final List<Member> roster;
  final String? lens;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        children: [
          Expanded(
            // The dish name is the way into its recipe from the plan; the `⋯`
            // menu beside it keeps its own hit box. A deleted recipe has no
            // page to open, so it stays inert.
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: entry.recipeTitle == null
                  ? null
                  : () => context.pushOnce('/recipes/${entry.recipeId}'),
              child: Text(
                entry.recipeTitle ?? '(deleted recipe)',
                style: entry.recipeTitle == null
                    ? ansiSans(size: 15, color: AnsiColors.muted)
                    : ansiSans(
                        size: 15,
                        color: AnsiColors.herbDeep,
                        weight: FontWeight.w600,
                      ),
              ),
            ),
          ),
          const SizedBox(width: 8),
          if (lens == null)
            EaterAvatarStack(roster: roster, eaterIds: entry.eaterIds.toSet())
          else if (entry.eaterIds.length > 1)
            _SharedTag(),
          _DishMenu(entry: entry),
        ],
      ),
    );
  }
}

class _SharedTag extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        const Icon(
          FLucideIcons.arrowLeftRight,
          size: 10,
          color: AnsiColors.muted,
        ),
        const SizedBox(width: 4),
        Text('shared', style: ansiMono(size: 10, color: AnsiColors.muted)),
      ],
    );
  }
}

class _DishMenu extends ConsumerWidget {
  const _DishMenu({required this.entry});

  final PlanEntry entry;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final repo = ref.read(planningRepositoryProvider);
    return FPopoverMenu(
      menu: [
        FItemGroup(
          children: [
            FItem(
              prefix: const Icon(FLucideIcons.users),
              title: const Text("Edit who's eating"),
              onPress: () async {
                final members = await ref.read(membersProvider.future);
                if (!context.mounted) return;
                final next = await showEditEatersDialog(
                  context,
                  members: members,
                  selected: entry.eaterIds.toSet(),
                );
                if (next != null) await repo.setEaters(entry.id, next.toList());
              },
            ),
            FItem(
              prefix: const Icon(FLucideIcons.trash2),
              title: const Text('Remove'),
              onPress: () => repo.removeEntry(entry.id),
            ),
          ],
        ),
      ],
      builder: (context, controller, _) => FButton.icon(
        variant: FButtonVariant.ghost,
        onPress: controller.toggle,
        child: const Icon(
          FLucideIcons.ellipsis,
          size: 16,
          color: AnsiColors.muted,
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
          error: (_, __) => const SizedBox.shrink(),
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
