/// The meal sheet's top block from a meal's own day on: *I ate this*, or
/// *Had something else*, for the member signed in on this phone and nobody
/// else.
///
/// Ticking never edits the plan; it records who ate the meal and when. The
/// time is when they ticked — or, ticked on a later day, the meal's own day at
/// that clock time — and the time beside the switch opens a picker to change
/// it.
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

/// When a tick made at [now] says a meal on [mealDay] was eaten: now, on the
/// meal's day; otherwise the meal's day at now's clock time, so a late tick
/// never lands on the wrong day.
DateTime defaultEatenAt({required DateTime mealDay, required DateTime now}) =>
    now.year == mealDay.year &&
        now.month == mealDay.month &&
        now.day == mealDay.day
    ? now
    : DateTime(mealDay.year, mealDay.month, mealDay.day, now.hour, now.minute);

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

/// The row: `I ate this`, the time once ticked, and the switch.
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
    final at = entry.eatenAt[memberId];
    final repo = ref.read(planningRepositoryProvider);

    void set(DateTime? when) => unawaited(
      ref.write(
        context,
        when == null ? 'untick it' : 'tick it',
        () => repo.setMealEaten(entry.id, memberId: memberId, eatenAt: when),
      ),
    );

    final had = entry.had[memberId];
    return Container(
      decoration: BoxDecoration(
        color: AnsiColors.paper,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.only(left: 12, right: 8),
            constraints: const BoxConstraints(minHeight: 48),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    'I ate this',
                    style: ansiSans(size: 14.5, weight: FontWeight.w500),
                  ),
                ),
                if (at != null)
                  AnsiTap(
                    onTap: () => unawaited(_pickTime(context, ref, at)),
                    semanticsLabel: 'Change when',
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 12,
                    ),
                    child: Text(
                      '${eatenAtLabel(at, mealDay: mealDay)} ›',
                      style: ansiMono(size: 12, color: AnsiColors.herbDeep),
                    ),
                  ),
                FSwitch(
                  semanticsLabel: 'I ate this',
                  value: at != null,
                  onChange: (on) => set(
                    on
                        ? defaultEatenAt(
                            mealDay: mealDay,
                            now: ref.read(clockProvider)(),
                          )
                        : null,
                  ),
                ),
              ],
            ),
          ),
          // Eating it and having something else are one or the other.
          if (at == null) ...[
            const SizedBox(
              height: 1,
              child: ColoredBox(color: AnsiColors.line),
            ),
            Row(
              children: [
                Expanded(
                  child: AnsiTap(
                    onTap: () => unawaited(_pickInstead(context, ref)),
                    semanticsLabel: had == null
                        ? 'Had something else'
                        : 'Change what you had instead',
                    padding: const EdgeInsets.fromLTRB(12, 13, 8, 13),
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(
                            had == null
                                ? 'Had something else'
                                : 'Instead: ${mealTitleText(had)}',
                            overflow: TextOverflow.ellipsis,
                            style: ansiSans(
                              size: 13.5,
                              color: had == null
                                  ? AnsiColors.ink
                                  : AnsiColors.cautionInk,
                            ),
                          ),
                        ),
                        Text(
                          '›',
                          style: ansiSans(size: 14, color: AnsiColors.herbDeep),
                        ),
                      ],
                    ),
                  ),
                ),
                if (had != null)
                  AnsiTap(
                    onTap: () => unawaited(
                      ref.write(
                        context,
                        'take that back',
                        () => repo.setInstead(
                          entry.id,
                          memberId: memberId,
                          meal: null,
                        ),
                      ),
                    ),
                    semanticsLabel: 'Had nothing else',
                    color: AnsiColors.muted,
                    padding: const EdgeInsets.fromLTRB(4, 12, 12, 12),
                    child: const Icon(FLucideIcons.x, size: 16),
                  ),
              ],
            ),
          ],
        ],
      ),
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

  Future<void> _pickTime(
    BuildContext context,
    WidgetRef ref,
    DateTime current,
  ) async {
    // Captured before the await: the sheet's row may be gone when the picker
    // closes (`shared/write.dart`).
    final container = ProviderScope.containerOf(context, listen: false);
    final host = hostContextOf(context);
    final repo = ref.read(planningRepositoryProvider);
    final picked = await showAnsiSheet<DateTime>(
      context: context,
      builder: (_) => _EatenAtPicker(initial: current.toLocal()),
    );
    if (picked == null) return;
    await container.write(
      host,
      'change when you ate it',
      () => repo.setMealEaten(entry.id, memberId: memberId, eatenAt: picked),
    );
  }
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
