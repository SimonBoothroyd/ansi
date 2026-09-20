/// The expanding ingredient line — the chrome and the slots two screens fill.
///
/// A line is a **row at rest** and a **card when it is open**: tapping the row
/// opens it in place, and everything the line can say about itself is inside —
/// the identity, whether it may be left out, the amount, the notes. The import
/// review and the recipe editor are the same component here; what differs is
/// what each puts in the slots (the review's match cascade and never-invent
/// flags mean nothing on a saved recipe, and the editor's *used in N steps*
/// means nothing on a line that is not saved yet).
///
/// **One gesture.** Anywhere on the collapsed row opens the card. A row that
/// meant the quantity sheet on its left 84 px and the identity picker on the
/// rest is a row a cook has to aim at — and the fact that sent them looking,
/// the note, was behind neither. The cost is honest: changing an amount is two
/// taps, row then chip.
///
/// **The grip is on the collapsed row only**, outside its tap target, so
/// taking hold of the handle never opens the card; and a drag starting
/// anywhere in the list closes every open card ([LineCard.collapseEpoch]), so
/// what crosses the list is a row like every other row rather than forms of
/// wildly different heights.
///
/// **The border is a state, not a decoration.** The review borders every line
/// because every line there is a claim waiting to be checked; the editor's
/// lines are settled, so they sit bare on the recipe page's own hairline and
/// the box appears when one opens ([LineCard.borderAtRest]).
library;

import 'package:flutter/widgets.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:forui/forui.dart';

import '../../../core/theme/ansi_theme.dart';
import '../../../core/theme/ansi_tokens.dart';
import '../../../shared/ansi_tap.dart';
import '../../../shared/reorder_grip.dart';
import 'ingredient_line.dart';

/// The label column on the card's rows — AMOUNT, UNIT, NOTES. One number, so
/// the three slots line up under each other on both screens.
const double kLineCardLabelWidth = 64;

/// One line: the row at rest, the card when it is open.
///
/// [collapsed] and [expanded] are builders rather than widgets because each
/// is handed the gesture that changes the state — the row opens itself, the
/// card's chevron closes it — and neither screen should have to hold that
/// state to draw its own contents.
class LineCard extends HookWidget {
  const LineCard({
    required this.collapsed,
    required this.expanded,
    this.dragIndex,
    this.collapseEpoch = 0,
    this.attention = false,
    this.borderAtRest = true,
    this.lit = false,
    super.key,
  });

  /// The row at rest, given the callback that opens the card.
  final Widget Function(VoidCallback onExpand) collapsed;

  /// The open card, given the callback that closes it.
  final Widget Function(VoidCallback onCollapse) expanded;

  /// This card's position in the list that drags it — what the grip takes
  /// hold of. Null where the card renders on its own.
  final int? dragIndex;

  /// Bumped by the list when a drag starts elsewhere: every open card closes.
  final int collapseEpoch;

  /// Whether the line needs the user — the border goes amber and stays amber
  /// while it does. Always false where nothing gates a save.
  final bool attention;

  /// Whether a closed line is drawn as a bordered card or as a bare row on a
  /// hairline. False in the editor, where a wall of boxes makes a finished
  /// list look unfinished.
  final bool borderAtRest;

  /// Whether a step being written points at this line — the wide editor's one
  /// use of the width. It is view state that follows focus and is never
  /// stored, and it only shows on the bare row: an open card is already the
  /// loudest thing in the column.
  final bool lit;

  @override
  Widget build(BuildContext context) {
    // Local to the row: several cards stand open at once, and each survives
    // the host's rebuild on every keystroke somewhere else.
    final open = useState(false);
    useEffect(() {
      open.value = false;
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

/// The surface a line is drawn on: the card's bordered box, or — at rest in
/// the editor — the bare row with the recipe page's hairline under it.
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

  /// An aging border while the line needs the user, a quiet line once it is
  /// done.
  final bool attention;

  /// A line on its way out of an import: the flat paper fill that says so.
  final bool dropped;

  final bool bordered;

  /// See [LineCard.lit] — the Shop pane's own selected-row wash, on the bare
  /// row. The hairline goes with it: a rule under a washed row cuts it in half.
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
          // Kept as a gap when the wash takes the rule's place, so lighting a
          // line never moves the ones under it.
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

/// The grip beside a collapsed row, when the list it lives in drags. It sits
/// OUTSIDE the row's own tap target, so taking hold of the handle never counts
/// as opening the card.
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

/// The card's head: what the line IS, and the two things that can be done to
/// the card itself — remove the line, close the card.
///
/// The identity is a slot because the two screens name a line differently: the
/// editor puts `change ›` beside the name (the head IS the identity door
/// there), the review prints the current identity and leaves re-matching to
/// the cascade under it.
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

/// One labelled row of the open card — `AMOUNT`, `UNIT`, `NOTES`. The label
/// column is [kLineCardLabelWidth] on both screens, so the slots stack.
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

/// The amount as the card prints it: a chip with the pencil that opens the
/// sheet where an amount is said. The sheet is the app's one place for a
/// keypad, the unit chip row and the measures — a card cannot hold those, and
/// two ways to say an amount would be two vocabularies.
class LineCardAmountChip extends StatelessWidget {
  const LineCardAmountChip({
    required this.label,
    required this.onTap,
    this.emptyLabel = 'set amount',
    this.semanticsLabel = 'Amount',
    super.key,
  });

  /// What the line's amount reads as. Empty prints [emptyLabel] instead — the
  /// slot never invents a unit to look filled.
  final String label;

  /// The prompt an empty chip carries, and what a screen reader calls it.
  /// Both are the amount's by default; a chip that asks for something else —
  /// a receipt line's PACK — says so in its own words.
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
/// stored. It is a field rather than a sheet because it is the one control on
/// the card a cook wants to read while looking at the amount above it.
class LineCardNotesField extends StatelessWidget {
  const LineCardNotesField({
    required this.initial,
    required this.onChanged,
    this.enabled = true,
    super.key,
  });

  /// The note as it stands. The field is uncontrolled from there on, so the
  /// host's rebuild on every keystroke never moves the caret.
  final String? initial;
  final ValueChanged<String> onChanged;

  /// False where the line has nothing to hang a note on yet — an import line
  /// with no ingredient matched.
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

/// The `optional` flag as the card's one-tap control.
///
/// It is [OptionalTag]'s geometry — the same 6 px box, the same muted mono —
/// because it is the same mark the collapsed row and the recipe page print,
/// and a second pill shape would read as a second vocabulary. Off, it is an
/// outline with an empty ring: a question nobody has answered. On, it is the
/// tag the row will wear. The filled herb + check stays reserved for week
/// mode's `included`, which is a different question ("this time, yes").
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
