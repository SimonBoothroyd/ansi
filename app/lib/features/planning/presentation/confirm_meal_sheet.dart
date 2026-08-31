/// Step 3 of the add-a-meal flow: confirm the slot, who's eating, and how many
/// portions, then place the meal on the week.
///
/// v2 (step 7.7, design board "Confirm & place v2"): one combined
/// "Day · Slot" dropdown (the day can still change here), the picked card
/// carries the honest per-serving macro line, and the batch cue is the full
/// prose ("Chicken Curry already cooks Monday and keeps 4 days — …") instead
/// of a truncated one-liner.
///
/// Portions default to the eater count and can be bumped for big appetites
/// (spec §8); a null override means "track |eaters|". The sheet does the
/// write itself and pops.
library;

import 'package:flutter/widgets.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:forui/forui.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

import '../../../core/theme/mise_theme.dart';
import '../../../core/theme/mise_tokens.dart';
import '../../../shared/incomplete_macros.dart';
import '../../books/presentation/text_prompt.dart';
import '../../cook_plan/domain/cook_plan.dart';
import '../../recipes/domain/recipe.dart';
import '../../recipes/presentation/format.dart';
import '../data/planning_providers.dart';
import '../domain/planning.dart';
import 'week_format.dart';
import 'week_view_models.dart';
import 'week_widgets.dart';

/// Opens the confirm sheet for [recipe] on [dayOfWeek], pre-selecting [slot].
Future<void> showConfirmMealSheet(
  BuildContext context, {
  required DateTime weekStart,
  required int dayOfWeek,
  required String slot,
  required RecipeSummary recipe,
}) {
  return showFSheet<void>(
    context: context,
    side: FLayout.btt,
    mainAxisMaxRatio: null,
    useSafeArea: true,
    builder: (_) => _ConfirmMealSheet(
      weekStart: weekStart,
      dayOfWeek: dayOfWeek,
      slot: slot,
      recipe: recipe,
    ),
  );
}

class _ConfirmMealSheet extends HookConsumerWidget {
  const _ConfirmMealSheet({
    required this.weekStart,
    required this.dayOfWeek,
    required this.slot,
    required this.recipe,
  });

  final DateTime weekStart;
  final int dayOfWeek;
  final String slot;
  final RecipeSummary recipe;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final dayState = useState(dayOfWeek);
    final slotState = useState(slot);
    final eaters = useState<Set<String>>({});
    // Null = track the eater count; a number is an explicit override (spec §8).
    final portionsOverride = useState<int?>(null);

    final members = ref.watch(membersProvider);

    // Days this recipe is already planned this week → the batch cue, live
    // against the currently selected day.
    final plannedDays = ref
        .watch(currentWeekProvider)
        .asData
        ?.value
        ?.entries
        .where((e) => e.recipeId == recipe.id)
        .map((e) => e.dayOfWeek)
        .toList();
    final hint = batchHintFor(
      plannedDays: plannedDays ?? const [],
      newDay: dayState.value,
      keepsForDays: recipe.keepsForDays,
      freezable: recipe.freezable,
      freezerDays: recipe.freezerDays,
    );

    useEffect(() {
      members.whenData((list) {
        if (eaters.value.isEmpty) {
          eaters.value = {for (final m in list) m.id};
        }
      });
      return null;
    }, [members]);

    final portions = portionsOverride.value ?? eaters.value.length;

    Future<void> add() async {
      await ref
          .read(planningRepositoryProvider)
          .addEntry(
            weekStart: weekStart,
            dayOfWeek: dayState.value,
            mealSlot: slotState.value,
            recipeId: recipe.id,
            eaterIds: eaters.value.toList(),
            portions: portionsOverride.value,
          );
      if (context.mounted) Navigator.of(context).pop();
    }

    return Container(
      decoration: const BoxDecoration(
        color: MiseColors.paper,
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        border: Border(top: BorderSide(color: MiseColors.line)),
      ),
      child: Padding(
        padding: EdgeInsets.only(
          left: 20,
          right: 20,
          top: 16,
          bottom: MediaQuery.viewInsetsOf(context).bottom + 16,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('Add to plan', style: miseSerif(size: 22)),
            const SizedBox(height: 14),
            _RecipeCard(recipe: recipe),
            if (hint != null) ...[
              const SizedBox(height: 10),
              _BatchProseBanner(
                hint: hint,
                recipe: recipe,
                newDay: dayState.value,
              ),
            ],
            const SizedBox(height: 18),
            const _Label('Slot'),
            const SizedBox(height: 6),
            _DaySlotPicker(
              day: dayState.value,
              slot: slotState.value,
              onChanged: (day, s) {
                dayState.value = day;
                slotState.value = s;
              },
            ),
            const SizedBox(height: 18),
            const _Label("Who's eating"),
            const SizedBox(height: 6),
            members.when(
              loading: () => const SizedBox.shrink(),
              error: (_, __) => const SizedBox.shrink(),
              data: (list) => _EaterPicker(
                members: list,
                selected: eaters.value,
                onToggle: (id) {
                  final next = {...eaters.value};
                  next.contains(id) ? next.remove(id) : next.add(id);
                  eaters.value = next;
                },
              ),
            ),
            const SizedBox(height: 18),
            const _Label('Portions'),
            const SizedBox(height: 6),
            _PortionsStepper(
              value: portions,
              tracksEaters: portionsOverride.value == null,
              onChanged: (v) => portionsOverride.value = v < 1 ? 1 : v,
            ),
            const SizedBox(height: 20),
            FButton(
              onPress: add,
              child: Text('Add to ${kWeekdayFull[dayState.value]}'),
            ),
          ],
        ),
      ),
    );
  }
}

class _Label extends StatelessWidget {
  const _Label(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => Text(
    text.toUpperCase(),
    style: miseMono(size: 10, color: MiseColors.muted, letterSpacing: 1),
  );
}

class _RecipeCard extends StatelessWidget {
  const _RecipeCard({required this.recipe});

  final RecipeSummary recipe;

  @override
  Widget build(BuildContext context) {
    final keeps = recipe.keepsForDays;
    final shelf = <String>[
      if (keeps != null) 'keeps $keeps d',
      if (recipe.freezable) 'freezable',
    ].join(' · ');
    final summary = recipe.macros;
    final perServing = summary?.perServing;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: MiseColors.surface,
        border: Border.all(color: MiseColors.line),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: MiseColors.herbSoft,
              borderRadius: BorderRadius.circular(10),
            ),
            child: const Icon(
              FLucideIcons.cookingPot,
              size: 20,
              color: MiseColors.herb,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  recipe.title.isEmpty ? 'Untitled recipe' : recipe.title,
                  style: miseSerif(size: 17),
                ),
                if (shelf.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: Text(
                      shelf,
                      style: miseMono(size: 10, color: MiseColors.muted),
                    ),
                  ),
                // The honest per-serving line (v2): real numbers or the
                // incomplete badge — never zeros (invariant 3).
                if (perServing != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 3),
                    child: Text.rich(
                      TextSpan(
                        text:
                            'serves ${formatQuantity(recipe.servingsBase)} · '
                            '~${perServing.kcal.round()} kcal · '
                            '${perServing.protein.round()}P',
                        style: miseMono(size: 10, color: MiseColors.herbDeep),
                        children: [
                          TextSpan(
                            text: ' /serving',
                            style: miseMono(size: 10, color: MiseColors.muted),
                          ),
                        ],
                      ),
                    ),
                  )
                else if (summary != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 3),
                    child: Row(
                      children: [
                        const IncompleteBadge(),
                        Text(
                          ' ${incompleteNote(summary)}',
                          style: miseMono(size: 10, color: MiseColors.muted),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// The batch-awareness cue, in full prose (v2 — the app used to truncate
/// this to a one-liner): names the dish, the day it already cooks, the
/// shelf-life window that makes it one batch, and the freezer hop when
/// that's how the meal is reached.
class _BatchProseBanner extends StatelessWidget {
  const _BatchProseBanner({
    required this.hint,
    required this.recipe,
    required this.newDay,
  });

  final BatchHint hint;
  final RecipeSummary recipe;
  final int newDay;

  @override
  Widget build(BuildContext context) {
    final title = recipe.title.isEmpty ? 'This dish' : recipe.title;
    final day = kWeekdayFull[hint.withDay];
    final target = kWeekdayFull[newDay];
    final keeps = recipe.keepsForDays;
    final text = hint.frozen
        ? '$title already cooks $day; $target is past the fridge window'
              '${keeps != null ? ' ($keeps days)' : ''}, but it freezes — '
              'a share goes to the freezer, so it still joins $day’s batch '
              'instead of a second cook.'
        : hint.withDay == newDay
        ? '$title already cooks $target — this meal joins that batch '
              'instead of a second cook.'
        : '$title already cooks $day'
              '${keeps != null ? ' and keeps $keeps days' : ''} — $target is '
              'inside that window, so this joins $day’s batch instead of a '
              'second cook.';
    return Container(
      padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
      decoration: BoxDecoration(
        color: MiseColors.herbSoft,
        border: Border.all(color: MiseColors.line),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 1),
            child: Icon(
              hint.frozen ? FLucideIcons.snowflake : FLucideIcons.repeat,
              size: 14,
              color: MiseColors.herbDeep,
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              text,
              style: miseSans(size: 12, color: MiseColors.herbDeep),
            ),
          ),
        ],
      ),
    );
  }
}

/// The combined "Day · Slot" dropdown (v2): one control carrying the pair,
/// so a meal can still land on a different day from the confirm sheet. A
/// non-default slot (a custom "Brunch") joins the menu for every day; the
/// trailing + prompts a new custom slot, keeping the selected day.
class _DaySlotPicker extends StatelessWidget {
  const _DaySlotPicker({
    required this.day,
    required this.slot,
    required this.onChanged,
  });

  final int day;
  final String slot;
  final void Function(int day, String slot) onChanged;

  @override
  Widget build(BuildContext context) {
    final slots = [
      ...kDefaultMealSlots,
      if (!kDefaultMealSlots.contains(slot)) slot,
    ];
    return Row(
      children: [
        Expanded(
          child: FSelect<(int, String)>.rich(
            format: (v) => '${kWeekdayFull[v.$1]} · ${v.$2}',
            control: FSelectControl<(int, String)>.lifted(
              value: (day, slot),
              onChange: (v) {
                if (v != null) onChanged(v.$1, v.$2);
              },
            ),
            children: [
              for (var d = 0; d < 7; d++)
                for (final s in slots)
                  FSelectItem(
                    title: Text('${kWeekdayFull[d]} · $s'),
                    value: (d, s),
                  ),
            ],
          ),
        ),
        const SizedBox(width: 8),
        FButton.icon(
          variant: FButtonVariant.secondary,
          onPress: () async {
            final custom = await promptForText(
              context,
              title: 'Custom meal',
              hint: 'e.g. Brunch, Snack',
              confirm: 'Use',
            );
            if (custom != null && custom.trim().isNotEmpty) {
              onChanged(day, custom.trim());
            }
          },
          child: const Icon(FLucideIcons.plus),
        ),
      ],
    );
  }
}

class _EaterPicker extends StatelessWidget {
  const _EaterPicker({
    required this.members,
    required this.selected,
    required this.onToggle,
  });

  final List<Member> members;
  final Set<String> selected;
  final ValueChanged<String> onToggle;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        for (final (i, m) in members.indexed)
          Padding(
            padding: const EdgeInsets.only(right: 12),
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () => onToggle(m.id),
              child: Row(
                children: [
                  EaterAvatar(
                    member: m,
                    color: memberColor(i),
                    dimmed: !selected.contains(m.id),
                  ),
                  const SizedBox(width: 6),
                  Text(
                    m.displayName,
                    style: miseSans(
                      size: 13,
                      color: selected.contains(m.id)
                          ? MiseColors.ink
                          : MiseColors.muted,
                    ),
                  ),
                ],
              ),
            ),
          ),
      ],
    );
  }
}

class _PortionsStepper extends StatelessWidget {
  const _PortionsStepper({
    required this.value,
    required this.tracksEaters,
    required this.onChanged,
  });

  final int value;
  final bool tracksEaters;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '$value ${value == 1 ? 'portion' : 'portions'}',
                style: miseSans(size: 15, weight: FontWeight.w600),
              ),
              const SizedBox(height: 2),
              Text(
                tracksEaters
                    ? 'defaults to eaters — bump up for big appetites'
                    : 'manual override',
                style: miseMono(size: 10, color: MiseColors.muted),
              ),
            ],
          ),
        ),
        _StepButton(
          icon: FLucideIcons.minus,
          onTap: () => onChanged(value - 1),
        ),
        SizedBox(
          width: 40,
          child: Text(
            '$value',
            textAlign: TextAlign.center,
            style: miseMono(size: 16, weight: FontWeight.w600),
          ),
        ),
        _StepButton(icon: FLucideIcons.plus, onTap: () => onChanged(value + 1)),
      ],
    );
  }
}

class _StepButton extends StatelessWidget {
  const _StepButton({required this.icon, required this.onTap});

  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Container(
        width: 40,
        height: 40,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: MiseColors.surface,
          border: Border.all(color: MiseColors.line),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Icon(icon, size: 16, color: MiseColors.herb),
      ),
    );
  }
}
