/// The dotted rule that carries the eye from a name to the number set against
/// it, so facts can sit in a right-hand column.
///
/// A small [CustomPainter] draws it, as in `dashed_border_box.dart`. It is an
/// [Expanded], written between two fixed cells.
library;

import 'package:flutter/widgets.dart';

import '../core/theme/ansi_tokens.dart';

class AnsiDottedLeader extends StatelessWidget {
  const AnsiDottedLeader({
    this.gap = 8,
    this.color = AnsiColors.line,
    super.key,
  });

  /// The clear space either side of the dots.
  final double gap;

  final Color color;

  @override
  Widget build(BuildContext context) => Expanded(
    child: Padding(
      padding: EdgeInsets.symmetric(horizontal: gap),
      child: CustomPaint(
        painter: _DottedLinePainter(color),
        // Set to the row's middle, a hair above the text's baseline.
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
