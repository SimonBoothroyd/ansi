/// The recipe editor's METHOD section: one card per step.
///
/// A step's prose is an editable sentence; a chip is a highlighted word in it,
/// backed by a ref to a recipe line. The document is a plain String plus a side
/// table of ranges (`method_draft.dart`), painted by [MethodSpanController].
/// The focused card shows the insert toolbar and a "Reads as" preview rendered
/// by [MethodStepText]. Cards edit through [MethodEditing], so the import
/// review screen uses the same cards over its own draft.
library;

import 'dart:async';

import 'package:flutter/material.dart'
    show
        AdaptiveTextSelectionToolbar,
        ContextMenuButtonItem,
        ContextMenuButtonType;
import 'package:flutter/widgets.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:forui/forui.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

import '../../../core/theme/ansi_theme.dart';
import '../../../core/theme/ansi_tokens.dart';
import '../../../core/units/number_format.dart';
import '../../../core/words.dart';
import '../../../shared/ansi_modals.dart';
import '../../../shared/ansi_more_trigger.dart';
import '../../../shared/method_step_text.dart';
import '../../../shared/was_word_line.dart';
import '../../ingredients/presentation/quantity_unit_sheet.dart';
import '../domain/line_display.dart';
import '../domain/method_draft.dart';
import '../domain/recipe.dart';
import 'component_quantity_sheet.dart';
import 'line_target_picker.dart';
import 'method_chip_sheet.dart';
import 'method_editing.dart';
import 'method_line_picker.dart';
import 'method_span_controller.dart';
import 'method_timer_sheet.dart';

class MethodEditor extends StatelessWidget {
  const MethodEditor({
    required this.recipe,
    required this.notifier,
    this.onStepFocus,
    this.ringsCaretChip = false,
    super.key,
  });

  final Recipe recipe;
  final MethodEditing notifier;

  /// Told which step has the caret, so a wide host can light the lines its
  /// chips point at. Null on the phone and at review.
  final void Function(String stepId, {required bool focused})? onStepFocus;

  /// See [MethodSpanController.ringsCaretChip].
  final bool ringsCaretChip;

  @override
  Widget build(BuildContext context) {
    final steps = notifier.methodDraft();
    final lines = notifier.lineById();
    final substitution = notifier.substitution();
    final relabels = notifier.relabels();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        EditorSectionHead(
          label: 'METHOD',
          count: '${steps.length}',
          trailing: FPopoverMenu(
            // `menuBuilder`, not `menu`: the item must dismiss its menu before
            // the confirm opens over it.
            menuBuilder: (_, controller, _) => [
              FItemGroup(
                children: [
                  FItem(
                    prefix: const Icon(FLucideIcons.type),
                    title: const Text('Convert to plain text'),
                    onPress: () {
                      unawaited(controller.hide());
                      unawaited(_confirmFlatten(context, notifier));
                    },
                  ),
                ],
              ),
            ],
            builder: (_, controller, _) => AnsiMoreTrigger(
              onTap: controller.toggle,
              size: 16,
              compact: true,
            ),
          ),
        ),
        if (substitution != null) _SubstitutionNotice(substitution),
        for (final (i, step) in steps.indexed)
          MethodStepCard(
            key: ValueKey(step.id),
            step: step,
            index: i,
            lastIndex: steps.length - 1,
            lineById: lines,
            recipe: recipe,
            notifier: notifier,
            flagged: substitution?.stepIds.contains(step.id) ?? false,
            onFocusChange: onStepFocus,
            ringsCaretChip: ringsCaretChip,
            relabels: [
              for (final r in relabels)
                if (r.stepId == step.id) r,
            ],
          ),
        const SizedBox(height: 4),
        FButton(
          variant: FButtonVariant.outline,
          prefix: const Icon(FLucideIcons.plus),
          onPress: notifier.addMethodStep,
          child: const Text('Add a step'),
        ),
      ],
    );
  }
}

/// An editor section's heading: the micro-label, the count, and the section's
/// door at the right. Used by METHOD and, wide, by the ingredients column.
class EditorSectionHead extends StatelessWidget {
  const EditorSectionHead({
    required this.label,
    this.count,
    this.trailing,
    super.key,
  });

  final String label;

  /// What the section holds, in the mono voice — `6`, `7 lines · 2 groups`.
  final String? count;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 8),
    child: ConstrainedBox(
      // One fixed height, so a head with a door and one without align across
      // the two wide columns.
      constraints: const BoxConstraints(minHeight: kEditorSectionHeadHeight),
      child: Row(
        children: [
          Text(label, style: ansiLabel()),
          if (count case final count?) ...[
            const SizedBox(width: 8),
            Text(count, style: ansiMono(size: 11, color: AnsiColors.muted)),
          ],
          const Spacer(),
          if (trailing case final trailing?) trailing,
        ],
      ),
    ),
  );
}

/// See [EditorSectionHead] — the `⋯` door's own height.
const double kEditorSectionHeadHeight = 40;

/// Drops focus when a step's sheet closes. The tap that opens a chip's sheet
/// also requests focus for the field, and the navigator restores it on the way
/// out, raising the keyboard. Focus is dropped twice because a focus change
/// applies in a microtask that can land either side of the next frame.
void _keepTheKeyboardDown(FocusNode node) {
  node.unfocus();
  WidgetsBinding.instance.addPostFrameCallback((_) => node.unfocus());
}

/// One step card: the sentence, its reorder/delete controls and, while focused,
/// the insert toolbar and the "Reads as" preview.
class MethodStepCard extends HookConsumerWidget {
  const MethodStepCard({
    required this.step,
    required this.index,
    required this.lastIndex,
    required this.lineById,
    required this.recipe,
    required this.notifier,
    this.flagged = false,
    this.relabels = const [],
    this.onFocusChange,
    this.ringsCaretChip = false,
    super.key,
  });

  final MethodDraftStep step;
  final int index;
  final int lastIndex;
  final Map<String, LineItem> lineById;
  final Recipe recipe;
  final MethodEditing notifier;

  /// Whether a line's identity change moved one of this step's chips this
  /// sitting (the amber check).
  final bool flagged;

  /// Each moved chip's previous word, so "keep the old word" is one tap.
  final List<ChipRelabel> relabels;

  /// See [MethodEditor.onStepFocus]. Called from the focus node's listener, not
  /// from build.
  final void Function(String stepId, {required bool focused})? onFocusChange;

  /// See [MethodSpanController.ringsCaretChip].
  final bool ringsCaretChip;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final controller = useMemoized(() => MethodSpanController(step), const []);
    useEffect(() => controller.dispose, const []);
    useEffect(() {
      controller.sync(step);
      return null;
    }, [step]);
    controller.ringsCaretChip = ringsCaretChip;

    final focusNode = useFocusNode();
    useListenable(focusNode);
    final focused = focusNode.hasFocus;
    // A ref, so the listener subscribes once and still calls the latest
    // callback.
    final report = useRef(onFocusChange)..value = onFocusChange;
    final stepId = step.id;
    useEffect(() {
      void tell() => report.value?.call(stepId, focused: focusNode.hasFocus);
      focusNode.addListener(tell);
      return () => focusNode.removeListener(tell);
    }, [focusNode, stepId]);

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AnsiColors.paper,
        border: Border.all(color: AnsiColors.line),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  flagged ? 'Step ${index + 1} · check' : 'Step ${index + 1}',
                  style: ansiLabel(
                    color: flagged ? AnsiColors.aging : AnsiColors.muted,
                  ),
                ),
              ),
              _CardAction(
                icon: FLucideIcons.chevronUp,
                semantics: 'Move step ${index + 1} up',
                onPress: index == 0
                    ? null
                    : () => notifier.moveMethodStep(step.id, -1),
              ),
              _CardAction(
                icon: FLucideIcons.chevronDown,
                semantics: 'Move step ${index + 1} down',
                onPress: index == lastIndex
                    ? null
                    : () => notifier.moveMethodStep(step.id, 1),
              ),
              _CardAction(
                icon: FLucideIcons.trash2,
                semantics: 'Delete step ${index + 1}',
                onPress: () => notifier.removeMethodStep(step.id),
              ),
            ],
          ),
          const SizedBox(height: 6),
          FTextField.multiline(
            hint: 'What happens in this step?',
            focusNode: focusNode,
            minLines: 1,
            // onTap fires after the tap has set the selection, so the span
            // lookup is exact; onTapAlwaysCalled lets a second tap re-open the
            // same chip.
            onTap: () => _openSpanSheet(context, controller, focusNode),
            onTapAlwaysCalled: true,
            // The card's context, not the toolbar's: `hideToolbar` unmounts
            // that one before the sheet opens.
            contextMenuBuilder: (_, state) =>
                _selectionToolbar(context, state, controller, focusNode),
            control: FTextFieldControl.managed(
              controller: controller,
              // Forui also calls this for text pushed in programmatically (a
              // chip renamed in its sheet). `applyEdit` would drop every span
              // that edit overlaps, so only a real keystroke is let through.
              onChange: (v) {
                if (controller.isSyncing) return;
                notifier.editStep(step.id, v.text);
              },
            ),
          ),
          for (final relabel in relabels)
            WasWordLine(
              oldWord: relabel.oldWord,
              onKeep: () => notifier.keepOldWord(relabel),
            ),
          if (focused) ...[
            const SizedBox(height: 8),
            Row(
              children: [
                FButton(
                  variant: FButtonVariant.secondary,
                  size: FButtonSizeVariant.sm,
                  prefix: const Icon(FLucideIcons.plus),
                  onPress: () => _insertIngredient(context, controller),
                  child: const Text('ingredient'),
                ),
                const SizedBox(width: 8),
                FButton(
                  variant: FButtonVariant.secondary,
                  size: FButtonSizeVariant.sm,
                  prefix: const Icon(FLucideIcons.timer),
                  onPress: () => _insertTimer(context, controller),
                  child: const Text('timer'),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Text('READS AS', style: ansiLabel()),
            const SizedBox(height: 4),
            MethodStepText(
              step: toTokens(step),
              lineById: lineById,
              textSize: 14,
            ),
          ],
        ],
      ),
    );
  }

  /// The platform selection toolbar with two extra items placed right after
  /// Copy, so iOS does not paginate them away.
  Widget _selectionToolbar(
    BuildContext context,
    EditableTextState state,
    MethodSpanController controller,
    FocusNode focusNode,
  ) {
    final items = [...state.contextMenuButtonItems];
    // Captured before the toolbar hides and the field loses focus, or the sheet
    // gets an empty range.
    final selection = controller.selection;
    if (selection.isValid && !selection.isCollapsed) {
      final copy = items.indexWhere(
        (i) => i.type == ContextMenuButtonType.copy,
      );
      items.insertAll(copy < 0 ? 0 : copy + 1, [
        ContextMenuButtonItem(
          label: 'To ingredient',
          onPressed: () {
            state.hideToolbar();
            unawaited(
              _selectionToIngredient(context, controller, selection, focusNode),
            );
          },
        ),
        ContextMenuButtonItem(
          label: 'To timer',
          onPressed: () {
            state.hideToolbar();
            unawaited(_selectionToTimer(context, selection, focusNode));
          },
        ),
      ]);
    }
    return AdaptiveTextSelectionToolbar.buttonItems(
      anchors: state.contextMenuAnchors,
      buttonItems: items,
    );
  }

  /// Turns the selected words into a chip verbatim; no text changes.
  Future<void> _selectionToIngredient(
    BuildContext context,
    MethodSpanController controller,
    TextSelection selection,
    FocusNode focusNode,
  ) async {
    final word = step.text.substring(selection.start, selection.end);
    final lineId = await pickOrAddLine(
      context,
      recipe: recipe,
      notifier: notifier,
      canAddLine: notifier.canAddLine,
      addLineReason: notifier.addLineReason,
      query: word,
      alreadyInStep: {
        for (final span in step.spans)
          if (span is RefSpan) ...span.refs,
      },
    );
    _keepTheKeyboardDown(focusNode);
    if (lineId == null) return;
    notifier.chipRange(
      step.id,
      start: selection.start,
      end: selection.end,
      refs: [lineId],
    );
    // No text changed, so the selection must be collapsed by hand: a live
    // selection swallows the next tap inside it, which is the tap that opens
    // the new chip.
    controller.selection = TextSelection.collapsed(offset: selection.end);
  }

  /// Parses only the selected substring and seeds the timer stepper with it for
  /// confirmation. A parse failure opens the stepper empty. Not render-time
  /// matching (ADR-0004): it runs once, on text the user selected.
  Future<void> _selectionToTimer(
    BuildContext context,
    TextSelection selection,
    FocusNode focusNode,
  ) async {
    final parsed = parseSelectedDuration(
      step.text.substring(selection.start, selection.end),
    );
    final result = await showMethodTimerSheet(
      context,
      lowSeconds: parsed?.$1,
      highSeconds: parsed?.$2,
      prosePrefix: step.text.substring(0, selection.start),
      proseSuffix: step.text.substring(selection.end),
    );
    _keepTheKeyboardDown(focusNode);
    if (result is! TimerSet) return;
    notifier.timerRange(
      step.id,
      start: selection.start,
      end: selection.end,
      lowSeconds: result.lowSeconds,
      highSeconds: result.highSeconds,
    );
  }

  /// A tap inside a chip opens its sheet; any other tap places the caret.
  Future<void> _openSpanSheet(
    BuildContext context,
    MethodSpanController controller,
    FocusNode focusNode,
  ) async {
    final selection = controller.selection;
    if (!selection.isCollapsed) return;
    // A caret at a chip's closing edge is a tap on the chip (iOS snaps to the
    // word's end) when the affinity is upstream, and a tap on the following
    // prose when downstream.
    final offset = selection.baseOffset;
    final index =
        spanAt(step, offset) ??
        (selection.affinity == TextAffinity.upstream
            ? spanEndingAt(step, offset)
            : null);
    if (index == null) return;
    switch (step.spans[index]) {
      case RefSpan(:final refs, :final amountRule):
        await showMethodChipSheet(
          context,
          initial: (
            refs: refs,
            word: spanWord(step, index),
            amountRule: amountRule,
          ),
          describe: _describeRefs,
          pickLine: () => pickOrAddLine(
            context,
            recipe: recipe,
            notifier: notifier,
            canAddLine: notifier.canAddLine,
            addLineReason: notifier.addLineReason,
            query: spanWord(step, index),
          ),
          onChanged: (edit) => notifier
            ..repointChip(step.id, index, edit.refs)
            ..renameChip(step.id, index, edit.word)
            ..setChipAmountRule(step.id, index, edit.amountRule),
          onRemove: () => notifier.removeChip(step.id, index),
        );
        _keepTheKeyboardDown(focusNode);
      case TimerSpan(:final lowSeconds, :final highSeconds):
        final span = step.spans[index];
        final result = await showMethodTimerSheet(
          context,
          lowSeconds: lowSeconds,
          highSeconds: highSeconds,
          removable: true,
          prosePrefix: step.text.substring(0, span.start),
          proseSuffix: step.text.substring(span.end),
        );
        _keepTheKeyboardDown(focusNode);
        switch (result) {
          case TimerSet(:final lowSeconds, :final highSeconds):
            notifier.setTimerSpan(step.id, index, lowSeconds, highSeconds);
          case TimerRemoved():
            notifier.removeChip(step.id, index);
          case null:
            break;
        }
    }
  }

  /// How the lines behind a chip read in its sheet: the name and live amount,
  /// or a note when the ref no longer resolves.
  String _describeRefs(List<String> refs) {
    final names = [
      for (final ref in refs)
        if (lineById[ref] case final line?)
          _lineSummary(line)
        else
          'a line this recipe no longer has',
    ];
    return names.isEmpty ? 'nothing yet' : names.join(' · ');
  }

  String _lineSummary(LineItem line) {
    final quantity = line.quantity;
    final measure = line.measure;
    final word = recipeMeasureOfLine(line);
    final unit = line.unit;
    final String amount;
    if (word != null) {
      amount = measuredAmountText(quantity, word.label);
    } else if (quantity == null) {
      // A line whose word has gone has nothing to name here at all.
      amount = unit?.label ?? '';
    } else if (measure != null) {
      amount = '${formatAmount(quantity)} ${measure.label}';
    } else if (unit == null) {
      amount = formatAmount(quantity);
    } else {
      amount = '${formatAmountIn(quantity, unit)} ${unit.label}';
    }
    return '${line.ingredientName} · $amount';
  }

  /// Picks a line and inserts its name at the caret as a chip, cased for its
  /// position ([chipWord]).
  Future<void> _insertIngredient(
    BuildContext context,
    MethodSpanController controller,
  ) async {
    final offset = _caret(controller);
    final lineId = await pickOrAddLine(
      context,
      recipe: recipe,
      notifier: notifier,
      canAddLine: notifier.canAddLine,
      addLineReason: notifier.addLineReason,
      alreadyInStep: {
        for (final span in step.spans)
          if (span is RefSpan) ...span.refs,
      },
    );
    if (lineId == null) return;
    final name = notifier.lineById()[lineId]?.ingredientName ?? '';
    if (name.isEmpty) return;
    final word = chipWord(name, textBefore: step.text.substring(0, offset));
    notifier.insertChip(step.id, offset: offset, word: word, refs: [lineId]);
  }

  Future<void> _insertTimer(
    BuildContext context,
    MethodSpanController controller,
  ) async {
    final offset = _caret(controller);
    final result = await showMethodTimerSheet(
      context,
      prosePrefix: step.text.substring(0, offset),
      proseSuffix: step.text.substring(offset),
    );
    if (result is! TimerSet) return;
    notifier.insertTimer(
      step.id,
      offset: offset,
      lowSeconds: result.lowSeconds,
      highSeconds: result.highSeconds,
    );
  }

  int _caret(MethodSpanController controller) {
    final offset = controller.selection.baseOffset;
    return offset < 0 ? step.text.length : offset.clamp(0, step.text.length);
  }
}

/// Opens the line picker over this recipe's lines and returns the chosen line's
/// id, running [showLineTargetPicker] and the quantity sheet when the add
/// footer is taken. [canAddLine] false (the import review) disables that footer
/// with its reason.
Future<String?> pickOrAddLine(
  BuildContext context, {
  required Recipe recipe,
  required MethodEditing notifier,
  String query = '',
  Set<String> alreadyInStep = const {},
  bool canAddLine = true,
  String? addLineReason,
}) async {
  final pick = await showMethodLinePicker(
    context,
    // From the draft, so a line added a moment ago is pickable immediately.
    lines: notifier.lineById().values.toList(),
    query: query,
    alreadyInStep: alreadyInStep,
    canAddLine: canAddLine,
    addLineReason: addLineReason,
  );
  if (pick == null || !context.mounted) return null;
  if (pick is PickedRecipeLine) return pick.lineId;

  final picked = await showLineTargetPicker(
    context,
    editingRecipeId: recipe.id,
  );
  if (picked == null || !context.mounted) return null;
  final before = notifier.lineById().keys.toSet();
  final groupId = notifier.ensureGroupId();
  switch (picked) {
    case PickedIngredient(:final ingredient):
      final result = await showQuantityUnitSheet(
        context,
        ingredient: ingredient,
      );
      notifier.addLineItem(
        groupId,
        ingredient,
        quantity: result is QuantitySaved ? result.quantity : null,
        choice: result is QuantitySaved ? result.choice : null,
      );
    case PickedSubRecipe(:final target):
      final result = await showComponentQuantitySheet(
        context,
        target: target,
        mayCoinWords: true,
      );
      notifier.addComponentLineItem(
        groupId,
        target,
        quantity: result?.quantity,
        unit: result?.unit,
        recipeMeasureId: result?.recipeMeasureId,
        recipeMeasure: result?.measure,
        optional: result?.optional ?? false,
      );
  }
  for (final id in notifier.lineById().keys) {
    if (!before.contains(id)) return id;
  }
  return null;
}

/// Confirms converting the method to plain text. It counts the chips that go;
/// [flattenMethod] emits each step's prose unchanged.
Future<void> _confirmFlatten(
  BuildContext context,
  MethodEditing notifier,
) async {
  final counts = notifier.methodLinkCounts();
  if (counts.chips == 0 && counts.timers == 0) return;
  final confirmed = await askAnsi(
    context,
    title: 'Convert the method to plain text?',
    body:
        '${counts.chips} ingredient '
        '${plural(counts.chips, 'chip')} and '
        '${counts.timers} ${plural(counts.timers, 'timer')} '
        'become ordinary words. Every sentence reads exactly the same — '
        'only the links go.',
    caveatLabel: 'This can’t be undone here',
    caveat:
        'Chips are written at import, or added one at a time from a '
        'selection. Nothing on the phone can re-chip a method — matching '
        'is online-only, and only at import.',
    confirm: 'Convert to plain text',
  );
  if (confirmed) notifier.convertMethodToPlainText();
}

/// "2 steps mentioned the sausage — their chips now read meatballs." A chip's
/// label follows the line it points at, so an identity change replaces the
/// chip's word, visibly and revertibly. The prose around the chip is flagged,
/// never rewritten.
class _SubstitutionNotice extends StatelessWidget {
  const _SubstitutionNotice(this.substitution);

  final Substitution substitution;

  @override
  Widget build(BuildContext context) {
    final n = substitution.stepIds.length;
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AnsiColors.paper,
        border: Border.all(color: AnsiColors.aging),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(
            FLucideIcons.triangleAlert,
            size: 14,
            color: AnsiColors.aging,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '$n '
                  '${plural(n, 'step mentioned', plural: 'steps mentioned')} '
                  '${substitution.oldName}',
                  style: ansiSans(size: 14, weight: FontWeight.w600),
                ),
                const SizedBox(height: 4),
                Text(
                  'Their chips now read ${substitution.newName}. The words '
                  'around them may need a look — we don’t rewrite your '
                  'sentences.',
                  style: ansiMono(
                    size: 11,
                    color: AnsiColors.muted,
                  ).copyWith(height: 1.5),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _CardAction extends StatelessWidget {
  const _CardAction({
    required this.icon,
    required this.semantics,
    required this.onPress,
  });

  final IconData icon;
  final String semantics;
  final VoidCallback? onPress;

  @override
  Widget build(BuildContext context) => Semantics(
    label: semantics,
    button: true,
    child: FButton.icon(
      variant: FButtonVariant.ghost,
      size: FButtonSizeVariant.sm,
      onPress: onPress,
      child: Icon(icon, size: 16),
    ),
  );
}
