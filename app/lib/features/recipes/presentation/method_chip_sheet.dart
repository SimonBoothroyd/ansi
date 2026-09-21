/// The chip sheet, opened by tapping a chip. Four controls: **Points at**
/// (re-points this chip only), **Word** (the text in the sentence), **Show the
/// amount here**, and **Remove chip** (drops the link, keeps the word).
///
/// A tap cannot place a caret inside a chip, so a chip's word is edited here.
/// Backspacing from just after a chip still demotes it.
library;

import 'package:flutter/widgets.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:forui/forui.dart';

import '../../../core/theme/ansi_theme.dart';
import '../../../core/theme/ansi_tokens.dart';
import '../../../shared/ansi_modals.dart';
import '../../../shared/ansi_sheet_shell.dart';
import '../domain/method_step.dart';

/// What the sheet shows: where the chip points, what it says, and whether it
/// carries its line's amount.
typedef ChipEdit = ({
  List<String> refs,
  String word,
  ChipAmountRule amountRule,
});

/// Opens the chip sheet. Every control writes through [onChanged] as it is
/// touched; [onRemove] drops the link and pops. [pickLine] opens the line
/// picker and resolves to the new line, or null if dismissed.
Future<void> showMethodChipSheet(
  BuildContext context, {
  required ChipEdit initial,
  required String Function(List<String> refs) describe,
  required Future<String?> Function() pickLine,
  required ValueChanged<ChipEdit> onChanged,
  required VoidCallback onRemove,
}) => showAnsiSheet<void>(
  context: context,
  builder: (sheetContext) => _ChipSheet(
    initial: initial,
    describe: describe,
    pickLine: pickLine,
    onChanged: onChanged,
    onRemove: () {
      Navigator.of(sheetContext).pop();
      onRemove();
    },
  ),
);

class _ChipSheet extends HookWidget {
  const _ChipSheet({
    required this.initial,
    required this.describe,
    required this.pickLine,
    required this.onChanged,
    required this.onRemove,
  });

  final ChipEdit initial;

  /// How the lines behind a chip's refs read: "Fennel bulb · 1", or the
  /// constituent run for a collective.
  final String Function(List<String> refs) describe;
  final Future<String?> Function() pickLine;
  final ValueChanged<ChipEdit> onChanged;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    final edit = useState<ChipEdit>(initial);
    final value = edit.value;

    void update(ChipEdit next) {
      edit.value = next;
      onChanged(next);
    }

    return AnsiSheetShell(
      title: 'Chip',
      centerTitle: false,
      children: [
        const SizedBox(height: 14),
        Text('POINTS AT', style: ansiLabel()),
        const SizedBox(height: 6),
        GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () async {
            final lineId = await pickLine();
            if (lineId == null) return;
            update((
              refs: [lineId],
              word: value.word,
              amountRule: value.amountRule,
            ));
          },
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
              color: AnsiColors.surface,
              border: Border.all(color: AnsiColors.line),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    describe(value.refs),
                    style: ansiMono(size: 13),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                const Icon(
                  FLucideIcons.pencil,
                  size: 12,
                  color: AnsiColors.muted,
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 14),
        Text('WORD', style: ansiLabel()),
        const SizedBox(height: 6),
        FTextField(
          hint: 'as it reads in the sentence',
          control: FTextFieldControl.managed(
            initial: TextEditingValue(text: initial.word),
            onChange: (v) {
              if (v.text.trim().isEmpty) return;
              update((
                refs: value.refs,
                word: v.text,
                amountRule: value.amountRule,
              ));
            },
          ),
        ),
        const SizedBox(height: 16),
        FSwitch(
          label: Text('Show the amount here', style: ansiSans(size: 15)),
          value: value.amountRule == ChipAmountRule.showAmount,
          onChange: (on) => update((
            refs: value.refs,
            word: value.word,
            amountRule: on
                ? ChipAmountRule.showAmount
                : ChipAmountRule.hideAmount,
          )),
        ),
        const SizedBox(height: 4),
        Text(
          'The first time a step calls for something, its chip shows the '
          'amount. After that it’s the same stuff, so the chip just names '
          'it.',
          style: ansiMono(size: 11, color: AnsiColors.muted),
        ),
        const SizedBox(height: 16),
        FButton(
          variant: FButtonVariant.ghost,
          onPress: onRemove,
          child: const Text('Remove chip · keeps the word'),
        ),
      ],
    );
  }
}
