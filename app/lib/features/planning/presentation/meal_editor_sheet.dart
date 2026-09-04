/// What the dish row's **portions chip + eater avatars** open: who is eating
/// this meal, and how many portions to cook.
///
/// **A field editor, not a hub.** It is reached by tapping *the values it
/// edits* and holds nothing else: there is no route to the recipe in here (that
/// is the row's title) and no remove (that is the row's `−`).
///
/// The rule it comes from: **a row's controls are the facts the row prints.**
/// Day · slot is not one of them — a row does not print a day as a value, its
/// *position* is its day — so moving a meal is remove-and-re-add through the
/// picker's "already this week" quick picks, and no repository method exists
/// for it.
///
/// Both controls come from `meal_fields.dart`, which is the whole reason that
/// file exists: the confirm sheet sets these two fields when a meal is made,
/// this sets them afterwards, and hoisting them is what stops the two paths
/// drifting.
///
/// Every control writes through on change; there is no Save. `Close` is a
/// dismissal, not a commit.
library;

import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

import '../../../core/words.dart';
import '../../../shared/ansi_modals.dart';
import '../../../shared/ansi_sheet_shell.dart';
import '../../../shared/write.dart';
import '../data/planning_providers.dart';
import '../domain/planning.dart';
import 'meal_fields.dart';
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

  /// The sheet holds the entry's ID, not the entry: it re-reads the live row
  /// every build, so its own writes (and the partner's) show immediately, and
  /// an entry removed from the row underneath — or from the other phone —
  /// leaves the sheet drawing nothing rather than editing a ghost.
  final String entryId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final week = ref.watch(viewedWeekProvider).asData?.value;
    final entry = week?.entries.where((e) => e.id == entryId).firstOrNull;
    final members = ref.watch(membersProvider);
    final repo = ref.read(planningRepositoryProvider);

    // Gone while the sheet was open. Unlike the entry sheet this one has no
    // removal of its own to race with, so there is nothing to auto-pop for:
    // the sheet simply has nothing to say, and the user's own dismissal is
    // still the way out.
    if (entry == null) return const SizedBox.shrink();

    return AnsiSheetShell(
      // Every control writes through, so there is nothing to save — "Close" is
      // the honest way out.
      title: entry.recipeTitle ?? 'This meal',
      // Which meal this is, since the sheet no longer carries the picked-recipe
      // card: the row you tapped, named back to you.
      subtitle:
          '${kWeekdayFull[entry.dayOfWeek]} · '
          '${entry.mealSlot.toLowerCase()}',
      titleSize: 22,
      centerTitle: false,
      dismiss: AnsiSheetDismiss.close,
      topPadding: 16,
      scrollable: true,
      children: [
        const SizedBox(height: 18),
        const MealFieldLabel("Who's eating"),
        const SizedBox(height: 6),
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
        const MealFieldLabel('Portions'),
        const SizedBox(height: 6),
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
        const SizedBox(height: 8),
      ],
    );
  }
}
