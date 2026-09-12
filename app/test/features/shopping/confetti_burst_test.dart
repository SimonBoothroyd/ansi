import 'package:ansi/core/theme/ansi_tokens.dart';
import 'package:ansi/features/shopping/presentation/confetti_burst.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('dealConfetti', () {
    test('deals thirty pieces inside the board’s spread, in its colours', () {
      final pieces = dealConfetti(7);
      expect(pieces, hasLength(kConfettiCount));
      for (final p in pieces) {
        expect(p.apex.dx.abs(), lessThanOrEqualTo(175));
        expect(p.apex.dy, inInclusiveRange(-260, -55));
        expect(p.delay, lessThanOrEqualTo(kConfettiMaxDelay));
        expect(AnsiConfetti.all, contains(p.color));
      }
      // Food and strips both, not a font sample and not plain paper.
      expect(pieces.map((p) => p.shape).toSet().length, greaterThan(2));
      expect(pieces.any((p) => p.shape == ConfettiShape.strip), isTrue);
      expect(pieces.any((p) => p.shape.glyph != null), isTrue);
    });

    test('the same seed deals the same burst', () {
      final a = dealConfetti(42);
      final b = dealConfetti(42);
      for (var i = 0; i < a.length; i++) {
        expect(a[i].apex, b[i].apex);
        expect(a[i].shape, b[i].shape);
        expect(a[i].delay, b[i].delay);
      }
    });
  });

  group('confettiFrameAt', () {
    const piece = ConfettiPiece(
      shape: ConfettiShape.leaf,
      color: AnsiConfetti.tomato,
      apex: Offset(100, -200),
      turn: 1,
      delay: Duration.zero,
    );

    test('leaves faint and small, sits at the apex through the hang', () {
      final start = confettiFrameAt(piece, 0);
      expect(start.opacity, 0);
      expect(start.scale, 0.5);
      expect(start.offset, Offset.zero);
      for (final t in [0.45, 0.48, 0.5]) {
        final frame = confettiFrameAt(piece, t);
        expect(frame.offset, piece.apex, reason: 'at $t');
        expect(frame.opacity, 1);
      }
    });

    test('falls at least the board’s drop, further to a lower edge, and is '
        'gone at the end', () {
      final end = confettiFrameAt(piece, 1);
      expect(end.offset.dy, piece.apex.dy + kConfettiFall);
      expect(end.offset.dx, closeTo(piece.apex.dx * 1.15, 1e-9));
      expect(end.opacity, 0);
      expect(confettiFrameAt(piece, 0.85).opacity, 1);
      final low = confettiFrameAt(piece, 1, fall: 900);
      expect(low.offset.dy, piece.apex.dy + 900);
    });

    test('gravity: the second half of the fall covers more than the first', () {
      final top = confettiFrameAt(piece, 0.5).offset.dy;
      final mid = confettiFrameAt(piece, 0.75).offset.dy;
      final end = confettiFrameAt(piece, 1).offset.dy;
      expect(end - mid, greaterThan(mid - top));
    });
  });

  testWidgets('the burst draws above whatever it is given and lets taps '
      'through', (tester) async {
    var taps = 0;
    late AnimationController controller;
    await tester.pumpWidget(
      Directionality(
        textDirection: TextDirection.ltr,
        child: Stack(
          children: [
            GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () => taps++,
              child: const SizedBox.expand(),
            ),
            _Host(onController: (c) => controller = c),
          ],
        ),
      ),
    );
    controller.forward();
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.byType(ConfettiBurst), findsOneWidget);
    await tester.tap(find.byType(ConfettiBurst), warnIfMissed: false);
    expect(taps, 1);
    await tester.pump(kConfettiDuration);
  });
}

class _Host extends StatefulWidget {
  const _Host({required this.onController});

  final ValueChanged<AnimationController> onController;

  @override
  State<_Host> createState() => _HostState();
}

class _HostState extends State<_Host> with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: kConfettiDuration,
  );

  @override
  void initState() {
    super.initState();
    widget.onController(_controller);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Positioned.fill(
    child: ConfettiBurst(
      origin: const Offset(40, 300),
      seed: 3,
      animation: _controller,
    ),
  );
}
