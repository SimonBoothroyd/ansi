/// The drag idiom the reorderable lists share: the grip that starts a
/// reorder, and the paper a row is lifted onto while it drags.
library;

import 'package:flutter/widgets.dart';
import 'package:forui/forui.dart';

import '../core/theme/ansi_tokens.dart';

/// The explicit drag handle a reorderable row wears; nothing else starts a
/// drag, so a scroll cannot become a move. [index] is the row's position in
/// the flat list it drags within.
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

/// The row under the finger while it drags, lifted onto paper.
Widget liftedRow(Widget child, int index, Animation<double> animation) =>
    DecoratedBox(
      decoration: BoxDecoration(
        color: AnsiColors.paper,
        border: Border.all(color: AnsiColors.line),
        borderRadius: BorderRadius.circular(10),
      ),
      child: child,
    );
