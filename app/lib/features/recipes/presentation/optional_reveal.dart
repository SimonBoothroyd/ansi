/// The page opened to choose optional ingredients brings them on screen.
/// Optional lines are ordinary rows in their own groups, so this wraps the
/// first and the last such row rather than a section.
library;

import 'dart:async';

import 'package:flutter/widgets.dart';

/// The key of an optional row: its first line's id.
ValueKey<String> optionalRowKey(String lineId) =>
    ValueKey('optional-row-$lineId');

/// [child], scrolled on screen once it is first laid out. The last optional
/// row is brought into view from below ([end]), then the first is kept from
/// going above the top ([start]), so as many as fit are on screen at once and
/// the first always is. One row alone does both.
class OptionalReveal extends StatefulWidget {
  const OptionalReveal({
    required this.child,
    this.start = false,
    this.end = false,
    super.key,
  });

  final Widget child;
  final bool start;
  final bool end;

  @override
  State<OptionalReveal> createState() => _OptionalRevealState();
}

class _OptionalRevealState extends State<OptionalReveal> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (widget.end) {
        Scrollable.ensureVisible(
          context,
          alignmentPolicy: ScrollPositionAlignmentPolicy.keepVisibleAtEnd,
        ).ignore();
      }
      if (!widget.start) return;
      // After every row's own pass this frame, so the last row's scroll lands
      // first and this one corrects it.
      scheduleMicrotask(() {
        if (!mounted) return;
        Scrollable.ensureVisible(
          context,
          alignmentPolicy: ScrollPositionAlignmentPolicy.keepVisibleAtStart,
        ).ignore();
      });
    });
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
