/// Step 3 of the add-a-meal flow: confirm the slot, who's eating, and how many
/// portions, then place the meal on the week.
///
/// The picked card carries the honest per-serving macro line, and the batch cue
/// is the full prose ("Chicken Curry already cooks Monday and keeps 4 days —
/// …") rather than a truncated one-liner.
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
/// **The day is not asked here.** Every add starts from a day card, so the day
/// arrived with the flow: it is the sheet's subtitle and the button repeats it
/// ("Add to Wednesday"), and the only question left is the slot, defaulted to
/// Dinner. A wrong day is one back-tap away while the sheet is open, and
/// remove-and-re-add once it is placed — the same way the editor documents.
/// The slot picker is this sheet's alone: the editor holds neither field,
/// because a row does not print a day or a slot as a value, its *position* is
/// both.
///
/// Since step 8.14 it places EITHER kind of meal — a recipe, or a bare
/// ingredient whose amount the quantity sheet already settled ([MealTarget]).
/// The slot, the eaters and the portions stepper are identical for both,
/// because a snack carries eaters and multiplies like any other entry (A-D3);
/// what differs is the card at the top and which repository door the write
/// goes through.
library;

import 'package:flutter/widgets.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:forui/forui.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

import '../../../core/units/measure.dart';
import '../../../core/units/units.dart';
import '../../../core/words.dart';
import '../../../shared/ansi_micro_label.dart';
import '../../../shared/ansi_modals.dart';
import '../../../shared/ansi_sheet_shell.dart';
import '../../../shared/write.dart';
import '../../cook_plan/domain/cook_plan.dart';
import '../../ingredients/domain/ingredient.dart';
import '../../recipes/domain/recipe.dart';
import '../data/planning_providers.dart';
import 'meal_fields.dart';
import 'week_view_models.dart';

/// What this sheet is about to place on the week — the `plan_entry` XOR, at
/// the door that writes it (step 8.14 / B-D1).
sealed class MealTarget {
  const MealTarget();
}

/// A dish. Its amount is its portions; the batch cue applies.
final class RecipeMeal extends MealTarget {
  const RecipeMeal(this.recipe);

  final RecipeSummary recipe;
}

/// A bare ingredient — a protein bar, a yoghurt. Its amount is ONE portion of
/// it, already settled by the shipped quantity sheet (A-D2) and carried here so
/// this sheet only has to ask the questions both kinds share.
final class SnackMeal extends MealTarget {
  const SnackMeal({
    required this.ingredient,
    this.quantity,
    this.unit,
    this.measure,
  });

  final Ingredient ingredient;
  final double? quantity;
  final Unit? unit;
  final Measure? measure;
}

/// Opens the confirm sheet for [target] on [dayOfWeek], pre-selecting [slot].
Future<void> showConfirmMealSheet(
  BuildContext context, {
  required DateTime weekStart,
  required int dayOfWeek,
  required String slot,
  required MealTarget target,
}) {
  return showAnsiSheet<void>(
    context: context,
    builder: (_) => _ConfirmMealSheet(
      weekStart: weekStart,
      dayOfWeek: dayOfWeek,
      slot: slot,
      target: target,
    ),
  );
}

class _ConfirmMealSheet extends HookConsumerWidget {
  const _ConfirmMealSheet({
    required this.weekStart,
    required this.dayOfWeek,
    required this.slot,
    required this.target,
  });

  final DateTime weekStart;
  final int dayOfWeek;
  final String slot;
  final MealTarget target;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final slotState = useState(slot);
    final eaters = useState<Set<String>>({});
    // Null = track the eater count; a number is an explicit override (spec §8).
    final portionsOverride = useState<int?>(null);

    final members = ref.watch(membersProvider);

    // The batch cue is a RECIPE fact — how long a cooked dish keeps, and
    // whether this day could share a batch with another. A snack is not
    // cooked (A-D4), so there is no batch to hint at and the card carries its
    // amount instead: the absence is the ruling, not an oversight.
    final recipe = target is RecipeMeal ? (target as RecipeMeal).recipe : null;
    final plannedDays = recipe == null
        ? null
        : ref
              .watch(viewedWeekProvider)
              .asData
              ?.value
              ?.entries
              .where((e) => e.recipeId == recipe.id)
              .map((e) => e.dayOfWeek)
              .toList();
    final hint = recipe == null
        ? null
        : batchHintFor(
            plannedDays: plannedDays ?? const [],
            newDay: dayOfWeek,
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
      final repo = ref.read(planningRepositoryProvider);
      final added = await ref.write(
        context,
        "add ${kWeekdayFull[dayOfWeek]}'s meal",
        () => switch (target) {
          RecipeMeal(:final recipe) => repo.addEntry(
            weekStart: weekStart,
            dayOfWeek: dayOfWeek,
            mealSlot: slotState.value,
            recipeId: recipe.id,
            eaterIds: eaters.value.toList(),
            portions: portionsOverride.value,
          ),
          SnackMeal(:final ingredient, :final quantity, :final unit) =>
            repo.addIngredientEntry(
              weekStart: weekStart,
              dayOfWeek: dayOfWeek,
              mealSlot: slotState.value,
              ingredientId: ingredient.id,
              eaterIds: eaters.value.toList(),
              quantity: quantity,
              unit: unit,
              measureId: (target as SnackMeal).measure?.id,
              portions: portionsOverride.value,
            ),
        },
      );
      if (added != null && context.mounted) Navigator.of(context).pop();
    }

    return AnsiSheetShell(
      title: 'Add to plan',
      // The day, stated rather than asked — the flow started on this card, so
      // the sheet names it back the way the meal editor names the row it was
      // opened from.
      subtitle: 'to · ${kWeekdayFull[dayOfWeek]}',
      titleSize: 22,
      centerTitle: false,
      dismiss: AnsiSheetDismiss.none,
      topPadding: 16,
      children: [
        const SizedBox(height: 14),
        switch (target) {
          RecipeMeal(:final recipe) => MealRecipeCard(recipe: recipe),
          final SnackMeal snack => MealSnackCard(snack: snack),
        },
        if (hint != null) ...[
          const SizedBox(height: 10),
          MealBatchBanner(hint: hint, recipe: recipe!, newDay: dayOfWeek),
        ],
        const SizedBox(height: 18),
        const AnsiMicroLabel('Slot'),
        MealSlotPicker(
          slot: slotState.value,
          onChanged: (s) => slotState.value = s,
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
        FButton(onPress: add, child: Text('Add to ${kWeekdayFull[dayOfWeek]}')),
      ],
    );
  }
}
