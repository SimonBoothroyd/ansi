/// Step 3 of the add-a-meal flow: confirm the slot, who's eating, and how many
/// portions, then place the meal on the week.
///
/// Portions default to the eater count and can be bumped for big appetites
/// (spec §8); a null override means "track |eaters|". The shelf-life batch hint
/// from the mockup is deferred to step 5 (it needs recipe shelf-life data +
/// cook-plan clustering). The sheet does the write itself and pops.
library;

import 'package:flutter/widgets.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:forui/forui.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

import '../../../core/theme/mise_theme.dart';
import '../../../core/theme/mise_tokens.dart';
import '../../books/presentation/text_prompt.dart';
import '../../recipes/domain/recipe.dart';
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
    final slotState = useState(slot);
    final eaters = useState<Set<String>>({});
    // Null = track the eater count; a number is an explicit override (spec §8).
    final portionsOverride = useState<int?>(null);

    final members = ref.watch(membersProvider);

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
            dayOfWeek: dayOfWeek,
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
            _RecipeCard(title: recipe.title),
            const SizedBox(height: 18),
            const _Label('Slot'),
            const SizedBox(height: 6),
            _SlotPicker(
              value: slotState.value,
              onChanged: (s) => slotState.value = s,
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
              child: Text('Add to ${kWeekdayFull[dayOfWeek]}'),
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
  const _RecipeCard({required this.title});

  final String title;

  @override
  Widget build(BuildContext context) {
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
            child: Text(
              title.isEmpty ? 'Untitled recipe' : title,
              style: miseSerif(size: 17),
            ),
          ),
        ],
      ),
    );
  }
}

class _SlotPicker extends StatelessWidget {
  const _SlotPicker({required this.value, required this.onChanged});

  final String value;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    final known = kDefaultMealSlots.contains(value);
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        for (final s in kDefaultMealSlots)
          Pill(label: s, selected: s == value, onTap: () => onChanged(s)),
        if (!known) Pill(label: value, selected: true, onTap: () {}),
        Pill(
          label: '＋',
          selected: false,
          onTap: () async {
            final custom = await promptForText(
              context,
              title: 'Custom meal',
              hint: 'e.g. Brunch, Snack',
              confirm: 'Use',
            );
            if (custom != null && custom.trim().isNotEmpty) {
              onChanged(custom.trim());
            }
          },
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
