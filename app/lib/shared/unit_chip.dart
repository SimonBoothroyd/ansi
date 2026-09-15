/// The unit chip — the one pill a unit is picked with — and the small sheet
/// that offers a list of them.
///
/// It sits in `shared/` because three surfaces ride it and none of them owns
/// it: the ingredient quantity sheet's dock (`UnitChipRow`) builds a row from
/// an admission set and its measures, the component quantity sheet builds its
/// own row over batch math, and `AmountAndUnitField` wears a single chip as
/// the unit half of a sentence. The same object, not three skins that drift.
///
/// **There is no unit dropdown anywhere.** A unit is picked from the units
/// this row can say, as chips — which is why the sentence control opens
/// [showUnitPickSheet] rather than a select: the offer is the same offer, in a
/// room small enough for a sentence to point at.
library;

import 'package:flutter/widgets.dart';

import '../core/theme/ansi_theme.dart';
import '../core/theme/ansi_tokens.dart';
import '../core/units/units.dart';
import 'ansi_modals.dart';
import 'ansi_sheet_shell.dart';

/// The height of a chip in a dock — the row above a keypad, and the pick
/// sheet's own [Wrap]. A chip inside a line of prose is trimmed to
/// `kInlineControlHeight` instead, which is the sentence's height, not the
/// dock's.
const double kUnitChipHeight = 34;

/// Offers [units] as chips and resolves to the one tapped, or null when the
/// sheet is dismissed.
///
/// The offer is the caller's list in the caller's order, and these lists are
/// **catalog** units — what a serving may be said in, what a basis can reach,
/// what a yield may be stated in. So there is no measure to lead with and no
/// imprecise divider to draw: a host holding an ingredient and its measures
/// wants the dock (`UnitChipRow`), not this.
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
      // A Wrap, not the dock's scrolling row: nothing here is docked over a
      // keypad, so every unit on offer can be seen at once rather than
      // hidden past a fold.
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

/// One chip of a unit offer: a label in a pill that fills in when it is the
/// chosen one.
///
/// It sizes to its label and takes its height from whatever encloses it, so
/// the same chip reads as a dock chip at [kUnitChipHeight] and as the unit
/// half of a sentence at `kInlineControlHeight`.
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

  /// A subtle annotation after the label ("not in filter") — the admitted
  /// off-filter selection reads as such without being hidden.
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
