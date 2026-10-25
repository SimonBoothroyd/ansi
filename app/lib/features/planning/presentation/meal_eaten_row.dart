/// The meal sheet's top block from a meal's own day on: did the member
/// signed in on this phone eat it — *Ate this* or *Something else* — and
/// nobody else.
///
/// One question, then its answer: the two choices until one is given, then a
/// single line saying which (`Ate this`, or the plan crossed out and what was
/// had), its time, and a `×` back to the question. Answering never edits the
/// plan; it records who ate what, and when. The time is when they answered —
/// or, answered on a later day, the meal's own day at that clock time
/// ([defaultEatenAt]) — and tapping it opens a picker to change it.
library;

import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:forui/forui.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

import '../../../core/theme/ansi_theme.dart';
import '../../../core/theme/ansi_tokens.dart';
import '../../../core/words.dart';
import '../../../shared/ansi_modals.dart';
import '../../../shared/ansi_sheet_shell.dart';
import '../../../shared/ansi_tap.dart';
import '../../../shared/write.dart';
import '../../ingredients/presentation/ingredient_view_models.dart'
    show MacroDraft;
import '../data/planning_providers.dart';
import '../domain/planning.dart';
import 'confirm_meal_sheet.dart';
import 'meal_fields.dart';
import 'recipe_picker_sheet.dart';
import 'week_view_models.dart';
import 'week_widgets.dart';

/// `19:42` on the meal's own day, `Thu 19:42` on another.
String eatenAtLabel(DateTime at, {required DateTime mealDay}) {
  final local = at.toLocal();
  final clock =
      '${local.hour.toString().padLeft(2, '0')}:'
      '${local.minute.toString().padLeft(2, '0')}';
  final sameDay =
      local.year == mealDay.year &&
      local.month == mealDay.month &&
      local.day == mealDay.day;
  return sameDay ? clock : '${kWeekdayShort[local.weekday - 1]} $clock';
}

/// The block: one question with two answers, `Ate this` or `Something else`,
/// and once answered one line saying which, with its time and a `×`.
class MealEatenRow extends ConsumerWidget {
  const MealEatenRow({
    required this.entry,
    required this.memberId,
    required this.mealDay,
    super.key,
  });

  final PlanEntry entry;

  /// The member signed in on this phone — the only one this row writes for.
  final String memberId;

  /// The local day the meal is planned on.
  final DateTime mealDay;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ticked = entry.eatenAt[memberId];
    final had = entry.had[memberId];
    final repo = ref.read(planningRepositoryProvider);

    final Widget body;
    if (had != null) {
      body = _Answer(
        icon: FLucideIcons.arrowLeftRight,
        iconColor: AnsiColors.cautionInk,
        at: entry.hadAt(memberId, mealDay: mealDay)!,
        mealDay: mealDay,
        onPickTime: (at) => _pickTime(context, had.id, at),
        undoLabel: 'Had nothing else',
        onUndo: () => unawaited(
          ref.write(
            context,
            'take that back',
            () => repo.setInstead(entry.id, memberId: memberId, meal: null),
          ),
        ),
        child: AnsiTap(
          onTap: () => unawaited(_pickInstead(context, ref)),
          semanticsLabel: 'Change what you had instead',
          padding: const EdgeInsets.symmetric(vertical: 12),
          child: Text.rich(
            TextSpan(
              children: [
                // What was planned stays readable, crossed out: on this
                // phone it was not what was eaten.
                TextSpan(
                  text: mealTitleText(entry),
                  style: ansiSans(size: 14, color: AnsiColors.muted).copyWith(
                    decoration: TextDecoration.lineThrough,
                    decorationColor: AnsiColors.muted,
                  ),
                ),
                const TextSpan(text: '  →  '),
                TextSpan(
                  text: mealTitleText(had),
                  style: ansiSans(size: 14, weight: FontWeight.w500),
                ),
              ],
            ),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: ansiSans(size: 14, color: AnsiColors.muted),
          ),
        ),
      );
    } else if (ticked != null) {
      body = _Answer(
        icon: FLucideIcons.check,
        iconColor: AnsiColors.herbDeep,
        at: ticked,
        mealDay: mealDay,
        onPickTime: (at) => _pickTime(context, entry.id, at),
        undoLabel: 'Not eaten',
        onUndo: () => unawaited(
          ref.write(
            context,
            'untick it',
            () =>
                repo.setMealEaten(entry.id, memberId: memberId, eatenAt: null),
          ),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 12),
          child: Text(
            'Ate this',
            style: ansiSans(size: 14, weight: FontWeight.w500),
          ),
        ),
      );
    } else {
      body = IntrinsicHeight(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(
              child: _Choice(
                icon: FLucideIcons.check,
                label: 'Ate this',
                onTap: () => unawaited(
                  ref.write(
                    context,
                    'tick it',
                    () => repo.setMealEaten(
                      entry.id,
                      memberId: memberId,
                      eatenAt: defaultEatenAt(
                        mealDay: mealDay,
                        now: ref.read(clockProvider)(),
                      ),
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(width: 1, child: ColoredBox(color: AnsiColors.line)),
            Expanded(
              child: _Choice(
                icon: FLucideIcons.arrowLeftRight,
                label: 'Something else',
                onTap: () => unawaited(_pickInstead(context, ref)),
              ),
            ),
          ],
        ),
      );
    }
    return Container(
      decoration: BoxDecoration(
        color: AnsiColors.paper,
        borderRadius: BorderRadius.circular(12),
      ),
      child: body,
    );
  }

  /// The planning picker, for what was had instead: a recipe goes as it is, a
  /// bare ingredient asks its amount, a meal eaten out its optional figures.
  Future<void> _pickInstead(BuildContext context, WidgetRef ref) async {
    // Captured before the awaits: the sheet's row may be gone by the end
    // (`shared/write.dart`).
    final container = ProviderScope.containerOf(context, listen: false);
    final host = hostContextOf(context);
    final repo = ref.read(planningRepositoryProvider);
    final picked = await showRecipePickerSheet(
      context,
      dayOfWeek: entry.dayOfWeek,
      slot: entry.mealSlot,
      instead: true,
    );
    if (picked == null) return;
    final InsteadMeal meal;
    switch (picked) {
      case PickedRecipe(:final recipe):
        meal = InsteadRecipe(recipe.id);
      case PickedIngredientMeal(:final ingredient):
        final snack = await askSnackAmount(container, host, ingredient);
        if (snack == null) return;
        meal = InsteadIngredient(
          ingredientId: ingredient.id,
          quantity: snack.quantity,
          unit: snack.unit,
          measureId: snack.measure?.id,
        );
      case PickedMealOut(:final label):
        final draft = await showAnsiSheet<MacroDraft>(
          // The host outlives the row — see [hostContextOf].
          // ignore: use_build_context_synchronously
          context: host.context,
          builder: (_) => _InsteadOutSheet(label: label),
        );
        if (draft == null) return;
        // An incomplete panel writes as "not stated".
        meal = InsteadOut(label, macros: draft.toMacros());
    }
    await container.write(
      host,
      'say what you had instead',
      () => repo.setInstead(entry.id, memberId: memberId, meal: meal),
    );
  }

  /// Moves when [memberId] ate [eatenId] — the meal itself, or what they had
  /// instead of it — from [current].
  Future<void> _pickTime(
    BuildContext context,
    String eatenId,
    DateTime current,
  ) async {
    // Captured before the await: the sheet's row may be gone when the picker
    // closes (`shared/write.dart`).
    final container = ProviderScope.containerOf(context, listen: false);
    final host = hostContextOf(context);
    final repo = container.read(planningRepositoryProvider);
    final picked = await showAnsiSheet<DateTime>(
      context: context,
      builder: (_) => _EatenAtPicker(initial: current.toLocal()),
    );
    if (picked == null) return;
    await container.write(
      host,
      'change when you ate it',
      () => repo.setMealEaten(eatenId, memberId: memberId, eatenAt: picked),
    );
  }
}

/// One answer to the question, before either is given.
class _Choice extends StatelessWidget {
  const _Choice({required this.icon, required this.label, required this.onTap});

  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => AnsiTap(
    onTap: onTap,
    semanticsLabel: label,
    color: AnsiColors.herbDeep,
    radius: 12,
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 14),
    child: Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Icon(icon, size: 15),
        const SizedBox(width: 7),
        Flexible(
          child: Text(
            label,
            overflow: TextOverflow.ellipsis,
            style: ansiSans(
              size: 14,
              weight: FontWeight.w500,
              color: AnsiColors.herbDeep,
            ),
          ),
        ),
      ],
    ),
  );
}

/// The answer given: its mark, what it says, when, and the `×` that takes it
/// back to the question.
class _Answer extends StatelessWidget {
  const _Answer({
    required this.icon,
    required this.iconColor,
    required this.at,
    required this.mealDay,
    required this.onPickTime,
    required this.undoLabel,
    required this.onUndo,
    required this.child,
  });

  final IconData icon;
  final Color iconColor;
  final DateTime at;
  final DateTime mealDay;
  final Future<void> Function(DateTime current) onPickTime;
  final String undoLabel;
  final VoidCallback onUndo;
  final Widget child;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(left: 12),
    child: Row(
      children: [
        Icon(icon, size: 15, color: iconColor),
        const SizedBox(width: 8),
        Expanded(child: child),
        AnsiTap(
          onTap: () => unawaited(onPickTime(at)),
          semanticsLabel: 'Change when',
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 12),
          child: Text(
            '${eatenAtLabel(at, mealDay: mealDay)} ›',
            style: ansiMono(size: 12, color: AnsiColors.herbDeep),
          ),
        ),
        AnsiTap(
          onTap: onUndo,
          semanticsLabel: undoLabel,
          color: AnsiColors.muted,
          padding: const EdgeInsets.fromLTRB(4, 12, 12, 12),
          child: const Icon(FLucideIcons.x, size: 16),
        ),
      ],
    ),
  );
}

/// A date-and-time wheel and a Done.
class _EatenAtPicker extends StatefulWidget {
  const _EatenAtPicker({required this.initial});

  final DateTime initial;

  @override
  State<_EatenAtPicker> createState() => _EatenAtPickerState();
}

class _EatenAtPickerState extends State<_EatenAtPicker> {
  late DateTime _picked = widget.initial;

  @override
  Widget build(BuildContext context) {
    return AnsiSheetShell(
      title: 'When',
      centerTitle: false,
      topPadding: 16,
      children: [
        const SizedBox(height: 12),
        SizedBox(
          height: 180,
          child: FDateTimePicker(
            hour24: true,
            control: FDateTimePickerControl.managed(
              initial: widget.initial,
              onChange: (v) => _picked = v,
            ),
          ),
        ),
        const SizedBox(height: 16),
        FButton(
          onPress: () => Navigator.of(context).pop(_picked),
          child: const Text('Done'),
        ),
      ],
    );
  }
}

/// A meal eaten out, had instead: its words and the optional figures.
class _InsteadOutSheet extends HookWidget {
  const _InsteadOutSheet({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    final stated = useState(const MacroDraft());
    return AnsiSheetShell(
      title: 'Had instead',
      centerTitle: false,
      topPadding: 16,
      scrollable: true,
      children: [
        const SizedBox(height: 14),
        MealOutCard(label: label),
        const SizedBox(height: 18),
        MealMacrosFold(draft: stated.value, onChanged: (d) => stated.value = d),
        const SizedBox(height: 20),
        FButton(
          onPress: () => Navigator.of(context).pop(stated.value),
          child: const Text('Done'),
        ),
      ],
    );
  }
}
