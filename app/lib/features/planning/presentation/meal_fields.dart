/// The controls a meal is described with — the picked recipe card, the slot
/// picker, the eater row and the portions stepper.
///
/// They live here because **two** sheets use them: `confirm_meal_sheet.dart`
/// places a NEW meal on the week, and `meal_editor_sheet.dart` changes the
/// slot, who's eating and how many portions on one already on it. Hoisting
/// them is the only way the two stay the same controls in the same order: two
/// copies would drift the first time one of them was touched (the same
/// argument that hoisted `MethodStepText` and [incompleteNote]).
///
/// There is no day control here at all — the add flow starts from a day, so
/// the day is a fact the sheet is opened with rather than a question it asks,
/// and a meal changes day by remove-and-re-add. The slot is different: a row
/// prints it, as the gutter label it sits under, so it is a field both sheets
/// hold.
///
/// [MealBatchBanner] rides along for the same reason: both sheets say the same
/// sentence about a meal joining an existing batch.
///
/// Nothing here talks to the repository or holds state; each control takes its
/// value and hands back the new one.
library;

import 'package:flutter/widgets.dart';
import 'package:forui/forui.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

import '../../../core/theme/ansi_theme.dart';
import '../../../core/theme/ansi_tokens.dart';
import '../../../core/units/portions.dart';
import '../../../shared/ansi_tap.dart';
import '../../../shared/format.dart';
import '../../../shared/incomplete_macros.dart';
import '../../account/data/household_providers.dart';
import '../../books/presentation/text_prompt.dart';
import '../../cook_plan/domain/cook_plan.dart';
import '../../recipes/domain/recipe.dart';
import '../domain/planning.dart';
import '../domain/week_macros.dart';
import 'confirm_meal_sheet.dart' show SnackMeal;
import 'week_format.dart';
import 'week_widgets.dart';

/// The picked recipe, with its shelf life and its HONEST per-serving line —
/// real numbers or the shared `incomplete` badge and reason, never zeros
/// (invariant 3).
class MealRecipeCard extends StatelessWidget {
  const MealRecipeCard({required this.recipe, super.key});

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
        color: AnsiColors.surface,
        border: Border.all(color: AnsiColors.line),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: AnsiColors.herbSoft,
              borderRadius: BorderRadius.circular(10),
            ),
            child: const Icon(
              FLucideIcons.cookingPot,
              size: 20,
              color: AnsiColors.herb,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  recipe.title.isEmpty ? 'Untitled recipe' : recipe.title,
                  style: ansiSerif(size: 17),
                ),
                if (shelf.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: Text(
                      shelf,
                      style: ansiMono(size: 10, color: AnsiColors.muted),
                    ),
                  ),
                if (perServing != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 3),
                    child: Text.rich(
                      TextSpan(
                        text:
                            'serves ${formatQuantity(recipe.servingsBase)} · '
                            '~${perServing.kcal.round()} kcal · '
                            '${perServing.protein.round()}P',
                        style: ansiMono(size: 10, color: AnsiColors.herbDeep),
                        children: [
                          TextSpan(
                            text: ' /serving',
                            style: ansiMono(size: 10, color: AnsiColors.muted),
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
                          style: ansiMono(size: 10, color: AnsiColors.muted),
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

/// The confirm sheet's card for a SNACK — a bare ingredient rather than a dish
/// (step 8.14 / A-D5).
///
/// Deliberately not a recipe card wearing a different icon: there is no shelf
/// life, no batch hint and no `/serving` denominator, because none of those are
/// facts about a protein bar. What it prints instead is the amount the quantity
/// sheet just settled, and — when the row can be weighed honestly — what one
/// portion of that amount comes to. A stub says so in the words a stub recipe
/// line uses, through the same [IncompleteBadge].
class MealSnackCard extends StatelessWidget {
  const MealSnackCard({required this.snack, super.key});

  final SnackMeal snack;

  @override
  Widget build(BuildContext context) {
    final entry = PlanEntry(
      id: '',
      dayOfWeek: 0,
      mealSlot: '',
      ingredientId: snack.ingredient.id,
      ingredientName: snack.ingredient.canonicalName,
      quantity: snack.quantity,
      unit: snack.unit,
      measureId: snack.measure?.id,
      measure: snack.measure,
      nutrition: (
        macros: snack.ingredient.macros,
        basis: snack.ingredient.macrosBasis,
        densityGPerMl: snack.ingredient.densityGPerMl,
        pieceBasisAmount: snack.ingredient.pieceBasisAmount,
      ),
    );
    final weighed = ingredientPortionMacros(entry, entry.nutrition);
    final perPortion = weighed.perPortion;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AnsiColors.surface,
        border: Border.all(color: AnsiColors.line),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: AnsiColors.herbSoft,
              borderRadius: BorderRadius.circular(10),
            ),
            child: const Icon(
              FLucideIcons.apple,
              size: 20,
              color: AnsiColors.herb,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(snack.ingredient.canonicalName, style: ansiSans(size: 15)),
                Padding(
                  padding: const EdgeInsets.only(top: 2),
                  child: Text(
                    snackAmount(entry),
                    style: ansiMono(size: 10, color: AnsiColors.muted),
                  ),
                ),
                if (perPortion != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 3),
                    child: Text.rich(
                      TextSpan(
                        text:
                            '~${perPortion.kcal.round()} kcal · '
                            '${perPortion.protein.round()}P',
                        style: ansiMono(size: 10, color: AnsiColors.herbDeep),
                        children: [
                          TextSpan(
                            text: ' /portion',
                            style: ansiMono(size: 10, color: AnsiColors.muted),
                          ),
                        ],
                      ),
                    ),
                  )
                else if (weighed.reason != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 3),
                    child: Row(
                      children: [
                        const IncompleteBadge(),
                        Text(
                          ' ${incompleteLineNote(weighed.reason!)}',
                          style: ansiMono(size: 10, color: AnsiColors.muted),
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

/// The slot picker: the default slots plus whatever custom slot the meal
/// already carries, with a trailing `+` that prompts a new one — `meal_slot` is
/// free text, so a household names its own.
///
/// **The day is not here, and that is the ruling.** Every add starts from a day
/// card, so the day is a fact the sheet was *opened with*: it is printed as the
/// sheet's subtitle and the button repeats it. A combined "Day · Slot" menu
/// would ask it again as one of many pairs, which makes the one question
/// actually open — the slot — the harder half of a pair nobody asked for. A
/// wrong day is one back-tap away, or remove-and-re-add once it is placed.
class MealSlotPicker extends StatelessWidget {
  const MealSlotPicker({
    required this.slot,
    required this.onChanged,
    super.key,
  });

  final String slot;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    final slots = [
      ...kDefaultMealSlots,
      if (!kDefaultMealSlots.contains(slot)) slot,
    ];
    return Row(
      children: [
        Expanded(
          child: FSelect<String>.rich(
            format: (v) => v,
            control: FSelectControl<String>.lifted(
              value: slot,
              onChange: (v) {
                if (v != null) onChanged(v);
              },
            ),
            children: [
              for (final s in slots) FSelectItem(title: Text(s), value: s),
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
              onChanged(custom.trim());
            }
          },
          child: const Icon(FLucideIcons.plus),
        ),
      ],
    );
  }
}

/// Who's eating: the roster as avatar + name, dimmed when not selected.
class MealEaterPicker extends StatelessWidget {
  const MealEaterPicker({
    required this.members,
    required this.selected,
    required this.onToggle,
    super.key,
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
                    style: ansiSans(
                      size: 13,
                      color: selected.contains(m.id)
                          ? AnsiColors.ink
                          : AnsiColors.muted,
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

/// Portions: the eaters' usual — Σ of their portion factors, said as a fraction
/// (`1¾ portions — Ada 1 · Jun ¾`) — or the whole-number [override] for
/// big/small appetites (spec §8), whose small print reads *overrides the
/// eaters' 1¾* so the figure it replaced is never hidden. The stepper itself
/// stays whole: from a fractional usual, `+` goes to the next whole number and
/// `−` to the previous one.
class MealPortionsStepper extends StatelessWidget {
  const MealPortionsStepper({
    required this.portionsOverride,
    required this.eaterIds,
    required this.roster,
    required this.onChanged,
    super.key,
  });

  /// `plan_entry.portions`: null tracks the eaters.
  final int? portionsOverride;

  /// Who is eating, and the household roster to read their factors and names
  /// from. An eater the roster lacks counts one, as [eatersDemand] says.
  final List<String> eaterIds;
  final List<Member> roster;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    final byId = {for (final m in roster) m.id: m};
    final usual = eatersDemand(eaterIds, byId);
    final demand = portionsOverride?.toDouble() ?? usual;
    // Names in roster order, each with their own factor.
    final names = [
      for (final m in roster)
        if (eaterIds.contains(m.id))
          '${m.displayName} ${formatFraction(m.portionFactor)}',
    ].join(' · ');
    final tracks = portionsOverride == null;
    final note = tracks
        ? names.isEmpty
              ? 'defaults to eaters — bump up for big appetites'
              : '$names — their usual'
        : eaterIds.isEmpty
        ? 'manual override'
        : 'overrides the eaters’ ${formatFraction(usual)}'
              '${names.isEmpty ? '' : ' — $names'}';
    return Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                formatPortions(demand),
                style: ansiSans(size: 15, weight: FontWeight.w600),
              ),
              const SizedBox(height: 2),
              Text(note, style: ansiMono(size: 10, color: AnsiColors.muted)),
            ],
          ),
        ),
        _StepButton(
          icon: FLucideIcons.minus,
          onTap: () => onChanged(demand.ceil() - 1),
        ),
        SizedBox(
          width: 40,
          child: Text(
            formatFraction(demand),
            textAlign: TextAlign.center,
            style: ansiMono(size: 16, weight: FontWeight.w600),
          ),
        ),
        _StepButton(
          icon: FLucideIcons.plus,
          onTap: () => onChanged(demand.floor() + 1),
        ),
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
    return AnsiTap(
      onTap: onTap,
      color: AnsiColors.herb,
      child: Container(
        width: 40,
        height: 40,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          border: Border.all(color: AnsiColors.line),
          borderRadius: BorderRadius.circular(AnsiRadii.box),
        ),
        child: Icon(icon, size: 16),
      ),
    );
  }
}

/// The batch-awareness cue, in full prose rather than a one-liner: it names the
/// dish, the day it already cooks, the shelf-life window that makes it one
/// batch, and the freezer hop when that's how the meal is reached.
class MealBatchBanner extends ConsumerWidget {
  const MealBatchBanner({
    required this.hint,
    required this.recipe,
    required this.newDay,
    super.key,
  });

  final BatchHint hint;
  final RecipeSummary recipe;
  final int newDay;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final title = recipe.title.isEmpty ? 'This dish' : recipe.title;
    final shape = ref.watch(weekShapeProvider);
    final day = shape.labelFull(hint.withDay);
    final target = shape.labelFull(newDay);
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
        color: AnsiColors.herbSoft,
        border: Border.all(color: AnsiColors.line),
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
              color: AnsiColors.herbDeep,
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              text,
              style: ansiSans(size: 12, color: AnsiColors.herbDeep),
            ),
          ),
        ],
      ),
    );
  }
}
