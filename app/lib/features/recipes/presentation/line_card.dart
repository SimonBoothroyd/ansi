/// The expanding ingredient line shared by the import review and the recipe
/// editor: a row at rest, a card when open. Each screen fills the card's slots
/// with its own content.
///
/// Anywhere on the collapsed row opens the card. The grip sits outside the
/// row's tap target, and a drag anywhere in the list closes every open card
/// ([LineCard.collapseEpoch]). The review borders every line; the editor's
/// lines sit bare until opened ([LineCard.borderAtRest]).
library;

import 'package:flutter/widgets.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:forui/forui.dart';

import '../../../core/theme/ansi_theme.dart';
import '../../../core/theme/ansi_tokens.dart';
import '../../../shared/ansi_tap.dart';
import '../../../shared/reorder_grip.dart';
import 'ingredient_line.dart';

/// The label column on the card's rows (AMOUNT, UNIT, NOTES).
const double kLineCardLabelWidth = 64;

/// One line: the row at rest, the card when open. [collapsed] and [expanded]
/// are builders so each receives the gesture that toggles the state, which
/// lives here.
class LineCard extends HookWidget {
  const LineCard({
    required this.collapsed,
    required this.expanded,
    this.dragIndex,
    this.collapseEpoch = 0,
    this.initiallyOpen = false,
    this.attention = false,
    this.borderAtRest = true,
    this.lit = false,
    super.key,
  });

  /// The row at rest, given the callback that opens the card.
  final Widget Function(VoidCallback onExpand) collapsed;

  /// The open card, given the callback that closes it.
  final Widget Function(VoidCallback onCollapse) expanded;

  /// This card's index in the list that drags it. Null when not in a list.
  final int? dragIndex;

  /// Bumped by the list when a drag starts elsewhere: every open card closes.
  final int collapseEpoch;

  /// Whether the card starts open — a line the person just added. Only the
  /// starting state.
  final bool initiallyOpen;

  /// Whether the line needs the user; the border stays amber while it does.
  final bool attention;

  /// Whether a closed line is a bordered card (review) or a bare row on a
  /// hairline (editor).
  final bool borderAtRest;

  /// Whether the step being written points at this line (wide editor). View
  /// state, never stored; shows only on the bare row.
  final bool lit;

  @override
  Widget build(BuildContext context) {
    // Local to the row, so it survives the host's rebuilds.
    final open = useState(initiallyOpen);
    // A drag bumps the epoch and closes every open card. The first build is not
    // a change, so a card that opens at birth stays open.
    final seen = useRef(collapseEpoch);
    useEffect(() {
      if (seen.value != collapseEpoch) {
        seen.value = collapseEpoch;
        open.value = false;
      }
      return null;
    }, [collapseEpoch]);

    if (open.value) {
      return LineCardSurface(
        attention: attention,
        child: expanded(() => open.value = false),
      );
    }
    return LineCardSurface(
      attention: attention,
      bordered: borderAtRest,
      lit: lit,
      child: LineCardGrip(
        dragIndex: dragIndex,
        child: collapsed(() => open.value = true),
      ),
    );
  }
}

/// The surface a line is drawn on: the bordered box, or the bare row with a
/// hairline under it.
class LineCardSurface extends StatelessWidget {
  const LineCardSurface({
    required this.child,
    this.attention = false,
    this.dropped = false,
    this.bordered = true,
    this.lit = false,
    super.key,
  });

  final Widget child;

  /// An amber border while the line needs the user.
  final bool attention;

  /// A line on its way out of an import: the flat paper fill that says so.
  final bool dropped;

  final bool bordered;

  /// See [LineCard.lit]. The hairline is hidden under the wash.
  final bool lit;

  @override
  Widget build(BuildContext context) {
    if (!bordered) {
      final row = Padding(
        padding: const EdgeInsets.symmetric(vertical: 9),
        child: child,
      );
      return Column(
        children: [
          if (lit)
            DecoratedBox(
              decoration: BoxDecoration(
                color: AnsiColors.herbSoft,
                borderRadius: BorderRadius.circular(9),
              ),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8),
                child: row,
              ),
            )
          else
            row,
          // Kept as a gap when lit, so lighting a line never moves the ones
          // under it.
          Container(height: 1, color: lit ? null : AnsiColors.line),
        ],
      );
    }
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: dropped ? AnsiColors.paper : AnsiColors.surface,
          border: Border.all(
            color: attention ? AnsiColors.aging : AnsiColors.line,
          ),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
          child: child,
        ),
      ),
    );
  }
}

/// The drag grip beside a collapsed row, outside the row's tap target.
class LineCardGrip extends StatelessWidget {
  const LineCardGrip({required this.child, this.dragIndex, super.key});

  final Widget child;
  final int? dragIndex;

  @override
  Widget build(BuildContext context) {
    final index = dragIndex;
    if (index == null) return child;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        DragGrip(index: index),
        Expanded(child: child),
      ],
    );
  }
}

/// The card's head: the line's identity slot, remove, and close. The editor
/// puts `change ›` in the slot; the review prints the current identity.
class LineCardHead extends StatelessWidget {
  const LineCardHead({
    required this.identity,
    required this.onCollapse,
    this.onRemove,
    super.key,
  });

  final Widget identity;

  /// Removes the line. Null where the card cannot be removed from here.
  final VoidCallback? onRemove;
  final VoidCallback onCollapse;

  @override
  Widget build(BuildContext context) {
    final onRemove = this.onRemove;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(child: identity),
        if (onRemove != null) ...[
          const SizedBox(width: 8),
          AnsiTap(
            onTap: onRemove,
            semanticsLabel: 'Remove the line',
            color: AnsiColors.muted,
            padding: const EdgeInsets.symmetric(horizontal: 4),
            child: const Icon(FLucideIcons.trash2, size: 16),
          ),
        ],
        const SizedBox(width: 8),
        AnsiTap(
          onTap: onCollapse,
          semanticsLabel: 'Close the line',
          color: AnsiColors.muted,
          child: const Icon(FLucideIcons.chevronUp, size: 18),
        ),
      ],
    );
  }
}

/// One labelled row of the open card, with a [kLineCardLabelWidth] label
/// column.
class LineCardRow extends StatelessWidget {
  const LineCardRow({required this.label, required this.child, super.key});

  final String label;
  final Widget child;

  @override
  Widget build(BuildContext context) => Row(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      SizedBox(
        width: kLineCardLabelWidth,
        child: Text(label, style: ansiLabel()),
      ),
      const SizedBox(width: 8),
      Expanded(child: child),
    ],
  );
}

/// The amount as a chip with a pencil; it opens the quantity sheet, the one
/// place an amount is entered.
class LineCardAmountChip extends StatelessWidget {
  const LineCardAmountChip({
    required this.label,
    required this.onTap,
    this.emptyLabel = 'set amount',
    this.semanticsLabel = 'Amount',
    super.key,
  });

  /// The amount's text. Empty prints [emptyLabel].
  final String label;

  /// The empty chip's prompt and semantic label; the amount's by default.
  final String emptyLabel;
  final String semanticsLabel;

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Semantics(
    label: semanticsLabel,
    button: true,
    child: GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: AnsiColors.paper,
          border: Border.all(color: AnsiColors.line),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Flexible(
                child: Text(
                  label.isEmpty ? emptyLabel : label,
                  style: ansiMono(size: 12, color: AnsiColors.muted),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const SizedBox(width: 5),
              const Icon(FLucideIcons.pencil, size: 11, color: AnsiColors.herb),
            ],
          ),
        ),
      ),
    ),
  );
}

/// The inline notes field. Blank clears the note; a value is trimmed and
/// stored.
class LineCardNotesField extends StatelessWidget {
  const LineCardNotesField({
    required this.initial,
    required this.onChanged,
    this.enabled = true,
    super.key,
  });

  /// The note as it stands. The field is uncontrolled afterwards, so host
  /// rebuilds never move the caret.
  final String? initial;
  final ValueChanged<String> onChanged;

  /// False where the line has no ingredient to attach a note to yet.
  final bool enabled;

  @override
  Widget build(BuildContext context) => LineCardRow(
    label: 'NOTES',
    child: FTextField(
      enabled: enabled,
      hint: 'e.g. finely chopped, to serve',
      control: FTextFieldControl.managed(
        initial: TextEditingValue(text: initial ?? ''),
        onChange: (v) => onChanged(v.text),
      ),
    ),
  );
}

/// The `optional` flag as a one-tap control, in [OptionalTag]'s geometry: an
/// outline with an empty ring when off, the tag when on. The filled herb check
/// is reserved for week mode's `included`.
class OptionalFlagToggle extends StatelessWidget {
  const OptionalFlagToggle({
    required this.value,
    required this.onChanged,
    super.key,
  });

  final bool value;

  /// The argument is what the line is to BECOME.
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) => Semantics(
    label: value
        ? 'optional · tap to make it required'
        : 'not optional · tap to mark it optional',
    button: true,
    child: GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => onChanged(!value),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: value ? AnsiColors.herbSoft : null,
          border: value ? null : Border.all(color: AnsiColors.line),
          borderRadius: BorderRadius.circular(6),
        ),
        child: Padding(
          padding: EdgeInsets.symmetric(
            horizontal: value ? 7 : 6,
            vertical: value ? 3 : 2,
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (!value)
                const Padding(
                  padding: EdgeInsets.only(right: 4),
                  child: OptionalRing(),
                ),
              Text(
                'optional',
                style: ansiMono(size: 10, color: AnsiColors.muted),
              ),
            ],
          ),
        ),
      ),
    ),
  );
}
