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
///
/// Its controls live in `meal_fields.dart` because a second sheet uses two of
/// them: `meal_editor_sheet.dart` sets who's eating and how many portions on a
/// meal already on the week. Hoisting them is what stops the add path and the
/// edit path drifting apart.
///
/// The `Day · Slot` dropdown is this sheet's alone. The editor holds no day and
/// no slot — a row does not print a day as a value, its *position* is its day —
/// so this is the only place a meal's day is chosen, on the way in.
library;

import 'package:flutter/widgets.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:forui/forui.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

import '../../../core/words.dart';
import '../../../shared/ansi_micro_label.dart';
import '../../../shared/ansi_modals.dart';
import '../../../shared/ansi_sheet_shell.dart';
import '../../../shared/write.dart';
import '../../cook_plan/domain/cook_plan.dart';
import '../../recipes/domain/recipe.dart';
import '../data/planning_providers.dart';
import 'meal_fields.dart';
import 'week_view_models.dart';

/// Opens the confirm sheet for [recipe] on [dayOfWeek], pre-selecting [slot].
Future<void> showConfirmMealSheet(
  BuildContext context, {
  required DateTime weekStart,
  required int dayOfWeek,
  required String slot,
  required RecipeSummary recipe,
}) {
  return showAnsiSheet<void>(
    context: context,
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
        .watch(viewedWeekProvider)
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

    Future<void> add() async {
      // The sheet closes only on a write that landed: a throw must not skip
      // the pop and leave it open and inert, the most confusing possible
      // outcome.
      final added = await ref.write(
        context,
        "add ${kWeekdayFull[dayState.value]}'s meal",
        () => ref
            .read(planningRepositoryProvider)
            .addEntry(
              weekStart: weekStart,
              dayOfWeek: dayState.value,
              mealSlot: slotState.value,
              recipeId: recipe.id,
              eaterIds: eaters.value.toList(),
              portions: portionsOverride.value,
            ),
      );
      if (added != null && context.mounted) Navigator.of(context).pop();
    }

    return AnsiSheetShell(
      title: 'Add to plan',
      titleSize: 22,
      centerTitle: false,
      dismiss: AnsiSheetDismiss.none,
      topPadding: 16,
      children: [
        const SizedBox(height: 14),
        MealRecipeCard(recipe: recipe),
        if (hint != null) ...[
          const SizedBox(height: 10),
          MealBatchBanner(hint: hint, recipe: recipe, newDay: dayState.value),
        ],
        const SizedBox(height: 18),
        const AnsiMicroLabel('Slot'),
        MealDaySlotPicker(
          day: dayState.value,
          slot: slotState.value,
          onChanged: (day, s) {
            dayState.value = day;
            slotState.value = s;
          },
        ),
        const SizedBox(height: 18),
        const AnsiMicroLabel("Who's eating"),
        members.when(
          loading: () => const SizedBox.shrink(),
          error: (_, __) => const SizedBox.shrink(),
          data: (list) => MealEaterPicker(
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
        const AnsiMicroLabel('Portions'),
        MealPortionsStepper(
          portionsOverride: portionsOverride.value,
          eaterIds: eaters.value.toList(),
          roster: members.asData?.value ?? const [],
          onChanged: (v) => portionsOverride.value = v < 1 ? 1 : v,
        ),
        const SizedBox(height: 20),
        FButton(
          onPress: add,
          child: Text('Add to ${kWeekdayFull[dayState.value]}'),
        ),
      ],
    );
  }
}
