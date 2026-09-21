/// The unit chip row that every quantity surface docks above the keyboard. The
/// chip itself is [UnitChip], in `shared/`. This row draws a prebuilt
/// [UnitChoiceOffer]; the domain decides its entries and order
/// (`allowedUnitChoicesFor` for an ingredient, `componentUnitChoices` for a
/// component line).
library;

import 'package:flutter/widgets.dart';
import 'package:forui/forui.dart';

import '../../../core/theme/ansi_tokens.dart';
import '../../../core/units/unit_choice.dart';
import '../../../core/units/units.dart';
import '../../../shared/unit_chip.dart';
import '../domain/serving_measure.dart';
import 'measures_editor.dart' show SourceDot;

/// The chip row in its [offer]'s order, with the imprecise tail after a
/// divider, the off-filter entry marked *not in filter*, and the `+` manage
/// chip last where the host has one. Horizontally scrollable; on open it
/// scrolls the selected chip into view.
class UnitChipRow extends StatefulWidget {
  const UnitChipRow({
    required this.offer,
    required this.selected,
    required this.onSelect,
    this.onManage,
    this.pieceLabel,
    super.key,
  });

  /// The whole offer, including a stored selection admitted from outside the
  /// filter (`offFilter`). The host builds it.
  final UnitChoiceOffer offer;

  /// The live selection, or null when the line has nothing to preselect, e.g. a
  /// component line whose recipe measure was retired.
  final UnitChoice? selected;
  final ValueChanged<UnitChoice> onSelect;

  /// Opens the host's manage-measures state. Null draws no `+` chip (the price
  /// sheet has none).
  final VoidCallback? onManage;

  /// What a `piece` chip says on this host: `piece (350 g)` on an ingredient
  /// row with a piece weight (`pieceChipLabel`, ADR-0015). Null keeps the bare
  /// word.
  final String? pieceLabel;

  @override
  State<UnitChipRow> createState() => _UnitChipRowState();
}

class _UnitChipRowState extends State<UnitChipRow> {
  /// Rides whichever chip is currently selected, so the open-scroll (and any
  /// later caller) can find it in the row.
  final _selectedKey = GlobalKey();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final chipContext = _selectedKey.currentContext;
      if (!mounted || chipContext == null) return;
      Scrollable.ensureVisible(chipContext, alignment: 0.5);
    });
  }

  /// A measure chip carries the bare label; its weight shows in the
  /// selected-choice line. Only `piece` can carry its weight on the chip
  /// (ADR-0015), and only where the host says so.
  String _label(UnitChoice choice) => switch (choice) {
    MeasureOption(:final measure) => measureChipLabel(measure),
    RecipeMeasureOption(:final measure) => measure.label,
    UnitOption(:final unit) when unit == pieces =>
      widget.pieceLabel ?? unit.label,
    UnitOption(:final unit) => unit.label,
  };

  /// The source dot an ingredient's measure wears. A recipe's own measures wear
  /// none.
  Widget? _dot(UnitChoice choice) => switch (choice) {
    MeasureOption(:final measure) => SourceDot(kind: measure.sourceKind),
    RecipeMeasureOption() || UnitOption() => null,
  };

  @override
  Widget build(BuildContext context) {
    final offer = widget.offer;
    final offFilter = offer.offFilter;
    final inFilter = offFilter == null
        ? offer.choices
        : offer.choices.sublist(0, offer.choices.length - 1);

    final children = <Widget>[];
    // The divider goes before the first imprecise chip that has a precise one
    // behind it, so a row whose default unit is an imprecise word still leads
    // with it.
    var dividerPlaced = false;
    var seenPreciseUnit = false;
    for (final c in inFilter) {
      final imprecise =
          c is UnitOption && c.unit.family == UnitFamily.imprecise;
      if (imprecise && seenPreciseUnit && !dividerPlaced) {
        dividerPlaced = true;
        children.add(
          Container(
            width: 1,
            height: 18,
            margin: const EdgeInsets.symmetric(horizontal: 6, vertical: 8),
            color: AnsiColors.line,
          ),
        );
      }
      if (c is UnitOption && !imprecise) seenPreciseUnit = true;
      children.add(
        UnitChip(
          key: widget.selected == c ? _selectedKey : null,
          label: _label(c),
          dot: _dot(c),
          imprecise: imprecise,
          selected: widget.selected == c,
          onTap: () => widget.onSelect(c),
        ),
      );
    }
    if (offFilter != null) {
      children.add(
        UnitChip(
          key: widget.selected == offFilter ? _selectedKey : null,
          label: _label(offFilter),
          suffix: 'not in filter',
          dot: _dot(offFilter),
          selected: widget.selected == offFilter,
          onTap: () => widget.onSelect(offFilter),
        ),
      );
    }
    // A real icon, not a "＋" glyph — the bundled fonts lack U+FF0B,
    // so the string form renders as tofu (the library_view rule).
    if (widget.onManage case final onManage?) {
      children.add(
        UnitChip(
          icon: const Icon(FLucideIcons.plus, size: 13, color: AnsiColors.herb),
          accent: true,
          onTap: onManage,
        ),
      );
    }

    return SizedBox(
      height: kUnitChipHeight,
      // A single scrollable Row, not a lazy ListView: every chip keeps a live
      // context, so ensureVisible can reach the selected one past the fold.
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(children: children),
      ),
    );
  }
}
