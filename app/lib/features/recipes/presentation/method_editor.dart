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

import 'package:flutter/widgets.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:forui/forui.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

import '../../../core/theme/ansi_theme.dart';
import '../../../core/theme/ansi_tokens.dart';
import '../../../shared/method_step_text.dart';
import '../../ingredients/presentation/quantity_unit_sheet.dart';
import '../domain/method_draft.dart';
import '../domain/recipe.dart';
import 'component_quantity_sheet.dart';
import 'line_target_picker.dart';
import 'method_line_picker.dart';
import 'method_span_controller.dart';
import 'method_timer_sheet.dart';
import 'recipe_view_models.dart';

class MethodEditor extends StatelessWidget {
  const MethodEditor({
    required this.recipe,
    required this.notifier,
    super.key,
  });

  final Recipe recipe;
  final RecipeEditor notifier;

  @override
  Widget build(BuildContext context) {
    final steps = notifier.methodDraft();
    final lines = notifier.lineById();
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
            ],
          ),
        ),
        for (final (i, step) in steps.indexed)
          MethodStepCard(
            key: ValueKey(step.id),
            step: step,
            index: i,
            lastIndex: steps.length - 1,
            lineById: lines,
            recipe: recipe,
            notifier: notifier,
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
    super.key,
  });

  final MethodDraftStep step;
  final int index;
  final int lastIndex;
  final Map<String, LineItem> lineById;
  final Recipe recipe;
  final RecipeEditor notifier;

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
                child: Text('Step ${index + 1}', style: ansiLabel()),
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
            control: FTextFieldControl.managed(
              controller: controller,
              onChange: (v) => notifier.editStep(step.id, v.text),
            ),
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
    notifier.insertChip(
      step.id,
      offset: offset,
      word: word,
      refs: [lineId],
    );
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
