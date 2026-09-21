/// The sheet a dish row's portions chip and avatars open: the meal's slot, its
/// eaters and its portions.
///
/// A field editor only: the recipe opens from the row's title and removal is
/// the row's `−`. The day is not a field; a meal changes day by
/// remove-and-re-add. Controls come from `meal_fields.dart`. Every control
/// writes through on change, so `Close` only dismisses.
library;

import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

import '../../../shared/ansi_micro_label.dart';
import '../../../shared/ansi_modals.dart';
import '../../../shared/ansi_sheet_shell.dart';
import '../../../shared/write.dart';
import '../../account/data/household_providers.dart';
import '../data/planning_providers.dart';
import '../domain/planning.dart';
import 'meal_fields.dart';
import 'week_variant_door.dart';
import 'week_view_models.dart';

/// Opens the meal editor for [entry].
Future<void> showMealEditorSheet(
  BuildContext context, {
  required PlanEntry entry,
}) {
  return showAnsiSheet<void>(
    context: context,
    // The root navigator, not the branch's — see showRecipePickerSheet.
    builder: (_) => _MealEditorSheet(entryId: entry.id),
  );
}

class _MealEditorSheet extends ConsumerWidget {
  const _MealEditorSheet({required this.entryId});

  /// The entry's id, not the entry: the sheet re-reads the live row every
  /// build, so remote writes show and a removed entry draws nothing.
  final String entryId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final week = ref.watch(viewedWeekProvider).asData?.value;
    final entry = week?.entries.where((e) => e.id == entryId).firstOrNull;
    final members = ref.watch(membersProvider);
    final repo = ref.read(planningRepositoryProvider);

    // Removed while the sheet was open: draw nothing and let the user dismiss.
    if (entry == null) return const SizedBox.shrink();

    return AnsiSheetShell(
      // Every control writes through, so the way out is "Close".
      title: entry.recipeTitle ?? 'This meal',
      // Names the row that was tapped.
      subtitle:
          '${ref.watch(weekShapeProvider).labelFull(entry.dayOfWeek)} · '
          '${entry.mealSlot.toLowerCase()}',
      centerTitle: false,
      dismiss: AnsiSheetDismiss.close,
      topPadding: 16,
      scrollable: true,
      children: [
        const SizedBox(height: 18),
        const AnsiMicroLabel('Slot'),
        MealSlotPicker(
          slot: entry.mealSlot,
          onChanged: (s) => unawaited(
            ref.write(
              context,
              'move it to ${s.toLowerCase()}',
              () => repo.setMealSlot(entry.id, s),
            ),
          ),
        ),
        const SizedBox(height: 18),
        const AnsiMicroLabel("Who's eating"),
        members.when(
          loading: () => const SizedBox.shrink(),
          error: (_, _) => const SizedBox.shrink(),
          data: (list) => MealEaterPicker(
            members: list,
            selected: entry.eaterIds.toSet(),
            onToggle: (id) {
              final next = {...entry.eaterIds};
              next.contains(id) ? next.remove(id) : next.add(id);
              unawaited(
                ref.write(
                  context,
                  'change who is eating',
                  () => repo.setEaters(entry.id, next.toList()),
                ),
              );
            },
          ),
        ),
        const SizedBox(height: 18),
        const AnsiMicroLabel('Portions'),
        MealPortionsStepper(
          portionsOverride: entry.portions,
          eaterIds: entry.eaterIds,
          roster: members.asData?.value ?? const [],
          onChanged: (v) => unawaited(
            ref.write(
              context,
              'change the portions',
              () => repo.setPortions(entry.id, v < 1 ? 1 : v),
            ),
          ),
        ),
        // The door into week mode, for a recipe meal only. Its sub-line states
        // its scope, because the sheet is per meal and the variant is per week
        // and recipe.
        if (entry.kind == PlanEntryKind.recipe) ...[
          const SizedBox(height: 18),
          const AnsiMicroLabel('Ingredients'),
          WeekVariantDoorRow(
            recipeId: entry.recipeId!,
            recipeTitle: entry.recipeTitle,
          ),
        ],
        const SizedBox(height: 8),
      ],
    );
  }
}
