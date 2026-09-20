/// The unit chip row — the dock every quantity surface rides.
///
/// The chip itself is [UnitChip], in `shared/`, because a third surface wears
/// one outside any row: the amount-and-unit control's sentence. This row is
/// the part that draws a whole **offer**.
///
/// It is handed a prebuilt [UnitChoiceOffer] and draws it; which entries an
/// offer holds, and in what order, is the domain's answer —
/// `allowedUnitChoicesFor` for an ingredient, `componentUnitChoices` for a
/// sub-recipe component line. That is why one widget serves both: a chip row
/// is a way of saying a list of choices, and the two surfaces disagree about
/// the list rather than about the saying.
library;

import 'package:flutter/widgets.dart';
import 'package:forui/forui.dart';

import '../../../core/theme/ansi_tokens.dart';
import '../../../core/units/unit_choice.dart';
import '../../../core/units/units.dart';
import '../../../shared/unit_chip.dart';
import '../domain/serving_measure.dart';
import 'measures_editor.dart' show SourceDot;

/// The chip row in the order its [offer] hands it, with the imprecise tail set
/// off by a divider, the off-filter entry marked *not in filter*, and the `+`
/// manage chip last where the host has a manage state to open.
///
/// Horizontally scrollable; docked directly above the keyboard by the host
/// sheet. On open it scrolls the selected chip into view — a stored selection
/// can sit deep in a long row and must not open off-screen.
class UnitChipRow extends StatefulWidget {
  const UnitChipRow({
    required this.offer,
    required this.selected,
    required this.onSelect,
    this.onManage,
    this.pieceLabel,
    super.key,
  });

  /// The whole offer, including the stored selection the domain filter
  /// admitted from outside itself (`offFilter`) — a merge-hidden duplicate
  /// measure, a no-longer-allowed unit, a word whose `makes` has gone. The
  /// host builds it, because only the host knows which filter it is asking.
  final UnitChoiceOffer offer;

  /// The live selection, or null where the line has no honest denomination to
  /// preselect: a component line whose recipe measure has been retired keeps
  /// its pointer with **no** chip lit, so nothing on the row claims to be what
  /// the line says.
  final UnitChoice? selected;
  final ValueChanged<UnitChoice> onSelect;

  /// Opens the host's manage-measures state, or null where the host has none
  /// — the price sheet, where the pack is a purchase and not a vocabulary
  /// edit. Null draws no `+` chip rather than one that does nothing.
  final VoidCallback? onManage;

  /// What a `piece` chip says on this host — `piece (350 g)` on an ingredient
  /// row that states what one weighs (`pieceChipLabel`, ADR-0015: a count is
  /// only a unit there because the row says what one comes to). Null keeps the
  /// bare word, which is all a recipe's count yield can honestly say.
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
  /// selected-choice line, not on every chip. `piece` is the one unit that can
  /// carry its weight ON the chip (ADR-0015), and only where the host says so.
  String _label(UnitChoice choice) => switch (choice) {
    MeasureOption(:final measure) => measureChipLabel(measure),
    RecipeMeasureOption(:final measure) => measure.label,
    UnitOption(:final unit) when unit == pieces =>
      widget.pieceLabel ?? unit.label,
    UnitOption(:final unit) => unit.label,
  };

  /// The source dot an INGREDIENT's measure wears — USDA, a borrow, an
  /// estimate, the household's own. A recipe's words have one source and it is
  /// the household that wrote the recipe, so they wear none.
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
    // The divider marks where the words the offer merely ADMITS begin — the
    // imprecise tail. A row whose own default unit is an imprecise word leads
    // the catalog with it (owner), so that leading word is on the near side of
    // the divider: the tail is the first imprecise chip with a precise one
    // already behind it.
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
