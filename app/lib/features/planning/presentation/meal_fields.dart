/// The controls a meal is described with — the picked recipe card, the
/// combined `Day · Slot` dropdown, the eater row and the portions stepper.
///
/// They live here because **two** sheets use them: `confirm_meal_sheet.dart`
/// places a NEW meal on the week, and `entry_sheet.dart` (week-redesign D7)
/// edits one already on it. The design board's ruling is that editing is the
/// confirm sheet in its editing role — same controls, same order, so adding and
/// editing are one thing learned once. Hoisting them is the only way that stays
/// true: two copies would drift the first time one of them was touched (the
/// same argument that hoisted `MethodStepText` and `incompleteNote`).
///
/// [MealBatchBanner] rides along for the same reason: both sheets say the same
/// sentence about a meal joining an existing batch.
///
/// Nothing here talks to the repository or holds state; each control takes its
/// value and hands back the new one.
library;

import 'package:flutter/widgets.dart';
import 'package:forui/forui.dart';

import '../../../core/theme/ansi_theme.dart';
import '../../../core/theme/ansi_tokens.dart';
import '../../../shared/incomplete_macros.dart';
import '../../books/presentation/text_prompt.dart';
import '../../cook_plan/domain/cook_plan.dart';
import '../../recipes/domain/recipe.dart';
import '../../recipes/presentation/format.dart';
import '../domain/planning.dart';
import 'week_format.dart';
import 'week_widgets.dart';

/// A sheet section's micro-label (`SLOT`, `WHO'S EATING`, `PORTIONS`).
class MealFieldLabel extends StatelessWidget {
  const MealFieldLabel(this.text, {super.key});

  final String text;

  @override
  Widget build(BuildContext context) => Text(
    text.toUpperCase(),
    style: ansiMono(size: 10, color: AnsiColors.muted, letterSpacing: 1),
  );
}

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

/// The combined "Day · Slot" dropdown (confirm v2): one control carrying the
/// pair, so a meal can land on — or move to — a different day from the sheet.
/// A non-default slot (a custom "Brunch") joins the menu for every day; the
/// trailing + prompts a new custom slot, keeping the selected day.
class MealDaySlotPicker extends StatelessWidget {
  const MealDaySlotPicker({
    required this.day,
    required this.slot,
    required this.onChanged,
    super.key,
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

/// Portions, defaulting to the eater count and bumpable for big appetites
/// (spec §8). [eaters] lets the sub-line state the split the per-person macro
/// lens will use — the honest even share, at the moment you set it (D4a).
class MealPortionsStepper extends StatelessWidget {
  const MealPortionsStepper({
    required this.value,
    required this.tracksEaters,
    required this.onChanged,
    this.eaters = 0,
    super.key,
  });

  final int value;
  final bool tracksEaters;
  final int eaters;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    final note = tracksEaters
        ? 'defaults to eaters — bump up for big appetites'
        : eaters > 0
        ? '$value portions overrides the $eaters '
              '${eaters == 1 ? 'eater' : 'eaters'} — '
              '${formatQuantity(value / eaters)} each'
        : 'manual override';
    return Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '$value ${value == 1 ? 'portion' : 'portions'}',
                style: ansiSans(size: 15, weight: FontWeight.w600),
              ),
              const SizedBox(height: 2),
              Text(note, style: ansiMono(size: 10, color: AnsiColors.muted)),
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
            style: ansiMono(size: 16, weight: FontWeight.w600),
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
          color: AnsiColors.surface,
          border: Border.all(color: AnsiColors.line),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Icon(icon, size: 16, color: AnsiColors.herb),
      ),
    );
  }
}

/// The batch-awareness cue, in full prose (v2 — the app used to truncate
/// this to a one-liner): names the dish, the day it already cooks, the
/// shelf-life window that makes it one batch, and the freezer hop when
/// that's how the meal is reached.
class MealBatchBanner extends StatelessWidget {
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
