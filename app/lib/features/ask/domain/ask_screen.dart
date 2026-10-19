/// What the member is looking at when they ask. Pure Dart.
///
/// Sent at the head of every question as a `<screen>` block, so "how much
/// salt?" means the recipe on screen at the servings it shows. It is also the
/// chip above the input — what Ansi can see, said out loud — and the chip's ✕
/// sends [AskNoScreen] instead.
library;

import 'dart:convert';

import '../../../core/units/number_format.dart';

sealed class AskScreen {
  const AskScreen();

  /// The JSON the model reads. Keys are the prompt's
  /// (`supabase/functions/_shared/prompts/ask.ts`).
  Map<String, Object?> toJson();

  /// What the chip says, or null when there is no chip.
  String? get chipLabel;

  /// The `<screen>` block a question starts with.
  String get block => '<screen>${jsonEncode(toJson())}</screen>';
}

/// Nothing in particular: the chip was dismissed, or the screen names no
/// recipe.
class AskNoScreen extends AskScreen {
  const AskNoScreen();

  @override
  Map<String, Object?> toJson() => const {'route': 'other'};

  @override
  String? get chipLabel => null;
}

/// A recipe page, at the servings its stepper shows.
class AskRecipeScreen extends AskScreen {
  const AskRecipeScreen({
    required this.recipeId,
    required this.title,
    required this.servings,
    required this.servingsBase,
    this.weekKey,
    this.weekPortions,
    this.struckSteps = const [],
  });

  final String recipeId;
  final String title;

  /// The servings the page shows now — the amount every answer scales to.
  final double servings;

  /// The servings the recipe is written for.
  final double servingsBase;

  /// The week the page was opened from, when that week plans this recipe.
  final String? weekKey;

  /// That week's planned portions of this recipe, when known.
  final double? weekPortions;

  /// The method steps the cook has struck off, numbered from 1, so "what's
  /// next" has an answer.
  final List<int> struckSteps;

  @override
  Map<String, Object?> toJson() => {
    'route': 'recipe',
    'recipe_id': recipeId,
    'title': title,
    'servings': servings,
    'written_for': servingsBase,
    if (weekKey != null) 'week': weekKey,
    if (weekKey != null && weekPortions != null) 'week_portions': weekPortions,
    if (struckSteps.isNotEmpty) 'struck_steps': struckSteps,
  };

  @override
  String get chipLabel => '$title · serves ${formatAmount(servings)}';
}
