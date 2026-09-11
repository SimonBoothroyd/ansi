/// The unit chip row — the dock every quantity surface rides.
///
/// The chip itself is [UnitChip], in `shared/`, because a third surface wears
/// one outside any row: the amount-and-unit control's sentence. This row is
/// the part that needs an [Ingredient] and its measures, which is exactly why
/// it is not the reusable piece.
library;

import 'package:flutter/widgets.dart';
import 'package:forui/forui.dart';

import '../../../core/theme/ansi_tokens.dart';
import '../../../core/units/measure.dart';
import '../../../core/units/units.dart';
import '../../../shared/unit_chip.dart';
import '../domain/allowed_units.dart';
import '../domain/ingredient.dart';
import '../domain/serving_measure.dart';
import 'measures_editor.dart' show SourceDot;

/// The chip row in the order [allowedUnitChoicesFor] hands it: the row's own
/// measures (source dot + label) · the default unit and the rest of its
/// family · demoted other-family units · imprecise after a divider · the `+`
/// manage chip. Horizontally scrollable; docked directly
/// above the keyboard by the host sheet. On open it scrolls the selected
/// chip into view — a stored selection can sit deep in a long row and must
/// not open off-screen.
class UnitChipRow extends StatefulWidget {
  const UnitChipRow({
    required this.ingredient,
    required this.measures,
    required this.selected,
    required this.onSelect,
    required this.onManage,
    this.stored,
    super.key,
  });

  final Ingredient ingredient;
  final List<Measure> measures;
  final UnitChoice selected;

  /// The stored (initial) choice — always admitted into the row, so an
  /// off-filter value (a merge-hidden duplicate measure, a no-longer-allowed
  /// unit) stays re-selectable even after tapping another chip. A user can
  /// only ever select an offered chip, so the live [selected] is always
  /// either in the filter or equal to this.
  final UnitChoice? stored;
  final ValueChanged<UnitChoice> onSelect;
  final VoidCallback onManage;

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

  @override
  Widget build(BuildContext context) {
    // The full offer comes from the domain filter — already in ADR-0008 chip
    // order (measures → default set → demoted → imprecise), excluding
    // volume-named measures (density owns volume conversion, frame-b review)
    // and ALWAYS admitting the stored selection — a merge-hidden duplicate
    // measure or a no-longer-allowed unit stays reachable, flagged so it can
    // read as outside the honest filter (the retired dropdowns' rule).
    final offer = allowedUnitChoicesFor(
      widget.ingredient,
      widget.measures,
      current: widget.stored ?? widget.selected,
    );
    final offFilter = offer.offFilter;
    final inFilter = offFilter == null
        ? offer.choices
        : offer.choices.sublist(0, offer.choices.length - 1);

    final children = <Widget>[];
    var dividerPlaced = false;
    for (final c in inFilter) {
      final imprecise =
          c is UnitOption && c.unit.family == UnitFamily.imprecise;
      if (imprecise && !dividerPlaced) {
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
      children.add(
        UnitChip(
          key: widget.selected == c ? _selectedKey : null,
          // A measure chip carries the bare label; its weight shows in the
          // selected-choice line, not on every chip. `piece` is the one unit
          // that carries its weight ON the chip (ADR-0015): a count is only a
          // unit here because the row says what one weighs, and the chip
          // says so rather than leaving "piece" to mean a clove or a bulb.
          label: switch (c) {
            MeasureOption(:final measure) => measureChipLabel(measure),
            UnitOption(:final unit) when unit == pieces => pieceChipLabel(
              widget.ingredient,
            ),
            UnitOption(:final unit) => unit.label,
          },
          dot: c is MeasureOption
              ? SourceDot(kind: c.measure.sourceKind)
              : null,
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
          label: switch (offFilter) {
            MeasureOption(:final measure) => measure.label,
            UnitOption(:final unit) when unit == pieces => pieceChipLabel(
              widget.ingredient,
            ),
            UnitOption(:final unit) => unit.label,
          },
          suffix: 'not in filter',
          dot: switch (offFilter) {
            MeasureOption(:final measure) => SourceDot(
              kind: measure.sourceKind,
            ),
            UnitOption() => null,
          },
          selected: widget.selected == offFilter,
          onTap: () => widget.onSelect(offFilter),
        ),
      );
    }
    // A real icon, not a "＋" glyph — the bundled fonts lack U+FF0B,
    // so the string form renders as tofu (the library_view rule).
    children.add(
      UnitChip(
        icon: const Icon(FLucideIcons.plus, size: 13, color: AnsiColors.herb),
        accent: true,
        onTap: widget.onManage,
      ),
    );

    return SizedBox(
      height: kUnitChipHeight,
      // A single scrollable Row (not a lazy ListView): every chip keeps a
      // live context, so the open-scroll can ensureVisible the selected one
      // even when it sits past the fold.
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(children: children),
      ),
    );
  }
}
