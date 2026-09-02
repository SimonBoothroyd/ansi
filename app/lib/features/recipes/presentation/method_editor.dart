/// The METHOD slot of the recipe editor — one card per step (0022 D1, design
/// board frame a).
///
/// A step's prose is a real editable sentence and a chip is a **highlighted
/// word inside it**, backed by a ref to a recipe line. That works because a
/// ref's label already IS the word at that position, so the editor's document
/// is a plain String plus a side table of ranges (`method_draft.dart`) and the
/// chip skin is painted by [MethodSpanController].
///
/// The card that has focus grows two things: the insert toolbar, and a
/// **"Reads as"** preview rendered by the shipped `MethodStepText` — the same
/// fold the recipe page runs, so the live amounts are visible while you write
/// and the editor never has to fake a number.
///
/// This replaces the read-only notice an imported method used to get. Nothing
/// is re-tokenized, re-matched or re-fetched on open: the refs are the
/// `line_item_id`s the import committed.
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
import '../../../shared/ansi_modals.dart';
import '../../../shared/method_step_text.dart';
import '../../ingredients/presentation/quantity_unit_sheet.dart';
import '../domain/method_draft.dart';
import '../domain/method_step.dart';
import '../domain/recipe.dart';
import 'component_quantity_sheet.dart';
import 'line_target_picker.dart';
import 'method_chip_sheet.dart';
import 'method_line_picker.dart';
import 'method_span_controller.dart';
import 'method_timer_sheet.dart';
import 'recipe_view_models.dart';

class MethodEditor extends StatelessWidget {
  const MethodEditor({required this.recipe, required this.notifier, super.key});

  final Recipe recipe;
  final RecipeEditor notifier;

  @override
  Widget build(BuildContext context) {
    final steps = notifier.methodDraft();
    final lines = notifier.lineById();
    final substitution = notifier.substitution();
    final relabels = notifier.relabels();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Row(
            children: [
              Text('METHOD', style: ansiLabel()),
              const SizedBox(width: 8),
              Text(
                '${steps.length}',
                style: ansiMono(size: 11, color: AnsiColors.muted),
              ),
              const Spacer(),
              FPopoverMenu(
                // `menuBuilder`, not `menu`: the item has to dismiss its own
                // menu before the confirm opens over it.
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
                builder: (_, controller, _) => FButton.icon(
                  variant: FButtonVariant.ghost,
                  size: FButtonSizeVariant.sm,
                  onPress: controller.toggle,
                  child: const Icon(FLucideIcons.ellipsis, size: 16),
                ),
              ),
            ],
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

/// One step card: the sentence, its reorder/delete controls, and — while it
/// has focus — the insert toolbar and the "Reads as" preview.
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
    super.key,
  });

  final MethodDraftStep step;
  final int index;
  final int lastIndex;
  final Map<String, LineItem> lineById;
  final Recipe recipe;
  final RecipeEditor notifier;

  /// Whether a line's identity change moved one of this step's chips this
  /// sitting — the amber *check* in the card's header (D3).
  final bool flagged;

  /// What each moved chip used to say, so "keep the old word" is one tap.
  final List<ChipRelabel> relabels;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final controller = useMemoized(() => MethodSpanController(step), const []);
    useEffect(() => controller.dispose, const []);
    useEffect(() {
      controller.sync(step);
      return null;
    }, [step]);

    final focusNode = useFocusNode();
    useListenable(focusNode);
    final focused = focusNode.hasFocus;

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
            // onTap fires AFTER the tap has set the selection, so the span
            // lookup is exact and needs no hit-testing of its own;
            // onTapAlwaysCalled so a second tap on the same chip re-opens it.
            onTap: () => _openSpanSheet(context, controller),
            onTapAlwaysCalled: true,
            // The CARD's context, not the toolbar's: the toolbar's is
            // unmounted by `hideToolbar` before the sheet ever opens.
            contextMenuBuilder: (_, state) =>
                _selectionToolbar(context, state, controller),
            control: FTextFieldControl.managed(
              controller: controller,
              onChange: (v) => notifier.editStep(step.id, v.text),
            ),
          ),
          for (final relabel in relabels)
            _KeepTheOldWord(
              relabel: relabel,
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

  /// **Select the text, then say what it is** (D2b) — the writing door.
  ///
  /// The platform's own toolbar gains two items, placed immediately after
  /// **Copy**: iOS paginates after roughly four, and ours must not be the ones
  /// behind the `▸`. This is the shipped path, not a Material intrusion —
  /// Forui's own default builder is already
  /// `AdaptiveTextSelectionToolbar.editableText`, and we hand it one more
  /// `ContextMenuButtonItem` each.
  Widget _selectionToolbar(
    BuildContext context,
    EditableTextState state,
    MethodSpanController controller,
  ) {
    final items = [...state.contextMenuButtonItems];
    // Captured BEFORE the toolbar hides and the field loses focus: the sheet
    // that opens next would otherwise be handed an empty range.
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
            unawaited(_selectionToIngredient(context, selection));
          },
        ),
        ContextMenuButtonItem(
          label: 'To timer',
          onPressed: () {
            state.hideToolbar();
            unawaited(_selectionToTimer(context, selection));
          },
        ),
      ]);
    }
    return AdaptiveTextSelectionToolbar.buttonItems(
      anchors: state.contextMenuAnchors,
      buttonItems: items,
    );
  }

  /// The selected words become the chip's word **verbatim** — nothing is
  /// inserted, deleted or rewritten. Selection → chip is a pure annotation of
  /// text the user already wrote, which is the whole reason it reads as
  /// obvious.
  Future<void> _selectionToIngredient(
    BuildContext context,
    TextSelection selection,
  ) async {
    final word = step.text.substring(selection.start, selection.end);
    final lineId = await pickOrAddLine(
      context,
      recipe: recipe,
      notifier: notifier,
      query: word,
      alreadyInStep: {
        for (final span in step.spans)
          if (span is RefSpan) ...span.refs,
      },
    );
    if (lineId == null) return;
    notifier.chipRange(
      step.id,
      start: selection.start,
      end: selection.end,
      refs: [lineId],
    );
  }

  /// Parses ONLY the selected substring, and seeds the stepper with it.
  ///
  /// This is not render-time matching (ADR-0004). Nothing scans prose on its
  /// own: it runs once, at edit time, on a string the user deliberately
  /// pointed at and asked us to read, and its output is shown in a stepper for
  /// confirmation before a single token is written. A failure opens the
  /// stepper EMPTY rather than guessing.
  Future<void> _selectionToTimer(
    BuildContext context,
    TextSelection selection,
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
    if (result is! TimerSet) return;
    notifier.timerRange(
      step.id,
      start: selection.start,
      end: selection.end,
      lowSeconds: result.lowSeconds,
      highSeconds: result.highSeconds,
    );
  }

  /// A tap inside a chip opens its sheet; a tap anywhere else is an ordinary
  /// caret placement. A drag-select is not a tap.
  Future<void> _openSpanSheet(
    BuildContext context,
    MethodSpanController controller,
  ) async {
    final selection = controller.selection;
    if (!selection.isCollapsed) return;
    final index = spanAt(step, selection.baseOffset);
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
            query: spanWord(step, index),
          ),
          onChanged: (edit) => notifier
            ..repointChip(step.id, index, edit.refs)
            ..renameChip(step.id, index, edit.word)
            ..setChipAmountRule(step.id, index, edit.amountRule),
          onRemove: () => notifier.removeChip(step.id, index),
        );
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

  /// How the lines behind a chip read in its sheet — the name and the live
  /// amount, or the honest note when the ref no longer resolves.
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
    final amount = line.quantity == null
        ? line.unit.label
        : '${formatNumber(line.quantity!)} '
              '${line.measure?.label ?? line.unit.label}';
    return '${line.ingredientName} · $amount';
  }

  /// The no-selection door: pick a line, and its name goes in at the caret as
  /// a chip. Renaming it to the printed word is the chip sheet's Word field.
  Future<void> _insertIngredient(
    BuildContext context,
    MethodSpanController controller,
  ) async {
    final offset = _caret(controller);
    final lineId = await pickOrAddLine(
      context,
      recipe: recipe,
      notifier: notifier,
      alreadyInStep: {
        for (final span in step.spans)
          if (span is RefSpan) ...span.refs,
      },
    );
    if (lineId == null) return;
    final word = notifier.lineById()[lineId]?.ingredientName ?? '';
    if (word.isEmpty) return;
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

/// Opens the line picker over this recipe's own lines and returns the id of
/// the line the chip should point at — running the shipped
/// `showLineTargetPicker` → quantity-sheet chain when the footer is taken, so
/// adding an ingredient and chipping it is ONE act.
Future<String?> pickOrAddLine(
  BuildContext context, {
  required Recipe recipe,
  required RecipeEditor notifier,
  String query = '',
  Set<String> alreadyInStep = const {},
}) async {
  final pick = await showMethodLinePicker(
    context,
    // From the draft, so a line added a moment ago is pickable immediately.
    lines: notifier.lineById().values.toList(),
    query: query,
    alreadyInStep: alreadyInStep,
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
      final result = await showComponentQuantitySheet(context, target: target);
      notifier.addComponentLineItem(
        groupId,
        target,
        quantity: result?.quantity,
        unit: result?.unit,
      );
  }
  for (final id in notifier.lineById().keys) {
    if (!before.contains(id)) return id;
  }
  return null;
}

/// D5's confirm (design board frame g). It counts what dies and promises what
/// does not: `flattenMethod` emits each step's own prose, byte-identical to
/// what the card was already showing, so **no sentence changes**.
///
/// It lives in the METHOD header's ⋯, not behind a red button: converting is
/// a legitimate choice for a badly-tokenized import, not a mistake to be
/// guarded against.
Future<void> _confirmFlatten(
  BuildContext context,
  RecipeEditor notifier,
) async {
  final counts = notifier.methodLinkCounts();
  if (counts.chips == 0 && counts.timers == 0) return;
  final confirmed = await showAnsiDialog<bool>(
    context: context,
    builder: (dialogContext, style, animation) => FDialog(
      title: Text(
        'Convert the method to plain text?',
        style: ansiSerif(size: 18),
      ),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            '${counts.chips} ingredient '
            '${counts.chips == 1 ? 'chip' : 'chips'} and '
            '${counts.timers} ${counts.timers == 1 ? 'timer' : 'timers'} '
            'become ordinary words. Every sentence reads exactly the same — '
            'only the links go.',
            style: ansiSans(size: 14, color: AnsiColors.muted),
          ),
          const SizedBox(height: 12),
          Text('This can’t be undone here', style: ansiLabel()),
          const SizedBox(height: 4),
          Text(
            'Chips are written at import, or added one at a time from a '
            'selection. Nothing on the phone can re-chip a method — matching '
            'is online-only, and only at import.',
            style: ansiMono(
              size: 11,
              color: AnsiColors.muted,
            ).copyWith(height: 1.5),
          ),
        ],
      ),
      actions: [
        FButton(
          variant: FButtonVariant.outline,
          onPress: () => Navigator.of(dialogContext).pop(false),
          child: const Text('Cancel'),
        ),
        FButton(
          onPress: () => Navigator.of(dialogContext).pop(true),
          child: const Text('Convert to plain text'),
        ),
      ],
    ),
  );
  if (confirmed ?? false) notifier.convertMethodToPlainText();
}

/// *"2 steps mentioned the sausage — their chips now read meatballs."*
///
/// The invariant behind it: **a chip never names something the recipe does not
/// contain.** Prose is authored, but a chip's label is data about what it
/// points at, so an identity change retires the printed word — visibly, and
/// revertibly. The words AROUND the chip are yours: "casings removed" is
/// flagged, never rewritten.
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
                  '$n ${n == 1 ? 'step mentioned' : 'steps mentioned'} '
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

/// The one-tap revert, on the card whose chip moved. It calls the same
/// [RecipeEditor.renameChip] the chip sheet's Word field calls — one place
/// changes what a chip says.
class _KeepTheOldWord extends StatelessWidget {
  const _KeepTheOldWord({required this.relabel, required this.onKeep});

  final ChipRelabel relabel;
  final VoidCallback onKeep;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(top: 6),
    child: Row(
      children: [
        Text(
          'was “${relabel.oldWord}”',
          style: ansiMono(size: 11, color: AnsiColors.aging),
        ),
        const SizedBox(width: 8),
        FButton(
          variant: FButtonVariant.ghost,
          size: FButtonSizeVariant.sm,
          onPress: onKeep,
          child: const Text('keep the old word'),
        ),
      ],
    ),
  );
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
