/// The add flow's last sheet: confirm the slot, the eaters and the portions,
/// then write the meal and pop.
///
/// It places any [MealTarget]; only the card at the top, the repository call
/// and a meal out's optional macros fold differ. The day arrives with the flow
/// and is stated, not asked. The slot opens on the day's next unfilled default
/// ([defaultMealSlot]). A null portions override tracks the eater count. Its
/// controls live in `meal_fields.dart`, shared with the meal editor.
library;

import 'package:flutter/widgets.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:forui/forui.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

import '../../../core/theme/ansi_theme.dart';
import '../../../core/theme/ansi_tokens.dart';
import '../../../core/units/measure.dart';
import '../../../core/units/unit_choice.dart';
import '../../../core/units/units.dart';
import '../../../shared/ansi_micro_label.dart';
import '../../../shared/ansi_modals.dart';
import '../../../shared/ansi_sheet_shell.dart';
import '../../../shared/write.dart';
import '../../account/data/household_providers.dart';
import '../../cook_plan/domain/cook_plan.dart';
import '../../cook_plan/domain/leftovers.dart';
import '../../cook_plan/presentation/leftover_format.dart';
import '../../cook_plan/presentation/leftovers_view_models.dart';
import '../../ingredients/domain/allowed_units.dart';
import '../../ingredients/domain/ingredient.dart';
import '../../ingredients/presentation/ingredient_view_models.dart'
    show MacroDraft;
import '../../ingredients/presentation/quantity_unit_sheet.dart';
import '../../ingredients/presentation/usual_amount.dart';
import '../../recipes/domain/recipe.dart';
import '../data/planning_providers.dart';
import '../domain/planning.dart' show Member, defaultMealSlot, eatersDemand;
import 'meal_fields.dart';
import 'use_up_block.dart';
import 'week_view_models.dart';

/// What this sheet is about to place on the week.
sealed class MealTarget {
  const MealTarget();
}

/// A dish. Its amount is its portions; the batch strip applies.
final class RecipeMeal extends MealTarget {
  const RecipeMeal(this.recipe);

  final RecipeSummary recipe;
}

/// A bare ingredient. Its amount is one portion, already settled by the
/// quantity sheet.
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

/// A meal eaten from a fridge or freezer row: a recipe meal that is not
/// cooked or bought, and may not take more than is left.
final class LeftoverMeal extends MealTarget {
  const LeftoverMeal({required this.recipe, required this.leftover});

  final RecipeSummary recipe;
  final Leftover leftover;
}

/// A meal eaten out: the typed words. Its figures are asked for on this sheet,
/// in the optional fold.
final class OutMeal extends MealTarget {
  const OutMeal(this.label);

  final String label;
}

/// The amount of one portion of [ingredient], asked on the quantity sheet: it
/// opens filled in with the amount of the last meal of it, else one of its
/// word for one, else one piece (`defaultAmountFor`); else empty, on the row's
/// first chip (ADR-0015). Null when the person backs out.
Future<SnackMeal?> askSnackAmount(
  ProviderContainer container,
  HostContext host,
  Ingredient ingredient,
) async {
  final usual = await usualAmountOf(container, ingredient, forMeal: true);
  final result = await showQuantityUnitSheet(
    // The host outlives the row that started the flow — see [hostContextOf].
    // ignore: use_build_context_synchronously
    host.context,
    ingredient: ingredient,
    initialQuantity: usual?.quantity,
    initialChoice: usual?.choice,
    requireQuantity: true,
    confirmLabel: 'Next',
  );
  if (result is! QuantitySaved) return null;
  return SnackMeal(
    ingredient: ingredient,
    quantity: result.quantity,
    unit: switch (result.choice) {
      // A measure-quantified row stores the count fallback beside the
      // measure id.
      MeasureOption() => pieces,
      RecipeMeasureOption(:final measure) => notAWordForAnIngredient(measure),
      UnitOption(:final unit) => unit,
    },
    measure: switch (result.choice) {
      MeasureOption(:final measure) => measure,
      RecipeMeasureOption(:final measure) => notAWordForAnIngredient(measure),
      UnitOption() => null,
    },
  );
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
    // A meal out's optional figures, as typed. Blank places the meal uncounted.
    final stated = useState(const MacroDraft());

    // A dish with a pot to eat from asks From leftovers or Cook fresh, and
    // answers neither for the household: null until one is picked.
    final fromLeftovers = useState<bool?>(null);
    // Add is single-shot: a second tap while the write is in flight would
    // insert the meal twice and pop the page under the sheet.
    final saving = useState(false);

    final members = ref.watch(membersProvider);
    final shape = ref.watch(weekShapeProvider);
    // Everyone eats until told otherwise. The effect runs inside this build,
    // so it comes before anything below reads the eaters.
    useEffect(() {
      members.whenData((list) {
        if (eaters.value.isEmpty) {
          eaters.value = {for (final m in list) m.id};
        }
      });
      return null;
    }, [members]);

    // The batch strip is a recipe fact; a snack is not cooked, so it has none.
    final picked = target is RecipeMeal ? (target as RecipeMeal).recipe : null;
    // The first pot of the dish picked that the meal's day can eat from: in
    // the fridge or the freezer, or planned and not cooked yet.
    final mealDay = DateTime(
      weekStart.year,
      weekStart.month,
      weekStart.day + dayOfWeek,
    );
    final today = ref.watch(todayProvider);
    final pot = picked == null
        ? null
        : ref
              .watch(leftoversGoodOnProvider(mealDay))
              .where((l) => l.recipeId == picked.id)
              .firstOrNull;
    final fromPot = fromLeftovers.value ?? false ? pot : null;
    // Eaten from a pot, it is not cooked for: no batch strip.
    final recipe = fromPot == null ? picked : null;
    final plannedDays = recipe == null
        ? null
        : ref
              .watch(viewedWeekProvider)
              .asData
              ?.value
              ?.entries
              .where((e) => e.recipeId == recipe.id && e.cooking == null)
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

    // A leftover says what this meal leaves of it, at the meal's own demand.
    // A pot not cooked yet makes this meal too: nothing to leave.
    final leftover = target is LeftoverMeal
        ? (target as LeftoverMeal).leftover
        : fromPot;
    final after = leftover == null || !leftover.cooked
        ? null
        : leftoverAfterLine(
            left: leftover.portions,
            demand:
                portionsOverride.value?.toDouble() ??
                eatersDemand(eaters.value, {
                  for (final m in members.asData?.value ?? const <Member>[])
                    m.id: m,
                }),
          );

    Future<void> add() async {
      if (saving.value) return;
      saving.value = true;
      // The sheet closes only on a write that landed; a throw must not leave it
      // open and inert.
      final repo = ref.read(planningRepositoryProvider);
      final added = await ref.write(
        context,
        "add ${shape.labelFull(dayOfWeek)}'s meal",
        () => switch (target) {
          RecipeMeal(:final recipe) => repo.addEntry(
            weekStart: weekStart,
            dayOfWeek: dayOfWeek,
            mealSlot: slotState.value,
            recipeId: recipe.id,
            eaterIds: eaters.value.toList(),
            portions: portionsOverride.value,
            cooking: fromPot?.id,
          ),
          // Planned from a pot: the meal links to its cooking.
          LeftoverMeal(:final recipe, :final leftover) => repo.addEntry(
            weekStart: weekStart,
            dayOfWeek: dayOfWeek,
            mealSlot: slotState.value,
            recipeId: recipe.id,
            eaterIds: eaters.value.toList(),
            portions: portionsOverride.value,
            cooking: leftover.id,
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
          // An incomplete panel ([MacroDraft.isCoherent]) writes as "not
          // stated".
          OutMeal(:final label) => repo.addOutEntry(
            weekStart: weekStart,
            dayOfWeek: dayOfWeek,
            mealSlot: slotState.value,
            label: label,
            eaterIds: eaters.value.toList(),
            macros: stated.value.toMacros(),
            portions: portionsOverride.value,
          ),
        },
      );
      if (!context.mounted) return;
      if (added == null) {
        saving.value = false;
        return;
      }
      popIfCurrent<void>(context);
    }

    return AnsiSheetShell(
      title: 'Add to plan',
      // The day is stated, not asked: the flow started on its card.
      subtitle: 'to · ${shape.labelFull(dayOfWeek)}',
      centerTitle: false,
      dismiss: AnsiSheetDismiss.none,
      topPadding: 16,
      // Scrolls, so a tall sheet on a small phone keeps its button reachable.
      scrollable: true,
      children: [
        const SizedBox(height: 14),
        switch (target) {
          RecipeMeal(:final recipe) => MealRecipeCard(recipe: recipe),
          LeftoverMeal(:final leftover) => LeftoverMealCard(leftover: leftover),
          final SnackMeal snack => MealSnackCard(snack: snack),
          OutMeal(:final label) => MealOutCard(label: label),
        },
        if (pot != null) ...[
          const SizedBox(height: 14),
          Row(
            children: [
              _Choice(
                label: 'From leftovers',
                detail: pot.cooked
                    ? leftCount(pot.portions)
                    : potWhen(pot, today, shape),
                selected: fromLeftovers.value ?? false,
                frozen: pot.place == LeftoverPlace.freezer,
                onTap: () => fromLeftovers.value = true,
              ),
              const SizedBox(width: 8),
              _Choice(
                label: 'Cook fresh',
                selected: fromLeftovers.value == false,
                onTap: () => fromLeftovers.value = false,
              ),
            ],
          ),
        ],
        if (hint != null) ...[
          const SizedBox(height: 12),
          MealBatchStrip(
            recipe: recipe!,
            plannedDays: plannedDays ?? const [],
            newDay: dayOfWeek,
          ),
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
          onChanged: (v) => portionsOverride.value = v,
        ),
        if (after != null)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text(
              after.text,
              style: ansiMono(
                size: 11,
                color: after.tooMuch ? AnsiColors.gone : AnsiColors.herbDeep,
              ),
            ),
          ),
        // Only a meal out is asked its figures; left empty it is placed
        // uncounted.
        if (target is OutMeal) ...[
          const SizedBox(height: 18),
          MealMacrosFold(
            draft: stated.value,
            onChanged: (d) => stated.value = d,
          ),
        ],
        const SizedBox(height: 20),
        FButton(
          // A meal cannot eat more of a leftover than is left, and a dish
          // with a pot waits for From leftovers or Cook fresh.
          onPress:
              saving.value ||
                  (after?.tooMuch ?? false) ||
                  (pot != null && fromLeftovers.value == null)
              ? null
              : add,
          child: Text('Add to ${shape.labelFull(dayOfWeek)}'),
        ),
      ],
    );
  }
}

/// One of the two answers a dish with a pot is asked: **From leftovers**
/// (with what is left, or when it cooks; blue from the freezer) or **Cook
/// fresh**.
class _Choice extends StatelessWidget {
  const _Choice({
    required this.label,
    required this.selected,
    required this.onTap,
    this.detail,
    this.frozen = false,
  });

  final String label;
  final String? detail;
  final bool selected;
  final bool frozen;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final ink = frozen ? AnsiColors.chillInk : AnsiColors.herbDeep;
    return Expanded(
      child: Semantics(
        button: true,
        selected: selected,
        label: detail == null ? label : '$label, $detail',
        child: ExcludeSemantics(
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: onTap,
            child: Container(
              constraints: const BoxConstraints(minHeight: 56),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              decoration: BoxDecoration(
                color: selected
                    ? (frozen ? AnsiColors.chill : AnsiColors.herbSoft)
                    : AnsiColors.surface,
                border: Border.all(
                  color: selected ? ink : AnsiColors.line,
                  width: selected ? 2 : 1,
                ),
                borderRadius: BorderRadius.circular(AnsiRadii.card),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    label,
                    style: ansiSans(
                      size: 13.5,
                      color: selected ? ink : AnsiColors.ink,
                      weight: selected ? FontWeight.w600 : FontWeight.w500,
                    ),
                  ),
                  if (detail case final detail?) ...[
                    const SizedBox(height: 3),
                    Text(detail, style: ansiMono(size: 10, color: ink)),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
