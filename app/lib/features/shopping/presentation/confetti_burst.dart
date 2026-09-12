/// Confetti of the food itself — the burst that plays when this phone ticks
/// the last row of the shopping list.
///
/// About thirty pieces — Lucide glyphs the app already ships (a leaf, an ear
/// of wheat, a carrot), a filled circle for a berry, and plain rounded strips
/// — in the eight [AnsiConfetti] colours, burst from the box just ticked, arc
/// up and out across the whole width of the screen, hang at the apex, then
/// fall past the bottom, turning, and fade over the last stretch. One painter
/// driven by one animation; the pieces are dealt once from a seed so a burst
/// is the same shape every frame, and each piece leaves a little after the
/// last so the burst reads as a scatter rather than a ring.
///
/// [playConfettiBurst] is the door: it drops one [ConfettiBurst] into the
/// root overlay above everything on screen, ignoring pointers, and takes it
/// down when the last piece has fallen — so the list re-flowing underneath
/// (the row leaving its aisle for the basket) never moves the confetti.
library;

import 'dart:math';
import 'dart:ui' as ui;

import 'package:flutter/widgets.dart';
import 'package:forui/forui.dart';

import '../../../core/theme/ansi_tokens.dart';

/// What a piece is drawn as: a Lucide glyph the app already ships, or one of
/// the two plain shapes the painter draws itself.
enum ConfettiShape {
  leaf(FLucideIcons.leaf),
  wheat(FLucideIcons.wheat),
  carrot(FLucideIcons.carrot),
  berry(null),
  strip(null);

  const ConfettiShape(this.glyph);

  final IconData? glyph;
}

/// One piece of the burst, dealt once: where it flies to, how far it has
/// turned by the time it gets there, and when it leaves.
class ConfettiPiece {
  const ConfettiPiece({
    required this.shape,
    required this.color,
    required this.apex,
    required this.turn,
    required this.delay,
  });

  final ConfettiShape shape;
  final Color color;

  /// The top of the arc, relative to the origin — up is negative.
  final Offset apex;

  /// Radians turned by the apex; the fall more than doubles it.
  final double turn;

  /// How long after the burst begins this piece leaves.
  final Duration delay;
}

/// Where a piece is at one instant of its flight, relative to the origin.
typedef ConfettiFrame = ({
  Offset offset,
  double angle,
  double scale,
  double opacity,
});

const kConfettiCount = 30;

/// One piece's flight, from leaving to gone.
const kConfettiPieceDuration = Duration(milliseconds: 1500);

/// The latest a piece leaves after the burst begins.
const kConfettiMaxDelay = Duration(milliseconds: 220);

/// The whole burst: the last piece to leave, flown.
const kConfettiDuration = Duration(milliseconds: 1720);

/// How far a piece falls past its apex when the screen's edge is not further.
const kConfettiFall = 420.0;

/// Deals the burst's pieces from [seed] — the same seed deals the same burst.
///
/// The spread is the board's: about ±175 px across, 55 to 260 px up, a turn
/// of up to most of a circle either way, and a start anywhere in the first
/// [kConfettiMaxDelay]. Strips are the most common piece, so the glyphs read
/// as food against them rather than as a font sample.
List<ConfettiPiece> dealConfetti(int seed) {
  final random = Random(seed);
  double between(double a, double b) => a + random.nextDouble() * (b - a);
  return [
    for (var i = 0; i < kConfettiCount; i++)
      ConfettiPiece(
        shape: _shapeFor(random.nextDouble()),
        color: AnsiConfetti.all[random.nextInt(AnsiConfetti.all.length)],
        apex: Offset(between(-175, 175), between(-260, -55)),
        turn: between(-300, 315) * pi / 180,
        delay: Duration(
          milliseconds: random.nextInt(kConfettiMaxDelay.inMilliseconds + 1),
        ),
      ),
  ];
}

ConfettiShape _shapeFor(double roll) => switch (roll) {
  < 0.35 => ConfettiShape.strip,
  < 0.55 => ConfettiShape.wheat,
  < 0.75 => ConfettiShape.leaf,
  < 0.90 => ConfettiShape.berry,
  _ => ConfettiShape.carrot,
};

/// The board's `cel-pop` keyframes, one piece at [t] of its own flight.
///
/// A pop to 8 % (fade in, over-scale, a third of the way out), the rise to
/// the apex by 45 % on an ease-out that slows into it, a short hang, then
/// gravity from 50 % to the end — down to [fall] below the apex with the
/// drift carrying on and the turn more than doubling — fading over the last
/// 15 %. [fall] is at least [kConfettiFall]; the painter stretches it to the
/// bottom of the screen so nothing is left lying on the list.
ConfettiFrame confettiFrameAt(
  ConfettiPiece piece,
  double t, {
  double fall = kConfettiFall,
}) {
  const rise = Cubic(0.2, 0.7, 0.35, 1);
  final pop = Offset(piece.apex.dx * 0.3, piece.apex.dy * 0.45);
  if (t < 0.08) {
    final k = rise.transform(t / 0.08);
    return (
      offset: pop * k,
      angle: piece.turn * 0.25 * k,
      scale: ui.lerpDouble(0.5, 1.05, k)!,
      opacity: k,
    );
  }
  if (t < 0.45) {
    final k = rise.transform((t - 0.08) / 0.37);
    return (
      offset: Offset.lerp(pop, piece.apex, k)!,
      angle: ui.lerpDouble(piece.turn * 0.25, piece.turn, k)!,
      scale: ui.lerpDouble(1.05, 1, k)!,
      opacity: 1,
    );
  }
  if (t < 0.5) {
    return (offset: piece.apex, angle: piece.turn, scale: 1, opacity: 1);
  }
  final k = Curves.easeInQuad.transform((t - 0.5) / 0.5);
  final landing = Offset(piece.apex.dx * 1.15, piece.apex.dy + fall);
  return (
    offset: Offset.lerp(piece.apex, landing, k)!,
    angle: ui.lerpDouble(piece.turn, piece.turn * 2.2, k)!,
    scale: ui.lerpDouble(1, 0.9, k)!,
    opacity: t < 0.85 ? 1 : (1 - (t - 0.85) / 0.15).clamp(0, 1),
  );
}

/// The burst, drawn: fills whatever it is given, ignores pointers, and paints
/// [dealConfetti]'s pieces from [origin] as [animation] runs 0 → 1 across
/// [kConfettiDuration].
class ConfettiBurst extends StatelessWidget {
  const ConfettiBurst({
    required this.origin,
    required this.seed,
    required this.animation,
    super.key,
  });

  /// Where the pieces come from, in this widget's own coordinates.
  final Offset origin;
  final int seed;
  final Animation<double> animation;

  @override
  Widget build(BuildContext context) => IgnorePointer(
    child: CustomPaint(
      painter: ConfettiPainter(
        origin: origin,
        pieces: dealConfetti(seed),
        progress: animation,
      ),
      size: Size.infinite,
    ),
  );
}

class ConfettiPainter extends CustomPainter {
  ConfettiPainter({
    required this.origin,
    required this.pieces,
    required Animation<double> progress,
  }) : _progress = progress,
       super(repaint: progress);

  final Offset origin;
  final List<ConfettiPiece> pieces;
  final Animation<double> _progress;

  /// A glyph laid out once per piece at full ink; the fade re-lays it.
  final _glyphs = <int, TextPainter>{};

  @override
  void paint(Canvas canvas, Size size) {
    final elapsed = kConfettiDuration * _progress.value;
    for (var i = 0; i < pieces.length; i++) {
      final piece = pieces[i];
      final t =
          (elapsed - piece.delay).inMicroseconds /
          kConfettiPieceDuration.inMicroseconds;
      if (t <= 0 || t >= 1) continue;
      // Past the bottom edge, however high the row was.
      final toEdge = size.height - (origin.dy + piece.apex.dy) + 24;
      final frame = confettiFrameAt(piece, t, fall: max(kConfettiFall, toEdge));
      canvas
        ..save()
        ..translate(origin.dx + frame.offset.dx, origin.dy + frame.offset.dy)
        ..rotate(frame.angle)
        ..scale(frame.scale);
      _drawPiece(canvas, i, piece, frame.opacity);
      canvas.restore();
    }
  }

  void _drawPiece(Canvas canvas, int index, ConfettiPiece piece, double a) {
    final color = a < 1 ? piece.color.withValues(alpha: a) : piece.color;
    final icon = piece.shape.glyph;
    if (icon == null) {
      final paint = Paint()..color = color;
      if (piece.shape == ConfettiShape.berry) {
        canvas.drawCircle(Offset.zero, 6.5, paint);
      } else {
        canvas.drawRRect(
          RRect.fromRectAndRadius(
            Rect.fromCenter(center: Offset.zero, width: 6, height: 13),
            const Radius.circular(2),
          ),
          paint,
        );
      }
      return;
    }
    final glyph = a < 1
        ? _glyph(icon, color)
        : _glyphs.putIfAbsent(index, () => _glyph(icon, color));
    glyph.paint(canvas, -glyph.size.center(Offset.zero));
  }

  static TextPainter _glyph(IconData icon, Color color) => TextPainter(
    text: TextSpan(
      text: String.fromCharCode(icon.codePoint),
      style: TextStyle(
        fontSize: 16,
        fontFamily: icon.fontFamily,
        package: icon.fontPackage,
        color: color,
      ),
    ),
    textDirection: TextDirection.ltr,
  )..layout();

  @override
  bool shouldRepaint(ConfettiPainter old) =>
      old.origin != origin || old.pieces != pieces;
}

/// Plays one burst from [origin] — global coordinates, a box's
/// `localToGlobal` — above everything on screen, and takes it down when the
/// last piece has fallen. The root overlay, so a tab's body re-flowing
/// underneath (or scrolling) never moves it; pointers pass straight through.
void playConfettiBurst(
  BuildContext context, {
  required Offset origin,
  required int seed,
}) {
  final overlay = Overlay.of(context, rootOverlay: true);
  late final OverlayEntry entry;
  entry = OverlayEntry(
    builder: (_) => _ConfettiOverlay(
      origin: origin,
      seed: seed,
      onDone: () => entry
        ..remove()
        ..dispose(),
    ),
  );
  overlay.insert(entry);
}

/// Owns the burst's one controller for the life of its overlay entry.
class _ConfettiOverlay extends StatefulWidget {
  const _ConfettiOverlay({
    required this.origin,
    required this.seed,
    required this.onDone,
  });

  final Offset origin;
  final int seed;
  final VoidCallback onDone;

  @override
  State<_ConfettiOverlay> createState() => _ConfettiOverlayState();
}

class _ConfettiOverlayState extends State<_ConfettiOverlay>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: kConfettiDuration,
  );

  @override
  void initState() {
    super.initState();
    _controller
      ..addStatusListener((status) {
        if (status == AnimationStatus.completed) widget.onDone();
      })
      ..forward();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Positioned.fill(
    child: ConfettiBurst(
      origin: widget.origin,
      seed: widget.seed,
      animation: _controller,
    ),
  );
}
