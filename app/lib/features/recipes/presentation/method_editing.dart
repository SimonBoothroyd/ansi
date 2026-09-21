/// What the method step cards (`method_editor.dart`) need from their host.
/// Implemented by `RecipeEditor` and by `ImportMethodEditing`, an adapter over
/// the import review's draft.
///
/// `addLineItem` and `addComponentLineItem` exist only for the picker's
/// add-a-line door; the import adapter throws [UnsupportedError] from them and
/// disables the door with its reason.
library;

import '../../../core/units/recipe_measure.dart';
import '../../../core/units/units.dart';
import '../../ingredients/domain/allowed_units.dart';
import '../../ingredients/domain/ingredient.dart';
import '../domain/method_draft.dart';
import '../domain/method_step.dart';
import '../domain/recipe.dart';

/// The host a `MethodStepCard` edits through.
abstract interface class MethodEditing {
  /// The method as the cards hold it: one sentence per step, plus the ranges
  /// that are chips or timers.
  List<MethodDraftStep> methodDraft();

  /// The lines a chip can point at, by ref id: real `line_item_id`s in the
  /// editor, the preview's synthetic `line-<i>` ids at review.
  Map<String, LineItem> lineById();

  /// The pending identity substitution to notice, or null. Always null at
  /// review, where a re-match re-points by line index and orphans no chip.
  Substitution? substitution();

  /// Chips whose word no longer matches their line. Always empty at review.
  List<ChipRelabel> relabels();

  /// What a convert-to-plain-text would cost, for the confirm to count.
  ({int chips, int timers}) methodLinkCounts();

  void editStep(String stepId, String text);
  void addMethodStep();
  void removeMethodStep(String stepId);
  void moveMethodStep(String stepId, int by);

  /// Chips `[start, end)` of [stepId] — changing no text.
  void chipRange(
    String stepId, {
    required int start,
    required int end,
    required List<String> refs,
    ChipAmountRule? amountRule,
  });

  /// Marks `[start, end)` of [stepId] as a timer, rewriting its words to
  /// [formatTimerRange]'s output.
  void timerRange(
    String stepId, {
    required int start,
    required int end,
    required int lowSeconds,
    required int highSeconds,
  });

  /// The no-selection door: splices [word] in at the caret and chips it.
  void insertChip(
    String stepId, {
    required int offset,
    required String word,
    required List<String> refs,
  });

  void insertTimer(
    String stepId, {
    required int offset,
    required int lowSeconds,
    required int highSeconds,
  });

  void repointChip(String stepId, int index, List<String> refs);
  void renameChip(String stepId, int index, String word);
  void setChipAmountRule(String stepId, int index, ChipAmountRule rule);
  void setTimerSpan(String stepId, int index, int low, int high);

  /// Drops a chip or timer, keeping its word in the sentence.
  void removeChip(String stepId, int index);

  /// Dismisses one relabel notice, keeping the word the step already had.
  void keepOldWord(ChipRelabel relabel);

  /// The one lossy act: every chip and timer becomes ordinary words.
  void convertMethodToPlainText();

  /// Whether the chip picker may mint a new line here. False at review, where
  /// `buildCommit` cannot index a new line; the footer is then disabled and
  /// shows [addLineReason], and the three members below are unreachable.
  bool get canAddLine;

  /// Why [canAddLine] is false, in one line. Null when it is true.
  String? get addLineReason;

  /// The group a chip's new line lands in. Throws [UnsupportedError] at review.
  String ensureGroupId();

  /// Appends an ingredient line. Throws [UnsupportedError] at review.
  void addLineItem(
    String groupId,
    Ingredient ingredient, {
    double? quantity,
    UnitChoice? choice,
  });

  /// Appends a sub-recipe component line. Throws [UnsupportedError] at review.
  /// [recipeMeasureId] replaces the unit (ADR-0018). [recipeMeasure] is that
  /// measure's row where the caller has it, since a just-coined one is not yet
  /// in [target].
  void addComponentLineItem(
    String groupId,
    SubRecipeTarget target, {
    double? quantity,
    Unit? unit,
    String? recipeMeasureId,
    RecipeMeasure? recipeMeasure,
    bool optional,
  });
}
