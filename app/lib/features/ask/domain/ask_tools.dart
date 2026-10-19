/// What each of Ansi's tools answers, built from the household's own rows.
/// Pure Dart.
///
/// **The model points; the app counts.** Every amount the model may repeat is
/// written here, by the same scaling and printing the recipe page uses
/// ([scaleLineItem], [amountOfLine], [foldMethod]). The model never sees a
/// stored quantity it would have to multiply itself.
///
/// The tool names and argument keys are the function's
/// (`supabase/functions/_shared/prompts/ask.ts`); a rename is made on both
/// sides at once.
library;

import 'dart:convert';

import '../../../core/search/search_rank.dart';
import '../../../core/units/number_format.dart';
import '../../recipes/domain/effective_lines.dart';
import '../../recipes/domain/line_display.dart';
import '../../recipes/domain/line_override.dart';
import '../../recipes/domain/method_step.dart';
import '../../recipes/domain/recipe.dart';
import '../../recipes/domain/scaling.dart';

/// The tool names, as the function declares them.
abstract final class AskTools {
  static const findRecipe = 'find_recipe';
  static const recipeLines = 'recipe_lines';
  static const methodStep = 'method_step';
  static const startStepTimer = 'start_step_timer';
  static const setServings = 'set_servings';
  static const openRecipe = 'open_recipe';
}

/// A tool call the app refuses, in words the model can repeat.
class AskToolError implements Exception {
  const AskToolError(this.message);
  final String message;
  @override
  String toString() => message;
}

/// The most rows [findRecipeResult] returns.
const kAskFindLimit = 5;

/// `find_recipe`: the household's recipes whose title hits [query], best tier
/// only — all spellings or all guesses, as the pickers show them.
String findRecipeResult(
  List<({String id, String title})> recipes,
  String query,
) {
  final hits = [
    for (final r in recipes) (recipe: r, hit: recipeTitleHit(r.title, query)),
  ].where((h) => h.hit != null).toList();
  final tier = bestTier([for (final h in hits) h.hit]);
  final best = [
    for (final h in hits)
      if (h.hit!.tier == tier) h,
  ]..sort((a, b) => b.hit!.score.compareTo(a.hit!.score));
  return jsonEncode({
    'query': query,
    'matches': [
      for (final h in best.take(kAskFindLimit))
        {'id': h.recipe.id, 'title': h.recipe.title},
    ],
    if (tier == SearchTier.typo) 'note': 'no exact spelling; these are guesses',
    if (best.isEmpty) 'note': 'no recipe title matches',
  });
}

/// `recipe_lines`: [recipe]'s lines scaled to [servings] and printed as the
/// page prints them.
///
/// With [ingredient], only the lines whose name it hits. When nothing hits,
/// every line comes back with a note, so a misheard word ("tomorrow") can be
/// matched by the model against the real names rather than answered as
/// absent. With [overrides] (this week's variant), lines go through
/// [effectiveLines] and the dropped ones are named.
String recipeLinesResult(
  Recipe recipe, {
  required double servings,
  String? ingredient,
  List<LineOverride>? overrides,
  String? basis,
}) {
  final factor = scaleFactorFor(recipe, servings);
  final week = overrides != null;
  final dropped = <String>[];
  final rows = <({String? group, LineItem line})>[];
  for (final group in recipe.groups) {
    final lines = week
        ? effectiveLines(group.items, overrides: overrides)
        : (kept: group.items, dropped: const <DroppedLine>[]);
    for (final d in lines.dropped) {
      dropped.add(d.line.subRecipe?.title ?? d.line.ingredientName);
    }
    for (final line in lines.kept) {
      rows.add((group: group.name, line: line));
    }
  }

  String nameOf(LineItem line) => line.subRecipe?.title ?? line.ingredientName;
  final query = ingredient?.trim() ?? '';
  final hits = query.isEmpty
      ? rows
      : [
          for (final r in rows)
            if (recipeTitleHit(nameOf(r.line), query) != null) r,
        ];
  final missed = query.isNotEmpty && hits.isEmpty;

  return jsonEncode({
    'recipe': recipe.title,
    'servings': formatAmount(servings),
    'written_for': formatAmount(recipe.servingsBase),
    'basis': ?basis,
    'lines': [
      for (final r in missed ? rows : hits)
        {
          'name': nameOf(r.line),
          'amount': amountOfLine(scaleLineItem(r.line, factor)),
          'group': ?r.group,
          if (r.line.note?.trim().isNotEmpty ?? false)
            'note': r.line.note!.trim(),
          if (r.line.optional) 'optional': true,
        },
    ],
    if (missed)
      'note':
          'no line is named "$query"; these are all the lines — if one '
          'sounds like it, it may be what was meant',
    if (dropped.isNotEmpty) 'left_out_this_week': dropped,
  });
}

/// The method's steps as plain text, chip amounts scaled by [factor].
List<String> methodStepTexts(Recipe recipe, {double factor = 1}) {
  final steps = recipe.methodSteps;
  if (steps == null) return [for (final s in recipe.steps) s.trim()];
  final lineById = {
    for (final g in recipe.groups)
      for (final item in g.items) item.id: item,
  };
  return [
    for (final step in steps)
      foldMethod(step, lineById: lineById, factor: factor)
          .map(
            (span) => switch (span) {
              MethodTextSpan(:final text) => text,
              MethodChipSpan(
                :final label,
                :final amount,
                :final constituents,
              ) =>
                [
                  ?amount,
                  if (label.isNotEmpty) label else constituents.join(', '),
                ].join(' '),
              MethodTimerSpan(:final text) => text,
            },
          )
          .join()
          .replaceAll(RegExp(r'\s+'), ' ')
          .trim(),
  ];
}

/// One step's timers, as `(lowSeconds, highSeconds)`, in chip order.
List<({int low, int high})> stepTimers(Recipe recipe, int index) {
  final steps = recipe.methodSteps;
  if (steps == null || index < 0 || index >= steps.length) return const [];
  return [
    for (final token in steps[index].tokens)
      if (token case MethodTimer(:final lowSeconds, :final highSeconds))
        (low: lowSeconds, high: highSeconds),
  ];
}

/// `method_step`: step [number] (from 1), at the page's [servings].
String methodStepResult(
  Recipe recipe, {
  required int number,
  required double servings,
}) {
  final texts = methodStepTexts(
    recipe,
    factor: scaleFactorFor(recipe, servings),
  );
  if (texts.isEmpty) throw AskToolError('${recipe.title} has no method');
  if (number < 1 || number > texts.length) {
    throw AskToolError(
      '${recipe.title} has ${texts.length} steps; there is no step $number',
    );
  }
  return jsonEncode({
    'recipe': recipe.title,
    'step': number,
    'of': texts.length,
    'text': texts[number - 1],
    'timers': [
      for (final t in stepTimers(recipe, number - 1))
        formatTimerRange(t.low, t.high),
    ],
  });
}

/// The timer `start_step_timer` names: step [number] (from 1), its [timer]th
/// (from 1, or the first). Throws [AskToolError] in the model's words.
({int step, int ordinal, int low, int high}) resolveStepTimer(
  Recipe recipe, {
  required int number,
  int? timer,
}) {
  final steps = recipe.methodSteps?.length ?? recipe.steps.length;
  if (number < 1 || number > steps) {
    throw AskToolError(
      '${recipe.title} has $steps steps; there is no step $number',
    );
  }
  final timers = stepTimers(recipe, number - 1);
  if (timers.isEmpty) {
    throw AskToolError('step $number of ${recipe.title} has no timer');
  }
  final ordinal = (timer ?? 1) - 1;
  if (ordinal < 0 || ordinal >= timers.length) {
    throw AskToolError(
      'step $number has ${timers.length} timer(s); there is no timer $timer',
    );
  }
  final t = timers[ordinal];
  return (step: number - 1, ordinal: ordinal, low: t.low, high: t.high);
}

/// The servings `set_servings` may set: positive, and kept to the quarter
/// steps a stepper could reach.
double acceptServings(Object? raw) {
  final n = raw is num ? raw.toDouble() : null;
  if (n == null || !n.isFinite || n <= 0 || n > 1000) {
    throw const AskToolError('servings must be a positive number');
  }
  return (n * 4).roundToDouble() / 4;
}
