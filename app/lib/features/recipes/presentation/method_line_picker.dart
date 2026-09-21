/// The chip's line picker: [PickerShell] over this recipe's own lines, not the
/// vocabulary. Search is [prematchLines], a fixed word-prefix over a few dozen
/// rows (not matching in ADR-0004's sense). The footer adds a new line through
/// `showLineTargetPicker` and the quantity sheet, and the chip points at it.
library;

import 'package:flutter/widgets.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:forui/forui.dart';

import '../../../core/theme/ansi_theme.dart';
import '../../../core/theme/ansi_tokens.dart';
import '../../../shared/ansi_modals.dart';
import '../../../shared/format.dart';
import '../../../shared/picker_shell.dart';
import '../domain/line_display.dart';
import '../domain/method_draft.dart';
import '../domain/recipe.dart';
import 'recipe_chip.dart';

/// What the picker resolved to.
sealed class MethodLinePick {
  const MethodLinePick();
}

/// Point the chip at this line of the recipe.
final class PickedRecipeLine extends MethodLinePick {
  const PickedRecipeLine(this.lineId);

  final String lineId;
}

/// Run the shipped add-a-line chain, then chip whatever it lands.
final class AddRecipeLine extends MethodLinePick {
  const AddRecipeLine();
}

/// Opens the picker over [lines], seeded with [query] (the selected words).
/// [canAddLine] false disables the footer's add-a-line door and shows why; the
/// import review offers only its own lines.
Future<MethodLinePick?> showMethodLinePicker(
  BuildContext context, {
  required List<LineItem> lines,
  String query = '',
  Set<String> alreadyInStep = const {},
  bool canAddLine = true,
  String? addLineReason,
}) => showAnsiSheet<MethodLinePick>(
  context: context,
  builder: (_) => _MethodLinePickerSheet(
    lines: lines,
    initialQuery: query,
    alreadyInStep: alreadyInStep,
    canAddLine: canAddLine,
    addLineReason: addLineReason,
  ),
);

class _MethodLinePickerSheet extends HookWidget {
  const _MethodLinePickerSheet({
    required this.lines,
    required this.initialQuery,
    required this.alreadyInStep,
    required this.canAddLine,
    required this.addLineReason,
  });

  final List<LineItem> lines;
  final String initialQuery;

  /// Lines this step already chips — drawn with a tick, still pickable.
  final Set<String> alreadyInStep;

  final bool canAddLine;
  final String? addLineReason;

  @override
  Widget build(BuildContext context) {
    final query = useState(initialQuery);
    final q = query.value.trim();
    // An empty query offers the whole short list.
    final matched = q.isEmpty ? lines : prematchLines(lines, q);
    final shown = matched.isEmpty ? lines : matched;

    return PickerShell(
      title: 'Point the chip at',
      subtitle: 'A chip can only point at a line this recipe already has.',
      searchHint: 'Search this recipe’s lines',
      onQueryChanged: (v) => query.value = v,
      // A single match is offered by name above the list.
      aboveList: matched.length == 1 && q.isNotEmpty
          ? Padding(
              padding: const EdgeInsets.only(top: 10),
              child: FButton(
                onPress: () => Navigator.of(
                  context,
                ).pop(PickedRecipeLine(matched.single.id)),
                child: Text('Chip as “${matched.single.ingredientName}”'),
              ),
            )
          : null,
      body: ListView(
        padding: EdgeInsets.zero,
        children: [
          if (matched.isEmpty && q.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 10, bottom: 6),
              child: Text(
                'Nothing in this recipe matches “$q”. '
                'Add it below, or pick a line.',
                style: ansiMono(size: 11, color: AnsiColors.muted),
              ),
            ),
          Padding(
            padding: const EdgeInsets.only(top: 10, bottom: 4),
            child: Text('IN THIS RECIPE', style: ansiLabel()),
          ),
          for (final (i, line) in shown.indexed) ...[
            if (i > 0) Container(height: 1, color: AnsiColors.line),
            _LineRow(
              line: line,
              ticked: alreadyInStep.contains(line.id),
              onPick: () =>
                  Navigator.of(context).pop(PickedRecipeLine(line.id)),
            ),
          ],
        ],
      ),
      footer: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: canAddLine
            ? () => Navigator.of(context).pop(const AddRecipeLine())
            : null,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(
                    FLucideIcons.plus,
                    size: 16,
                    color: canAddLine ? AnsiColors.herb : AnsiColors.muted,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      'Add an ingredient to this recipe',
                      style: ansiSans(
                        size: 14,
                        color: canAddLine
                            ? AnsiColors.herbDeep
                            : AnsiColors.muted,
                      ),
                    ),
                  ),
                ],
              ),
              if (!canAddLine && addLineReason != null)
                Padding(
                  padding: const EdgeInsets.only(top: 4, left: 26),
                  child: Text(
                    addLineReason!,
                    style: ansiMono(size: 10, color: AnsiColors.muted),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// The amount a row states, in the shape of the editor's quantity pill.
String _amountText(LineItem line) {
  final word = recipeMeasureOfLine(line);
  if (word != null) return measuredAmountText(line.quantity, word.label);
  final measure = line.measure;
  final lineUnit = line.unit;
  final qty = measure == null && lineUnit != null
      ? formatQuantityIn(line.quantity, lineUnit)
      : formatQuantity(line.quantity);
  // A line whose word has gone keeps its number and names no denomination.
  final unit = measure?.label ?? lineUnit?.label ?? '';
  if (unit.isEmpty) return qty;
  return qty.isEmpty ? unit : '$qty $unit';
}

/// One line of the recipe: its identity (a recipe chip for a component, plain
/// text for an ingredient) and its amount.
class _LineRow extends StatelessWidget {
  const _LineRow({
    required this.line,
    required this.ticked,
    required this.onPick,
  });

  final LineItem line;
  final bool ticked;
  final VoidCallback onPick;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onPick,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 10),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (line.isComponent)
                    RecipeChip(title: line.ingredientName)
                  else
                    Text(
                      line.ingredientName,
                      style: ansiSans(size: 15, weight: FontWeight.w600),
                      overflow: TextOverflow.ellipsis,
                    ),
                  const SizedBox(height: 3),
                  Text(
                    _amountText(line),
                    style: ansiMono(size: 11, color: AnsiColors.muted),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Icon(
              ticked ? FLucideIcons.check : FLucideIcons.plus,
              size: 18,
              color: ticked ? AnsiColors.muted : AnsiColors.herb,
            ),
          ],
        ),
      ),
    );
  }
}
