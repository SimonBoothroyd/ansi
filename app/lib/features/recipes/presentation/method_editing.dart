/// What the method step cards actually need from their host (seam **D4**).
///
/// The editor v2 cards (`method_editor.dart`) were written against
/// `RecipeEditor` because that was the only host there was. The import review
/// is the second — and it is the screen most likely to need a method fix, so
/// it was the wrong one to leave read-only.
///
/// This is a **declaration, not a refactor**: `RecipeEditor` already has every
/// member below, and gains `implements MethodEditing` with no change to its
/// body. The import side supplies `ImportMethodEditing`, an adapter over the
/// review draft. Both hosts keep their own state model — the alternative
/// (hoisting both onto a shared draft controller) would re-plumb a surface
/// that shipped the day before and is under sim coverage.
///
/// The surface is deliberately narrow and deliberately *the cards' own*: if a
/// card needs something new it goes here, and both hosts have to answer for
/// it. Two members exist only so the picker's add-a-line door can be offered —
/// `addLineItem` and `addComponentLineItem` — and the import adapter throws
/// [UnsupportedError] from them, with the door disabled and its reason shown
/// rather than the throw ever being reachable.
library;

import '../../../core/units/units.dart';
import '../../ingredients/domain/allowed_units.dart';
import '../../ingredients/domain/ingredient.dart';
import '../domain/method_draft.dart';
import '../domain/method_step.dart';
import '../domain/recipe.dart';

/// The host a `MethodStepCard` edits through.
abstract interface class MethodEditing {
  /// The method as the cards hold it: one sentence per step, plus the ranges
  /// that are chips or timers. Derived, so there is one source of truth.
  List<MethodDraftStep> methodDraft();

  /// The lines a chip can point at, by the id its refs carry. On the recipe
  /// editor these are real `line_item_id`s; at review they are the preview's
  /// synthetic `line-<i>` ids, which is what lets the "Reads as" fold show
  /// live amounts with no extra plumbing.
  Map<String, LineItem> lineById();

  /// The pending identity substitution to notice, or null. Always null at
  /// review: a re-match there re-points by line INDEX, so no chip can be
  /// orphaned by one.
  Substitution? substitution();

  /// Chips whose word no longer matches the line they point at. Always empty
  /// at review, for the same reason.
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
  /// `formatTimerRange`'s own output.
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

  /// Drops a chip or timer, keeping its word: the sentence survives and only
  /// the link dies.
  void removeChip(String stepId, int index);

  /// Dismisses one relabel notice, keeping the word the step already had.
  void keepOldWord(ChipRelabel relabel);

  /// The one lossy act: every chip and timer becomes ordinary words.
  void convertMethodToPlainText();

  /// Whether the chip picker may mint a BRAND-NEW line here. False at review
  /// (seam D4's scope cut): a new line would need a flat index `buildCommit`
  /// does not walk, and the review screen has never had an add-a-line
  /// affordance. The footer is then disabled and says [addLineReason] —
  /// disabled rather than hidden, because a door that vanishes teaches
  /// nothing — so the three members below are unreachable there.
  bool get canAddLine;

  /// Why [canAddLine] is false, in one line. Null when it is true.
  String? get addLineReason;

  /// The group a chip's *new* line lands in. Throws [UnsupportedError] on a
  /// host with no add-a-line door.
  String ensureGroupId();

  /// Appends an ingredient line. Throws [UnsupportedError] at review.
  void addLineItem(
    String groupId,
    Ingredient ingredient, {
    double? quantity,
    UnitChoice? choice,
  });

  /// Appends a sub-recipe component line. Throws [UnsupportedError] at review.
  void addComponentLineItem(
    String groupId,
    SubRecipeTarget target, {
    double? quantity,
    Unit? unit,
  });
}
