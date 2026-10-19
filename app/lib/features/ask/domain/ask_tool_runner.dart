/// Runs the tool calls Ansi makes, on this phone. Pure Dart.
///
/// The data and the actions are injected, so this file decides only what a
/// call means: which recipe, at which servings, which week. The answers
/// themselves are written by `ask_tools.dart`.
///
/// Two rules shape it. A screen names a recipe at the servings
/// its stepper shows, and a call about that recipe defaults to them. Only the
/// recipe on screen can be scaled: `set_servings` moves a stepper the member
/// can see.
library;

import 'dart:convert';

import '../../../core/units/number_format.dart';
import '../../recipes/domain/line_override.dart';
import '../../recipes/domain/method_step.dart';
import '../../recipes/domain/recipe.dart';
import 'ask_screen.dart';
import 'ask_thread.dart';
import 'ask_tools.dart';

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
    }
    throw AskToolError('there is no tool called ${call.name}');
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
