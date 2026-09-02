/// What a dish row opens in EDIT mode (week-redesign D7): one sheet holding
/// everything there is to say about a planned meal — where it sits, who is
/// eating, how many portions, the way through to the recipe, and the way off
/// the week.
///
/// It is deliberately the confirm sheet in its editing role: the same picked
/// card, the same combined `Day · Slot` dropdown, the same eater row, the same
/// portions stepper, the same batch prose, in the same order (all of them from
/// `meal_fields.dart`, so the two cannot drift). Adding and editing are then
/// one thing learned once.
///
/// It retires the two half-measures it replaces — the per-row `⋯` popover and
/// the standalone "who's eating" dialog. A popover cannot hold day · slot ·
/// eaters · portions, which is why editing used to be split between a menu
/// (eaters) and remove-and-re-add (everything else).
///
/// Every control writes through on change; there is no Save. The sheet is a
/// view of a row, not a form over one — the same call the `⋯` menu made, minus
/// the ceremony. `Close` is therefore a dismissal, not a commit.
library;

import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:forui/forui.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

import '../../../core/theme/ansi_theme.dart';
import '../../../core/theme/ansi_tokens.dart';
import '../../../shared/ansi_modals.dart';
import '../../../shared/guarded_navigation.dart';
import '../../cook_plan/domain/cook_plan.dart';
import '../../recipes/presentation/recipe_view_models.dart';
import '../data/planning_providers.dart';
import '../domain/planning.dart';
import 'meal_fields.dart';
import 'week_view_models.dart';

/// Opens the entry sheet for [entry].
Future<void> showEntrySheet(BuildContext context, {required PlanEntry entry}) {
  return showAnsiSheet<void>(
    context: context,
    // The root navigator, not the branch's — see showRecipePickerSheet.
    builder: (_) => _EntrySheet(entryId: entry.id),
  );
}

class _EntrySheet extends HookConsumerWidget {
  const _EntrySheet({required this.entryId});

  /// The sheet holds the entry's ID, not the entry: it re-reads the live row
  /// every build, so its own writes (and the partner's) show immediately and
  /// a removed entry closes the sheet rather than editing a ghost.
  final String entryId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final week = ref.watch(viewedWeekProvider).asData?.value;
    final entry = week?.entries.where((e) => e.id == entryId).firstOrNull;
    final members = ref.watch(membersProvider);
    final repo = ref.read(planningRepositoryProvider);

    // The entry is gone (removed here, or by the other device). Close rather
    // than draw a sheet about nothing.
    useEffect(() {
      if (week != null && entry == null) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (context.mounted) Navigator.of(context).pop();
        });
      }
      return null;
    }, [week, entry]);

    if (entry == null) return const SizedBox.shrink();

    final recipe = ref
        .watch(recipeListProvider)
        .asData
        ?.value
        .where((r) => r.id == entry.recipeId)
        .firstOrNull;

    // The batch cue, live against the day the entry currently sits on — the
    // same sentence the confirm sheet says when the meal was added.
    final hint = recipe == null
        ? null
        : batchHintFor(
            plannedDays: [
              for (final e in week!.entries)
                if (e.recipeId == entry.recipeId && e.id != entry.id)
                  e.dayOfWeek,
            ],
            newDay: entry.dayOfWeek,
            keepsForDays: recipe.keepsForDays,
            freezable: recipe.freezable,
            freezerDays: recipe.freezerDays,
          );

    return Container(
      decoration: const BoxDecoration(
        color: AnsiColors.paper,
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        border: Border(top: BorderSide(color: AnsiColors.line)),
      ),
      child: Padding(
        padding: EdgeInsets.only(
          left: 20,
          right: 20,
          top: 16,
          bottom: MediaQuery.viewInsetsOf(context).bottom + 16,
        ),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text('This meal', style: ansiSerif(size: 22)),
                  ),
                  // Every control writes through, so there is nothing to save
                  // — but a sheet still needs a visible way out.
                  GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: () => Navigator.of(context).pop(),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 6,
                        vertical: 4,
                      ),
                      child: Text(
                        'Close',
                        style: ansiSans(size: 14, color: AnsiColors.herbDeep),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              if (recipe != null)
                MealRecipeCard(recipe: recipe)
              else
                _DeletedRecipeCard(title: entry.recipeTitle),
              if (hint != null && recipe != null) ...[
                const SizedBox(height: 10),
                MealBatchBanner(
                  hint: hint,
                  recipe: recipe,
                  newDay: entry.dayOfWeek,
                ),
              ],
              const SizedBox(height: 18),
              const MealFieldLabel('Day · slot'),
              const SizedBox(height: 6),
              MealDaySlotPicker(
                day: entry.dayOfWeek,
                slot: entry.mealSlot,
                onChanged: (day, slot) => unawaited(
                  repo.setDaySlot(
                    entryId: entry.id,
                    dayOfWeek: day,
                    mealSlot: slot,
                  ),
                ),
              ),
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
                    unawaited(repo.setEaters(entry.id, next.toList()));
                  },
                ),
              ),
              const SizedBox(height: 18),
              const MealFieldLabel('Portions'),
              const SizedBox(height: 6),
              MealPortionsStepper(
                value: entry.portionsOrDefault,
                tracksEaters: entry.portions == null,
                eaters: entry.eaterIds.length,
                onChanged: (v) =>
                    unawaited(repo.setPortions(entry.id, v < 1 ? 1 : v)),
              ),
              const SizedBox(height: 20),
              // A deleted recipe has no page to open, so the row is absent
              // rather than inert.
              if (entry.recipeTitle != null) ...[
                const MealFieldLabel('Recipe'),
                const SizedBox(height: 6),
                _SheetAction(
                  icon: FLucideIcons.cookingPot,
                  label: 'Open ${entry.recipeTitle}',
                  onTap: () {
                    Navigator.of(context).pop();
                    context.pushOnce('/recipes/${entry.recipeId}');
                  },
                ),
                const SizedBox(height: 10),
              ],
              _SheetAction(
                icon: FLucideIcons.trash2,
                label: 'Remove from the week',
                danger: true,
                onTap: () {
                  unawaited(repo.removeEntry(entry.id));
                  Navigator.of(context).pop();
                },
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// The picked card's stand-in when the recipe behind the entry is gone: the
/// meal is still a real row on the week and still editable, so the sheet says
/// what happened rather than rendering an empty card.
class _DeletedRecipeCard extends StatelessWidget {
  const _DeletedRecipeCard({required this.title});

  final String? title;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AnsiColors.surface,
        border: Border.all(color: AnsiColors.line),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Text(
        title == null
            ? 'This meal’s recipe was deleted — the meal is still on the week.'
            : '$title — still loading.',
        style: ansiMono(size: 12, color: AnsiColors.muted),
      ),
    );
  }
}

/// A full-width row action at the foot of the sheet.
class _SheetAction extends StatelessWidget {
  const _SheetAction({
    required this.icon,
    required this.label,
    required this.onTap,
    this.danger = false,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final bool danger;

  @override
  Widget build(BuildContext context) {
    final color = danger ? AnsiColors.gone : AnsiColors.herbDeep;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
        decoration: BoxDecoration(
          color: AnsiColors.surface,
          border: Border.all(color: AnsiColors.line),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          children: [
            Icon(icon, size: 16, color: color),
            const SizedBox(width: 10),
            Expanded(
              child: Text(label, style: ansiSans(size: 14, color: color)),
            ),
            if (!danger)
              const Icon(
                FLucideIcons.chevronRight,
                size: 14,
                color: AnsiColors.muted,
              ),
          ],
        ),
      ),
    );
  }
}
