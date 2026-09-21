/// A dashed herb-green outline box, the app's "add" affordance. Flutter has
/// no dashed border primitive, so a small [CustomPainter] draws it.
///
/// [DashedAction] is the whole affordance: the box, an icon and a mono label.
library;

import 'package:flutter/widgets.dart';

import '../core/theme/ansi_theme.dart';
import '../core/theme/ansi_tokens.dart';

class DashedBorderBox extends StatelessWidget {
  const DashedBorderBox({
    required this.child,
    this.color = AnsiColors.herb,
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

/// A dashed row that invites: an icon, a mono label, one tap target.
///
/// The icon is an [IconData], never a "＋" glyph, which the bundled fonts
/// lack. [enabled] false greys the row and makes the tap inert.
class DashedAction extends StatelessWidget {
  const DashedAction({
    required this.icon,
    required this.label,
    required this.onTap,
    this.enabled = true,
    super.key,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: enabled ? onTap : null,
      child: DashedBorderBox(
        color: enabled ? AnsiColors.herb : AnsiColors.line,
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              icon,
              size: 12,
              color: enabled ? AnsiColors.herb : AnsiColors.muted,
            ),
            const SizedBox(width: 5),
            Flexible(
              child: Text(
                label,
                textAlign: TextAlign.center,
                overflow: TextOverflow.ellipsis,
                style: ansiMono(
                  size: 11,
                  color: enabled ? AnsiColors.herb : AnsiColors.muted,
                  letterSpacing: 0.5,
                ),
              ),
            ),
          ],
        ),
      ),
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
