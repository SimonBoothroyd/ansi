/// The `nutrition`, `cost` and `prices` tools wired to this phone's rows: the
/// same summaries the recipe panel, the Week band and the Shop read, fetched
/// for whatever week or recipe the call names rather than the one on screen.
///
/// Reads go to the repositories' streams directly, through a container
/// captured when the sheet opened, as `ask_wiring.dart` does.
library;

import 'package:hooks_riverpod/hooks_riverpod.dart';

import '../../../core/week_shape.dart';
import '../../account/data/household_providers.dart';
import '../../ingredients/data/ingredient_providers.dart';
import '../../planning/data/planning_providers.dart';
import '../../planning/domain/planning.dart';
import '../../planning/domain/week_cost.dart';
import '../../planning/domain/week_macros.dart';
import '../../receipts/data/receipt_providers.dart';
import '../../receipts/domain/receipt_ledger.dart';
import '../../recipes/data/recipe_providers.dart';
import '../../recipes/domain/recipe_cost.dart';
import '../../recipes/domain/recipe_macros.dart';
import '../../shopping/presentation/shopping_view_models.dart';
import '../domain/ask_proposal.dart';
import '../domain/ask_tool_runner.dart';
import '../domain/ask_tools.dart';
import 'ask_figures.dart';

const _variantBasis = "this week's variant";

/// `Tue 20 Oct`, or `the week of 18 Oct`.
String _scopeLabel(WeekShape shape, AskPlanFigures scope) {
  final date = scope.date;
  return date == null
      ? 'the week of ${askDayLabel(shape, scope.weekStart)}'
      : askDayLabel(shape, date);
}

List<PlanEntry> _entriesOf(
  WeekPlan? plan,
  WeekShape shape,
  AskPlanFigures scope,
) {
  final date = scope.date;
  if (plan == null) return const [];
  return date == null ? plan.entries : plan.entriesForDay(shape.offsetOf(date));
}

Future<Map<String, Member>> _membersById(ProviderContainer c) async => {
  for (final m in await c.read(planningRepositoryProvider).watchMembers().first)
    m.id: m,
};

/// `nutrition`, as the recipe panel and the Week band read it.
Future<String> askNutrition(ProviderContainer c, AskFigureScope scope) async {
  final recipes = await c.read(recipeRepositoryProvider).watchRecipes().first;
  final macros = {
    for (final r in recipes)
      if (r.macros != null) r.id: r.macros!,
  };
  final variants = c.read(weekVariantRepositoryProvider);
  switch (scope) {
    case AskRecipeFigures(:final recipeId, :final servings, :final weekStart):
      final title = [
        for (final r in recipes)
          if (r.id == recipeId) r.title,
      ].firstOrNull;
      if (title == null) {
        throw const AskToolError('there is no recipe with that id');
      }
      final varied = weekStart == null
          ? null
          : (await variants
                .watchVariantRecipeMacros(weekStart)
                .first)[recipeId];
      final summary = varied ?? macros[recipeId];
      if (summary == null) {
        throw AskToolError("$title's figures are not worked out yet");
      }
      return recipeNutritionResult(
        title,
        summary,
        servings: servings,
        basis: varied == null ? null : _variantBasis,
      );
    case AskPlanFigures():
      final shape = c.read(weekShapeProvider);
      final plan = await c
          .read(planningRepositoryProvider)
          .watchWeek(scope.weekStart)
          .first;
      final varied = await variants
          .watchVariantRecipeMacros(scope.weekStart)
          .first;
      final summaries = <String, RecipeMacroSummary>{...macros, ...varied};
      return planNutritionResult(
        sumPlannedMacros(
          _entriesOf(plan, shape, scope),
          summaryFor: (id) => summaries[id],
          lensMemberId: scope.memberId,
          membersById: await _membersById(c),
        ),
        scope: _scopeLabel(shape, scope),
        forWhom: scope.forWhom,
        isDay: scope.date != null,
      );
    case AskTripFigures():
      throw const AskToolError(
        'the shopping list has a cost, not nutrition; ask about a day or week',
      );
  }
}

/// `cost`, as the recipe panel, the Week band and the Shop read it.
Future<String> askCost(ProviderContainer c, AskFigureScope scope) async {
  final variants = c.read(weekVariantRepositoryProvider);
  final prices = c.read(priceRepositoryProvider);
  switch (scope) {
    case AskRecipeFigures(:final recipeId, :final servings, :final weekStart):
      final recipes = await c
          .read(recipeRepositoryProvider)
          .watchRecipes()
          .first;
      final title = [
        for (final r in recipes)
          if (r.id == recipeId) r.title,
      ].firstOrNull;
      if (title == null) {
        throw const AskToolError('there is no recipe with that id');
      }
      final varied = weekStart == null
          ? null
          : (await variants.watchVariantRecipeCosts(weekStart).first)[recipeId];
      final summary =
          varied ??
          (await c
              .read(recipeRepositoryProvider)
              .watchRecipeCosts()
              .first)[recipeId];
      if (summary == null) {
        throw AskToolError("$title's cost is not worked out yet");
      }
      return recipeCostResult(
        title,
        summary,
        servings: servings,
        basis: varied == null ? null : _variantBasis,
      );
    case AskPlanFigures():
      final shape = c.read(weekShapeProvider);
      final plan = await c
          .read(planningRepositoryProvider)
          .watchWeek(scope.weekStart)
          .first;
      final costs = <String, RecipeCostSummary>{
        ...await c.read(recipeRepositoryProvider).watchRecipeCosts().first,
        ...await variants.watchVariantRecipeCosts(scope.weekStart).first,
      };
      final costPrices = await prices.watchCostPrices().first;
      String? spent;
      if (scope.date == null) {
        final receipts = await c
            .read(receiptRepositoryProvider)
            .watchReceipts()
            .first;
        spent = weekSpentLine(
          receiptsInWeek(
            [for (final r in receipts) receiptSummaryOf(r)],
            scope.weekStart,
            shape,
          ),
          shape,
        );
      }
      return planCostResult(
        sumPlannedCost(
          _entriesOf(plan, shape, scope),
          costFor: (id) => costs[id],
          priceFor: (id) => costPrices[id],
          lensMemberId: scope.memberId,
          membersById: await _membersById(c),
        ),
        scope: _scopeLabel(shape, scope),
        forWhom: scope.forWhom,
        spent: spent,
        isDay: scope.date != null,
      );
    case AskTripFigures(:final weekStart):
      // The Shop's own figure, at its prices rather than the latest, so the
      // answer always agrees with the sync line.
      return tripCostResult(await readShopTripCost(c, weekStart));
  }
}

/// `prices`: one ingredient's purchases and the price its costs read.
Future<String> askPrices(ProviderContainer c, String ingredientId) async {
  final ingredient = await c
      .read(ingredientRepositoryProvider)
      .byId(ingredientId);
  if (ingredient == null) {
    throw AskToolError('there is no food with the id `$ingredientId`');
  }
  final prices = c.read(priceRepositoryProvider);
  final costPrice = (await prices.watchCostPrices().first)[ingredientId];
  return pricesResult(
    ingredient.canonicalName,
    bought: await prices.watchPrices(ingredientId).first,
    costPrice: costPrice,
  );
}
