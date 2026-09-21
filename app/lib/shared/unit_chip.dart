/// The unit chip, the one pill a unit is picked with, and the small sheet
/// that offers a list of them.
///
/// Shared by the ingredient and component quantity sheets' docks and by
/// `AmountAndUnitField`. There is no unit dropdown anywhere.
library;

import 'package:flutter/widgets.dart';

import '../core/theme/ansi_theme.dart';
import '../core/theme/ansi_tokens.dart';
import '../core/units/units.dart';
import 'ansi_modals.dart';
import 'ansi_sheet_shell.dart';

/// The height of a chip in a dock or the pick sheet. A chip inside a line of
/// prose is trimmed to `kInlineControlHeight` instead.
const double kUnitChipHeight = 34;

/// Offers [units] as chips and resolves to the one tapped, or null when the
/// sheet is dismissed.
///
/// The offer is the caller's list of catalog units in the caller's order. A
/// host holding an ingredient and its measures wants `UnitChipRow` instead.
Future<Unit?> showUnitPickSheet(
  BuildContext context, {
  required List<Unit> units,
  required Unit selected,
}) => showAnsiSheet<Unit>(
  context: context,
  builder: (sheetContext) => AnsiSheetShell(
    title: 'Unit',
    centerTitle: false,
    scrollable: true,
    children: [
      const SizedBox(height: 14),
      // A Wrap, not a scrolling row: every unit on offer is visible at once.
      Wrap(
        runSpacing: 8,
        children: [
          for (final unit in units)
            SizedBox(
              height: kUnitChipHeight,
              child: UnitChip(
                label: unit.label,
                selected: unit == selected,
                onTap: () => Navigator.of(sheetContext).pop(unit),
              ),
            ),
        ],
      ),
    ],
  ),
);

/// One chip of a unit offer, filled in when chosen. It sizes to its label and
/// takes its height from whatever encloses it.
class UnitChip extends StatelessWidget {
  const UnitChip({
    required this.onTap,
    this.label,
    this.icon,
    this.selected = false,
    this.imprecise = false,
    this.accent = false,
    this.dot,
    this.suffix,
    super.key,
  }) : assert(label != null || icon != null, 'a chip needs a label or icon');

  final String? label;
  final Widget? icon;
  final bool selected;
  final bool imprecise;
  final bool accent;
  final Widget? dot;

  /// A subtle annotation after the label ("not in filter").
  final String? suffix;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final fg = selected
        ? AnsiColors.surface
        : accent
        ? AnsiColors.herb
        : imprecise
        ? AnsiColors.muted
        : AnsiColors.ink;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.only(right: 6),
        padding: const EdgeInsets.symmetric(horizontal: 12),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: selected ? AnsiColors.herb : AnsiColors.surface,
          border: Border.all(
            color: selected || accent ? AnsiColors.herb : AnsiColors.line,
          ),
          borderRadius: BorderRadius.circular(999),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (dot != null) ...[dot!, const SizedBox(width: 5)],
            if (icon != null) icon!,
            if (label != null)
              Text(label!, style: ansiMono(size: 11.5, color: fg)),
            if (suffix != null) ...[
              const SizedBox(width: 5),
              Text(
                suffix!,
                style: ansiMono(
                  size: 9,
                  color: selected ? AnsiColors.surface : AnsiColors.muted,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
