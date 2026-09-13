/// The dotted rule that carries the eye from a name to the number set against
/// it — the leader of a well-set table in the back of a cookbook.
///
/// It exists so a fact can sit in a **column** instead of chasing the thing it
/// belongs to: the Library's ledger puts every book's counts and every recipe's
/// stats down one right-hand edge, and the leader is what keeps a short name
/// and a long one pointing at the same place. Flutter has no dotted-line
/// primitive, so a small [CustomPainter] draws it, exactly as
/// `dashed_border_box.dart` draws the dashed box.
///
/// It is the flexible member of its row — it *is* an [Expanded] — so a caller
/// writes it between two fixed cells and nothing else has to know how wide the
/// gap turned out to be.
library;

import 'package:flutter/widgets.dart';

import '../core/theme/ansi_tokens.dart';

class AnsiDottedLeader extends StatelessWidget {
  const AnsiDottedLeader({
    this.gap = 8,
    this.color = AnsiColors.line,
    super.key,
  });

  /// The clear space either side of the dots, so the leader never touches the
  /// letters it runs between.
  final double gap;

  final Color color;

  @override
  Widget build(BuildContext context) => Expanded(
    child: Padding(
      padding: EdgeInsets.symmetric(horizontal: gap),
      child: CustomPaint(
        painter: _DottedLinePainter(color),
        // The line rides a hair above the baseline of the text either side of
        // it, which is what a leader in print does: it is set to the row's
        // middle and the row is centred on its own text.
        child: const SizedBox(height: 1, width: double.infinity),
      ),
    ),
  );
}

class _DottedLinePainter extends CustomPainter {
  const _DottedLinePainter(this.color);

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = 1
      ..strokeCap = StrokeCap.round;
    const step = 4.0;
    final y = size.height / 2;
    for (var x = 0.0; x < size.width; x += step) {
      canvas.drawLine(Offset(x, y), Offset(x + 1, y), paint);
    }
  }

  @override
  bool shouldRepaint(covariant _DottedLinePainter oldDelegate) =>
      oldDelegate.color != color;
}
