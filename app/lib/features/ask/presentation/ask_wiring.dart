/// Ansi's tools, wired to this phone's rows and actions.
///
/// Everything goes through a [ProviderContainer] captured when the sheet
/// opened, never a widget's `ref`: a question can outlive the widget that
/// asked it. Reads go to the repositories' streams directly, so no
/// auto-disposed provider is read once and lost
/// (`test/structure/no_future_on_autodispose_test.dart`).
library;

import 'package:hooks_riverpod/hooks_riverpod.dart';

import '../../account/data/household_providers.dart';
import '../../planning/data/planning_providers.dart';
import '../../planning/domain/planning.dart';
import '../../planning/presentation/week_view_models.dart';
import '../../recipes/data/recipe_providers.dart';
import '../../recipes/domain/line_override.dart';
import '../../recipes/presentation/recipe_view_models.dart';
import '../../timers/data/timer_providers.dart';
import '../domain/ask_screen.dart';
import '../domain/ask_tool_runner.dart';

/// Builds a runner whose `open_recipe` hands the recipe id to [open].
typedef AskToolRunnerFactory =
    AskToolRunner Function(void Function(String recipeId) open);

/// The runner over [container]'s repositories and actions.
AskToolRunner askToolRunner(
  ProviderContainer container, {
  required AskScreen Function() screen,
  required void Function(String recipeId) open,
}) {
  // Read when a tool runs, not before: most questions never touch the week.
  final recipes = container.read(recipeRepositoryProvider);
  return AskToolRunner(
    screen: screen,
    loadRecipe: (id) => recipes.watchRecipe(id).first,
    listRecipes: () async => [
      for (final r in await recipes.watchRecipes().first)
        (id: r.id, title: r.title),
    ],
    weekOf: (recipeId, weekKey) async {
      final start = weekStartOfKey(weekKey, container.read(weekShapeProvider));
      if (start == null) {
        return (overrides: const <LineOverride>[], portions: null);
      }
      final overrides = await container
          .read(weekVariantRepositoryProvider)
          .watchWeekOverrides(start)
          .first;
      final planning = container.read(planningRepositoryProvider);
      final plan = await planning.watchWeek(start).first;
      final members = {
        for (final m in await planning.watchMembers().first) m.id: m,
      };
      double? portions;
      for (final e in plan?.entries ?? const <PlanEntry>[]) {
        if (e.kind == PlanEntryKind.recipe && e.recipeId == recipeId) {
          portions = (portions ?? 0) + demandPortions(e, members);
        }
      }
      return (
        overrides: overrides[recipeId] ?? const <LineOverride>[],
        portions: portions,
      );
    },
    setServings: (recipeId, servings) =>
        container.read(recipeServingsProvider(recipeId).notifier).set(servings),
    startTimer:
        (
          recipe, {
          required step,
          required ordinal,
          required low,
          required high,
        }) => container
            .read(cookTimersProvider.notifier)
            .start(
              recipeId: recipe.id,
              recipeTitle: recipe.title,
              step: step,
              ordinal: ordinal,
              lowSeconds: low,
              highSeconds: high,
            ),
    openRecipe: open,
  );
}
