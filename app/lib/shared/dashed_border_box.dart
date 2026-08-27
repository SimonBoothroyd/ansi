/// A dashed herb-green outline box — the "add" affordance used across the app
/// (Library's "+ new section", the Week's "+ Add a meal"). Flutter has no
/// dashed border primitive, so a small [CustomPainter] draws it.
library;

import 'package:flutter/widgets.dart';

import '../core/theme/mise_tokens.dart';

class DashedBorderBox extends StatelessWidget {
  const DashedBorderBox({
    required this.child,
    this.color = MiseColors.herb,
    this.padding = const EdgeInsets.symmetric(vertical: 11, horizontal: 12),
    super.key,
  });

  final Widget child;
  final Color color;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      painter: _DashedRectPainter(color),
      child: Padding(padding: padding, child: child),
    );
  }
}

class _DashedRectPainter extends CustomPainter {
  _DashedRectPainter(this.color);

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1;
    final rrect = RRect.fromRectAndRadius(
      Offset.zero & size,
      const Radius.circular(12),
    );
    final path = Path()..addRRect(rrect);
    const dash = 4.0;
    const gap = 4.0;
    for (final metric in path.computeMetrics()) {
      var distance = 0.0;
      while (distance < metric.length) {
        canvas.drawPath(metric.extractPath(distance, distance + dash), paint);
        distance += dash + gap;
      }
    }
  }

  @override
  bool shouldRepaint(covariant _DashedRectPainter oldDelegate) =>
      oldDelegate.color != color;
}
