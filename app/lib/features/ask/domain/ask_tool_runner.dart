/// Runs the tool calls Ansi makes, on this phone. Pure Dart.
///
/// The data and the actions are injected, so this file decides only what a
/// call means: which recipe, at which servings, which week. The answers
/// themselves are written by `ask_tools.dart`.
///
/// Three rules shape it. A screen names a recipe at the servings
/// its stepper shows, and a call about that recipe defaults to them. Only the
/// recipe on screen can be scaled: `set_servings` moves a stepper the member
/// can see. And a `propose_*` call writes nothing: it is checked, drawn as a
/// card, and waits for the member's Confirm ([AskHousehold.propose]).
library;

import 'dart:convert';

import '../../../core/units/number_format.dart';
import '../../../core/week_shape.dart';
import '../../cook_plan/domain/cook_plan.dart';
import '../../ingredients/domain/ingredient.dart';
import '../../planning/domain/planning.dart';
import '../../recipes/domain/line_override.dart';
import '../../recipes/domain/method_step.dart';
import '../../recipes/domain/recipe.dart';
import '../../shopping/domain/shopping.dart';
import 'ask_proposal.dart';
import 'ask_screen.dart';
import 'ask_thread.dart';
import 'ask_tools.dart';
import 'ask_week_tools.dart';

/// The household beyond the recipe on screen: the weeks, the cook plan, the
/// list and the vocabulary to read, and the card that asks before a write.
class AskHousehold {
  const AskHousehold({
    required this.today,
    required this.shape,
    required this.loadWeek,
    required this.previousWeek,
    required this.members,
    required this.me,
    required this.cookPlan,
    required this.shoppingList,
    required this.shopTotal,
    required this.searchIngredients,
    required this.ingredientsById,
    required this.propose,
  });

  /// Today, as a UTC date.
  final DateTime Function() today;
  final WeekShape Function() shape;
  final Future<WeekPlan?> Function(DateTime weekStart) loadWeek;

  /// The latest week before the one given with meals — what a copy copies.
  final Future<WeekPlan?> Function(DateTime weekStart) previousWeek;
  final Future<List<Member>> Function() members;

  /// The member this phone is signed in as, when it can be told (`askMe`).
  final String? Function(List<Member> members) me;
  final Future<CookPlan> Function(DateTime weekStart) cookPlan;
  final Future<ShoppingList> Function(DateTime weekStart) shoppingList;

  /// A list row's total as the Shop screen prints it.
  final String Function(ShoppingItem item) shopTotal;
  final Future<({List<Ingredient> rows, bool guessed})> Function(String query)
  searchIngredients;
  final Future<Map<String, Ingredient>> Function(Set<String> ids)
  ingredientsById;

  /// Draws the proposal as a card and resolves once the member has decided.
  final Future<AskDecision> Function(AskProposal proposal) propose;
}

/// What one call produced: the result the model reads, whether it is an
/// error, and — for an action — what the member is told was done.
typedef AskToolOutcome = ({String content, bool isError, String? done});

/// This week's say on one recipe: its variant and its planned portions.
typedef AskWeekOfRecipe = ({List<LineOverride> overrides, double? portions});

class AskToolRunner {
  AskToolRunner({
    required this.screen,
    required this.loadRecipe,
    required this.listRecipes,
    required this.weekOf,
    required this.setServings,
    required this.startTimer,
    required this.openRecipe,
    required this.household,
  });

  /// What is on screen now — read per call, so a stepper Ansi just moved is
  /// the servings the next call scales to.
  final AskScreen Function() screen;

  final Future<Recipe?> Function(String id) loadRecipe;
  final Future<List<({String id, String title})>> Function() listRecipes;
  final Future<AskWeekOfRecipe> Function(String recipeId, String weekKey)
  weekOf;
  final void Function(String recipeId, double servings) setServings;
  final void Function(
    Recipe recipe, {
    required int step,
    required int ordinal,
    required int low,
    required int high,
  })
  startTimer;
  final void Function(String recipeId) openRecipe;
  final AskHousehold household;

  /// The weeks read during this question, so a proposal can find the meals
  /// the model named by id.
  final _read = <DateTime, WeekPlan?>{};

  /// Runs [call]. Never throws: a refusal comes back as an error result the
  /// model can say in words.
  Future<AskToolOutcome> run(AskToolCall call) async {
    try {
      return await _run(call);
    } on AskToolError catch (e) {
      return (content: e.message, isError: true, done: null);
    } on Object catch (e) {
      return (
        content: 'that could not be read on the phone: $e',
        isError: true,
        done: null,
      );
    }
  }

  Future<AskToolOutcome> _run(AskToolCall call) async {
    final input = call.input;
    switch (call.name) {
      case AskTools.findRecipe:
        final query = _string(input, 'query');
        return _answer(findRecipeResult(await listRecipes(), query));

      case AskTools.recipeLines:
        final recipe = await _recipe(input);
        final asked = input['servings'];
        if (input['for_week'] == true) {
          final key = _onScreen(recipe)?.weekKey;
          if (key == null) {
            throw AskToolError(
              '${recipe.title} was not opened from a week that plans it',
            );
          }
          final week = await weekOf(recipe.id, key);
          final portions = week.portions;
          return _answer(
            recipeLinesResult(
              recipe,
              servings: asked == null
                  ? portions ?? _servingsFor(recipe)
                  : acceptServings(asked),
              ingredient: input['ingredient'] as String?,
              overrides: week.overrides,
              basis: portions == null
                  ? "this week's variant"
                  : "this week's plan: ${formatAmount(portions)} portions, "
                        "with this week's variant",
            ),
          );
        }
        return _answer(
          recipeLinesResult(
            recipe,
            servings: asked == null
                ? _servingsFor(recipe)
                : acceptServings(asked),
            ingredient: input['ingredient'] as String?,
          ),
        );

      case AskTools.methodStep:
        final recipe = await _recipe(input);
        return _answer(
          methodStepResult(
            recipe,
            number: _int(input, 'step'),
            servings: _servingsFor(recipe),
          ),
        );

      case AskTools.startStepTimer:
        final recipe = await _recipe(input);
        final t = resolveStepTimer(
          recipe,
          number: _int(input, 'step'),
          timer: input['timer'] is num
              ? (input['timer']! as num).toInt()
              : null,
        );
        startTimer(
          recipe,
          step: t.step,
          ordinal: t.ordinal,
          low: t.low,
          high: t.high,
        );
        final range = formatTimerRange(t.low, t.high);
        return (
          content: jsonEncode({'started': range, 'step': t.step + 1}),
          isError: false,
          done: 'Started step ${t.step + 1}’s timer · $range',
        );

      case AskTools.setServings:
        final on = screen();
        if (on is! AskRecipeScreen) {
          throw const AskToolError(
            'no recipe is on screen; only the recipe on screen can be scaled',
          );
        }
        final servings = acceptServings(input['servings']);
        setServings(on.recipeId, servings);
        final said = formatAmount(servings);
        return (
          content: jsonEncode({'recipe': on.title, 'servings': said}),
          isError: false,
          done: '${on.title} now serves $said',
        );

      case AskTools.openRecipe:
        final recipe = await _recipe(input);
        openRecipe(recipe.id);
        return (
          content: jsonEncode({'opened': recipe.title}),
          isError: false,
          done: 'Opening ${recipe.title}',
        );

      case AskTools.week:
        final h = household;
        final weekStart = _weekOf(input['week_of']);
        final plan = await _week(weekStart);
        final members = await h.members();
        final day = input['date'] == null ? null : parseAskDate(input['date']);
        if (day != null && h.shape().weekStartOf(day) != weekStart) {
          throw AskToolError(
            '${isoDateOf(day)} is not in the week of ${isoDateOf(weekStart)}',
          );
        }
        return _answer(
          weekResult(
            plan,
            weekStart: weekStart,
            shape: h.shape(),
            members: members,
            me: h.me(members),
            day: day,
            slot: input['slot'] as String?,
          ),
        );

      case AskTools.cookSessions:
        final weekStart = _weekOf(input['week_of']);
        final day = input['date'] == null ? null : parseAskDate(input['date']);
        return _answer(
          cookSessionsResult(
            await household.cookPlan(weekStart),
            weekStart: weekStart,
            shape: household.shape(),
            day: day,
          ),
        );

      case AskTools.shopping:
        final weekStart = _weekOf(input['week_of']);
        return _answer(
          shoppingResult(
            await household.shoppingList(weekStart),
            weekStart: weekStart,
            total: household.shopTotal,
            ingredient: input['ingredient'] as String?,
          ),
        );

      case AskTools.findIngredient:
        final query = _string(input, 'query');
        return _answer(
          findIngredientResult(await household.searchIngredients(query), query),
        );

      case AskTools.proposePlanChanges:
        final raw = input['changes'];
        if (raw is! List) throw const AskToolError('`changes` is missing');
        final changes = [
          for (final c in raw) Map<String, Object?>.from(c as Map),
        ];
        final shape = household.shape();
        // The meals a change names by id are looked for in the weeks its
        // dates fall in, the week on screen, this week and next.
        final thisWeek = shape.weekStartOf(household.today());
        for (final weekStart in {
          for (final date in datesNamed(changes)) shape.weekStartOf(date),
          _weekOf(null),
          thisWeek,
          thisWeek.add(const Duration(days: 7)),
        }) {
          await _week(weekStart);
        }
        final proposal = buildPlanProposal(
          changes,
          AskPlanContext(
            shape: shape,
            weeks: _read,
            members: await household.members(),
            recipeTitles: {
              for (final c in changes)
                if (c['recipe_id'] case final String id)
                  if (await loadRecipe(id) case final recipe?) id: recipe.title,
            },
            ingredients: await household.ingredientsById({
              for (final c in changes)
                if (c['ingredient_id'] case final String id) id,
            }),
          ),
        );
        return _decided(proposal);

      case AskTools.proposeCopyLastWeek:
        final weekStart = _weekOf(input['week_of']);
        final proposal = buildCopyWeekProposal(
          shape: household.shape(),
          weekStart: weekStart,
          source: await household.previousWeek(weekStart),
          target: await _week(weekStart),
        );
        return _decided(proposal);

      case AskTools.proposeTopUp:
        final weekStart = _weekOf(input['week_of']);
        final id = input['ingredient_id'];
        Ingredient? ingredient;
        if (id is String) {
          ingredient = (await household.ingredientsById({id}))[id];
          if (ingredient == null) {
            throw AskToolError('there is no ingredient with the id `$id`');
          }
        }
        return _decided(
          buildTopUpProposal(
            weekStart: weekStart,
            shape: household.shape(),
            ingredient: ingredient,
            quantity: input['quantity'],
            unit: input['unit'],
            item: input['item'] as String?,
          ),
        );
    }
    throw AskToolError('there is no tool called ${call.name}');
  }

  /// Waits for the member's decision on [proposal]; a confirmed one is
  /// listed under the answer like any action.
  Future<AskToolOutcome> _decided(AskProposal proposal) async {
    final decision = await household.propose(proposal);
    // Written or changed underneath: the weeks read so far are stale.
    if (decision != AskDecision.cancelled) _read.clear();
    return (
      content: jsonEncode({
        'outcome': decision.name,
        'meaning': decision.said,
        'card': [for (final r in proposal.rows) r.toJson()],
      }),
      isError: false,
      done: decision == AskDecision.confirmed ? proposal.title : null,
    );
  }

  /// The week a call names by any date in it; with none, the week on screen,
  /// else this week.
  DateTime _weekOf(Object? raw) {
    final shape = household.shape();
    if (raw != null) return shape.weekStartOf(parseAskDate(raw));
    final on = screen();
    if (on is AskWeekScreen) return on.weekStart;
    if (on is AskRecipeScreen && on.weekKey != null) {
      final d = DateTime.tryParse(on.weekKey!);
      if (d != null) return shape.weekStartOf(d);
    }
    return shape.weekStartOf(household.today());
  }

  Future<WeekPlan?> _week(DateTime weekStart) async {
    if (_read.containsKey(weekStart)) return _read[weekStart];
    return _read[weekStart] = await household.loadWeek(weekStart);
  }

  static AskToolOutcome _answer(String content) =>
      (content: content, isError: false, done: null);

  /// The recipe screen, when it shows [recipe].
  AskRecipeScreen? _onScreen(Recipe recipe) {
    final on = screen();
    return on is AskRecipeScreen && on.recipeId == recipe.id ? on : null;
  }

  /// The servings a call about [recipe] defaults to: the stepper's when it is
  /// on screen, the recipe's own otherwise.
  double _servingsFor(Recipe recipe) =>
      _onScreen(recipe)?.servings ?? recipe.servingsBase;

  Future<Recipe> _recipe(Map<String, Object?> input) async {
    final id = _string(input, 'recipe_id');
    final recipe = await loadRecipe(id);
    if (recipe == null) {
      throw const AskToolError('there is no recipe with that id');
    }
    return recipe;
  }

  static String _string(Map<String, Object?> input, String key) {
    final v = input[key];
    if (v is! String || v.trim().isEmpty) {
      throw AskToolError('`$key` is missing');
    }
    return v.trim();
  }

  static int _int(Map<String, Object?> input, String key) {
    final v = input[key];
    if (v is! num) throw AskToolError('`$key` must be a number');
    return v.toInt();
  }
}
