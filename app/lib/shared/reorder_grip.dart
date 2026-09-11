/// The one drag idiom: the grip that starts a reorder, and the paper a row is
/// lifted onto while it crosses the list.
///
/// It lives here rather than beside any one list because three of them use it
/// — the recipe editor's lines, the import review's cards, and an
/// ingredient's measures — and a second copy is how two of them drift apart.
library;

import 'package:flutter/widgets.dart';
import 'package:forui/forui.dart';

import '../core/theme/ansi_tokens.dart';

/// The explicit drag handle a reorderable row wears.
///
/// A list of tappable rows that also moved on hold is how a scroll becomes an
/// accidental move, so the gesture gets a glyph of its own and nothing else
/// starts it. [index] is the row's position in the flat list it drags within.
class DragGrip extends StatelessWidget {
  const DragGrip({required this.index, super.key});

  final int index;

  @override
  Widget build(BuildContext context) => ReorderableDragStartListener(
    index: index,
    child: Semantics(
      label: 'Reorder',
      child: const Padding(
        padding: EdgeInsets.only(right: 6, top: 2),
        child: Icon(
          FLucideIcons.gripVertical,
          size: 15,
          color: AnsiColors.line,
        ),
      ),
    ),
  );
}

/// The row under the finger while it drags: the same row, lifted onto paper so
/// it reads over the list it is crossing. Both line lists decorate with it, so
/// a drag looks the same wherever it happens.
Widget liftedRow(Widget child, int index, Animation<double> animation) =>
    DecoratedBox(
      decoration: BoxDecoration(
        color: AnsiColors.paper,
        border: Border.all(color: AnsiColors.line),
        borderRadius: BorderRadius.circular(10),
      ),
      child: child,
    );
