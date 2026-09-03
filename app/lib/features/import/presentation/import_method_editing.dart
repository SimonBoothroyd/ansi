/// The import review as a host for the editor v2 step cards (seam **D4**).
///
/// `reconciliation_view.dart` used to print *"Method is read-only in v1 —
/// editing lands later via the recipe's Edit route"* over a read-only fold.
/// The step cards shipped on 2026-09-02, so the notice had been false for a
/// day — and the review screen is the one screen most likely to need a method
/// fix, which made it the worst screen to leave read-only.
///
/// This adapter satisfies [MethodEditing] over the review's own state. It owns
/// no state itself: it derives the drafts from the preview recipe when nobody
/// has typed, and every mutator re-seats the whole list through
/// `ImportController.setMethodDraft`. That keeps the review's single source of
/// truth where it already was — the controller — and means a rebuild between
/// two keystrokes cannot lose one.
///
/// **Chips key on the preview's ids** (`previewLineId(i) == 'line-<i>'`), so
/// `MethodStepText`'s "Reads as" fold shows live amounts with no extra
/// plumbing, and `stepsFromDrafts` parses them back to line indexes at commit.
library;

import '../../../core/units/units.dart';
import '../../ingredients/domain/allowed_units.dart';
import '../../ingredients/domain/ingredient.dart';
import '../../recipes/domain/method_draft.dart';
import '../../recipes/domain/method_step.dart';
import '../../recipes/domain/recipe.dart';
import '../../recipes/presentation/method_editing.dart';
import '../domain/method_draft_bridge.dart';
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

  @override
  List<MethodDraftStep> methodDraft() =>
      state.editedSteps ?? draftsFromPreview(preview);

  @override
  Map<String, LineItem> lineById() => {
    for (final group in preview.groups)
      for (final item in group.items) item.id: item,
  };

  /// Always null at review: a re-match here re-points by line INDEX, so no
  /// chip can be orphaned by an identity change and there is nothing to
  /// notice.
  @override
  Substitution? substitution() => null;

  @override
  List<ChipRelabel> relabels() => const [];

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

  /// A counter rather than a uuid: the review is one screen with no
  /// persistence of its own, and a stable, readable id keeps the cards' keys
  /// legible in a widget test.
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

  /// Nothing to keep: [relabels] is always empty here.
  @override
  void keepOldWord(ChipRelabel relabel) {}

  @override
  void convertMethodToPlainText() => _set([
    for (final draft in methodDraft())
      MethodDraftStep(id: draft.id, text: draft.text),
  ]);

  /// The review screen offers THIS import's lines only (D4's scope cut), so
  /// the picker's add-a-line door is disabled with its reason and none of the
  /// three members below is reachable.
  @override
  bool get canAddLine => false;

  @override
  String? get addLineReason =>
      'at review, a chip can only point at a line this import already has';

  @override
  String ensureGroupId() => throw UnsupportedError(
    'the review screen mints no new lines — buildCommit walks the payload’s '
    'flat indexes, and a brand-new line has none',
  );

  @override
  void addLineItem(
    String groupId,
    Ingredient ingredient, {
    double? quantity,
    UnitChoice? choice,
  }) => throw UnsupportedError(
    'the review screen mints no new lines — see addLineReason',
  );

  @override
  void addComponentLineItem(
    String groupId,
    SubRecipeTarget target, {
    double? quantity,
    Unit? unit,
  }) => throw UnsupportedError(
    'the review screen mints no new lines — see addLineReason',
  );
}
