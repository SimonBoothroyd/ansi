/// The import review as a host for the editor's method step cards.
///
/// This adapter implements [MethodEditing] over the review's state and owns
/// none itself: it derives the drafts from the preview recipe until someone
/// types, and every mutator re-seats the whole list through
/// [ImportController.setMethodDraft]. Chips key on the preview's ids
/// (`previewLineId(i) == 'line-<i>'`), and [stepsFromDrafts] parses them back
/// to line indexes at commit. A line added from the chip picker lands in the
/// review's last section, as one added from the list does.
library;

import '../../../core/units/recipe_measure.dart';
import '../../../core/units/units.dart';
import '../../ingredients/domain/allowed_units.dart';
import '../../ingredients/domain/ingredient.dart';
import '../../recipes/domain/method_draft.dart';
import '../../recipes/domain/method_step.dart';
import '../../recipes/domain/recipe.dart';
import '../../recipes/presentation/method_editing.dart';
import '../domain/line_resolution.dart';
import '../domain/method_draft_bridge.dart';
import '../domain/preview_recipe.dart';
import 'import_view_models.dart';

/// Adapts the import review to the step cards' host interface.
class ImportMethodEditing implements MethodEditing {
  ImportMethodEditing({
    required this.controller,
    required this.state,
    required this.preview,
  });

  final ImportController controller;
  final ImportReconciling state;

  /// The recipe the review is previewing — the source of both the line map
  /// and, until somebody types, the drafts themselves.
  final Recipe preview;

  /// The drafts as they stand now, not when this adapter was built. One gesture
  /// fires several mutators, each re-seating the whole list; reading the
  /// captured [state] would make the second undo the first. [preview] is
  /// consulted only while nobody has edited.
  @override
  List<MethodDraftStep> methodDraft() => _now.methodDrafts(preview: _preview);

  @override
  Map<String, LineItem> lineById() => {
    for (final group in _preview.groups)
      for (final item in group.items) item.id: item,
  };

  /// The reconciliation as it stands right now, which after any mutator in
  /// this gesture is not the one the view handed over.
  ImportReconciling get _now => controller.reconciling() ?? state;

  /// The preview over [_now]. Once something has moved it is re-derived, so a
  /// line the chip picker just added is pickable immediately. The re-derived
  /// one carries no measure map, so a chip's amount can read as a bare count
  /// for one frame.
  Recipe get _preview {
    final now = _now;
    if (identical(now, state)) return preview;
    return buildPreviewRecipe(
      now.payload,
      now.resolutions,
      servingsBase: now.servings,
      sections: now.sections,
    );
  }

  /// The identity change being read through this sitting. A re-match re-points
  /// by line index, so no chip is orphaned, but its word may now name a food
  /// the recipe lacks. The controller runs the editor's `relabelRefs` on an
  /// identity change, which drives the notice and *keep the old word*.
  @override
  Substitution? substitution() => controller.substitution();

  @override
  List<ChipRelabel> relabels() => controller.relabels();

  @override
  ({int chips, int timers}) methodLinkCounts() {
    var chips = 0;
    var timers = 0;
    for (final step in methodDraft()) {
      for (final span in step.spans) {
        if (span is RefSpan) chips++;
        if (span is TimerSpan) timers++;
      }
    }
    return (chips: chips, timers: timers);
  }

  void _set(List<MethodDraftStep> drafts) => controller.setMethodDraft(drafts);

  void _mapStep(String stepId, MethodDraftStep Function(MethodDraftStep) f) {
    final drafts = methodDraft();
    final i = drafts.indexWhere((d) => d.id == stepId);
    if (i < 0) return;
    final next = f(drafts[i]);
    // Forui registers its onChange as a plain controller listener, so a no-op
    // edit must not re-enter state: it would round-trip forever.
    if (next == drafts[i]) return;
    _set([...drafts]..[i] = next);
  }

  @override
  void editStep(String stepId, String text) =>
      _mapStep(stepId, (d) => applyEdit(d, text));

  @override
  void addMethodStep() =>
      _set(addStep(methodDraft(), id: 'step-new-${_newStepSeq++}'));

  /// A counter rather than a uuid: the review persists nothing, and readable
  /// ids keep widget-test keys legible.
  static int _newStepSeq = 0;

  @override
  void removeMethodStep(String stepId) =>
      _set(removeStep(methodDraft(), stepId));

  @override
  void moveMethodStep(String stepId, int by) =>
      _set(moveStep(methodDraft(), stepId, by));

  @override
  void chipRange(
    String stepId, {
    required int start,
    required int end,
    required List<String> refs,
    ChipAmountRule? amountRule,
  }) => _mapStep(
    stepId,
    (d) => annotate(
      d,
      RefSpan(
        start: start,
        end: end,
        refs: refs,
        amountRule:
            amountRule ??
            amountRuleFor(
              methodDraft(),
              lineId: refs.first,
              stepId: stepId,
              offset: start,
            ),
      ),
    ),
  );

  @override
  void timerRange(
    String stepId, {
    required int start,
    required int end,
    required int lowSeconds,
    required int highSeconds,
  }) => _mapStep(stepId, (d) {
    final span = TimerSpan(
      start: start,
      end: end,
      lowSeconds: lowSeconds,
      highSeconds: highSeconds,
    );
    final marked = annotate(d, span);
    final index = marked.spans.indexWhere((s) => s.start == start);
    if (index < 0) return marked;
    return respan(
      marked,
      index,
      span: span,
      word: formatTimerRange(lowSeconds, highSeconds),
    );
  });

  @override
  void insertChip(
    String stepId, {
    required int offset,
    required String word,
    required List<String> refs,
  }) => _mapStep(
    stepId,
    (d) => insertSpan(
      d,
      offset: offset,
      word: word,
      span: RefSpan(
        start: 0,
        end: 0,
        refs: refs,
        amountRule: amountRuleFor(
          methodDraft(),
          lineId: refs.first,
          stepId: stepId,
          offset: offset,
        ),
      ),
    ),
  );

  @override
  void insertTimer(
    String stepId, {
    required int offset,
    required int lowSeconds,
    required int highSeconds,
  }) => _mapStep(
    stepId,
    (d) => insertSpan(
      d,
      offset: offset,
      word: formatTimerRange(lowSeconds, highSeconds),
      span: TimerSpan(
        start: 0,
        end: 0,
        lowSeconds: lowSeconds,
        highSeconds: highSeconds,
      ),
    ),
  );

  @override
  void repointChip(String stepId, int index, List<String> refs) => _mapStep(
    stepId,
    (d) => switch (d.spans.elementAtOrNull(index)) {
      final RefSpan span => respan(
        d,
        index,
        span: span.copyWith(refs: refs),
        word: spanWord(d, index),
      ),
      _ => d,
    },
  );

  @override
  void renameChip(String stepId, int index, String word) => _mapStep(
    stepId,
    (d) => index < d.spans.length
        ? respan(d, index, span: d.spans[index], word: word)
        : d,
  );

  @override
  void setChipAmountRule(String stepId, int index, ChipAmountRule rule) =>
      _mapStep(
        stepId,
        (d) => switch (d.spans.elementAtOrNull(index)) {
          final RefSpan span => respan(
            d,
            index,
            span: span.copyWith(amountRule: rule),
            word: spanWord(d, index),
          ),
          _ => d,
        },
      );

  @override
  void setTimerSpan(String stepId, int index, int low, int high) => _mapStep(
    stepId,
    (d) => index < d.spans.length
        ? respan(
            d,
            index,
            span: TimerSpan(
              start: 0,
              end: 0,
              lowSeconds: low,
              highSeconds: high,
            ),
            word: formatTimerRange(low, high),
          )
        : d,
  );

  @override
  void removeChip(String stepId, int index) =>
      _mapStep(stepId, (d) => removeSpan(d, index));

  /// The revert: the chip keeps its ref and takes its printed word back,
  /// through the same rename door the sheet's Word field uses.
  @override
  void keepOldWord(ChipRelabel relabel) {
    renameChip(relabel.stepId, relabel.spanIndex, relabel.oldWord);
    controller.forgetRelabel(relabel);
  }

  @override
  void convertMethodToPlainText() {
    controller.clearRelabels();
    _set([
      for (final draft in methodDraft())
        MethodDraftStep(id: draft.id, text: draft.text),
    ]);
  }

  /// The chip picker's *＋ Add an ingredient to this recipe* is open here. A new
  /// line takes a flat index past the payload's last; nothing renumbers, so
  /// existing chips keep pointing where they did.
  @override
  bool get canAddLine => true;

  @override
  String? get addLineReason => null;

  /// The section a chip's *new* line lands in: the last one, which is where
  /// the list's own `＋ ingredient` puts it too.
  @override
  String ensureGroupId() => _now.sections.last.id;

  @override
  void addLineItem(
    String groupId,
    Ingredient ingredient, {
    double? quantity,
    UnitChoice? choice,
  }) => controller.addLine(
    groupId,
    name: ingredient.canonicalName,
    ingredientId: ingredient.id,
    quantity: quantity,
    unit: choice == null
        ? ingredient.defaultUnit.id
        : sheetChoiceUnit(choice: choice, unitPicked: true, currentUnit: null),
  );

  @override
  void addComponentLineItem(
    String groupId,
    SubRecipeTarget target, {
    double? quantity,
    Unit? unit,
    String? recipeMeasureId,
    RecipeMeasure? recipeMeasure,
    bool optional = false,
  }) {
    // A review line stores a unit id and has no column for a recipe's own word,
    // so one arriving here is refused out loud rather than written as whole
    // batches.
    if (recipeMeasureId != null) {
      throw UnsupportedError(
        'an import review line cannot be said in a recipe’s own word',
      );
    }
    controller.addLine(
      groupId,
      name: target.title,
      recipeId: target.id,
      quantity: quantity,
      unit: (unit ?? batches).id,
      optional: optional,
    );
  }
}
