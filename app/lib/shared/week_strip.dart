/// The week strip: seven cells in the household's week order, saying what one
/// batch does on each day. Never a calendar.
///
/// A cell's fill is the batch's state ([WeekStripFill]): cooked (solid herb),
/// keeps in the fridge (herb-soft), from the freezer (the chill blue) or past
/// the fridge window (the hatch). A dot marks a day a meal eats from it; an
/// outline marks the meal the screen is about. At most one caption fragment
/// sits underneath.
///
/// Three sizes ([WeekStripSize]): full for sheets and pages, compact inside
/// cards, and line where the surface keeps its fills for something else. The
/// days come from `week_strip_days.dart`; the strip only draws them.
library;

import 'package:flutter/widgets.dart';

import '../core/theme/ansi_theme.dart';
import '../core/theme/ansi_tokens.dart';
import '../core/week_shape.dart';
import 'week_strip_days.dart';

export 'week_strip_days.dart';

enum WeekStripSize {
  /// `Mon`, `Tue`… in filled cells.
  full,

  /// Initials in smaller filled cells.
  compact,

  /// Initials with no fills: the cook days underlined.
  line,
}

class WeekStrip extends StatelessWidget {
  const WeekStrip({
    required this.days,
    required this.shape,
    this.size = WeekStripSize.full,
    this.caption,
    super.key,
  });

  /// Seven days, offset 0 first.
  final List<WeekStripDay> days;

  /// The household's week, for the labels.
  final WeekShape shape;

  final WeekStripSize size;

  /// The one fragment underneath, or none.
  final String? caption;

  @override
  Widget build(BuildContext context) {
    final line = size == WeekStripSize.line;
    final gap = size == WeekStripSize.full ? 3.0 : 2.0;
    final cells = [
      for (var day = 0; day < 7; day++)
        WeekStripCell(
          key: ValueKey('week-strip-$day'),
          day: day < days.length ? days[day] : const WeekStripDay(),
          label: size == WeekStripSize.full
              ? shape.labelShort(day)
              : shape.labelShort(day)[0],
          size: size,
        ),
    ];
    final row = line
        ? Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              for (final cell in cells) SizedBox(width: 18, child: cell),
            ],
          )
        : Row(
            children: [
              for (final (i, cell) in cells.indexed) ...[
                if (i > 0) SizedBox(width: gap),
                Expanded(child: cell),
              ],
            ],
          );
    final caption = this.caption;
    // The caption takes the freezer's ink when the meal it is about comes out
    // of the freezer.
    final frozen = days.any(
      (d) => d.thisMeal && d.fill == WeekStripFill.frozen,
    );
    return Semantics(
      container: true,
      label: _spoken(days, shape),
      child: ExcludeSemantics(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            row,
            if (caption != null)
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Text(
                  caption,
                  style: ansiMono(
                    size: 10,
                    color: frozen ? AnsiColors.chillInk : AnsiColors.herbDeep,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// What a screen reader hears for the strip: each day that carries anything,
/// by name.
String _spoken(List<WeekStripDay> days, WeekShape shape) => [
  for (final (i, d) in days.indexed)
    if (d.fill != WeekStripFill.none || d.eats || d.thisMeal)
      [
        shape.labelFull(i),
        switch (d.fill) {
          WeekStripFill.cooked => 'cooked',
          WeekStripFill.keeps => 'in the fridge',
          WeekStripFill.frozen => 'from the freezer',
          WeekStripFill.gone => 'past the fridge window',
          WeekStripFill.none => null,
        },
        if (d.thisMeal) 'this meal' else if (d.eats) 'a meal',
      ].nonNulls.join(' '),
].join(', ');

/// One day of a [WeekStrip].
class WeekStripCell extends StatelessWidget {
  const WeekStripCell({
    required this.day,
    required this.label,
    required this.size,
    super.key,
  });

  final WeekStripDay day;
  final String label;
  final WeekStripSize size;

  @override
  Widget build(BuildContext context) =>
      size == WeekStripSize.line ? _line() : _filled();

  Widget _line() {
    final cooked = day.fill == WeekStripFill.cooked;
    return Stack(
      children: [
        Padding(
          padding: const EdgeInsets.only(bottom: 5),
          child: Text(
            label,
            textAlign: TextAlign.center,
            style: ansiMono(
              size: 10,
              color: cooked ? AnsiColors.herbDeep : AnsiColors.muted,
              weight: cooked ? FontWeight.w600 : FontWeight.w400,
            ),
          ),
        ),
        if (cooked)
          const Positioned(
            left: 4,
            right: 4,
            bottom: 0,
            height: 2,
            child: ColoredBox(color: AnsiColors.herb),
          )
        else if (day.eats)
          const Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: Center(child: _Dot(size: 3, color: AnsiColors.herbDeep)),
          ),
      ],
    );
  }

  Widget _filled() {
    final full = size == WeekStripSize.full;
    final radius = BorderRadius.circular(full ? 6 : 4);
    final (fill, ink) = switch (day.fill) {
      WeekStripFill.cooked => (AnsiColors.herb, AnsiColors.surface),
      WeekStripFill.keeps => (AnsiColors.herbSoft, AnsiColors.herbDeep),
      WeekStripFill.frozen => (AnsiColors.chill, AnsiColors.chillInk),
      WeekStripFill.gone => (AnsiColors.alarm, AnsiColors.gone),
      WeekStripFill.none => (AnsiColors.paper, AnsiColors.muted),
    };
    final outline = day.fill == WeekStripFill.frozen
        ? AnsiColors.chillInk
        : AnsiColors.herbDeep;
    return Container(
      foregroundDecoration: day.thisMeal
          ? BoxDecoration(
              border: Border.all(color: outline, width: 2),
              borderRadius: radius,
            )
          : null,
      child: ClipRRect(
        borderRadius: radius,
        child: ColoredBox(
          color: fill,
          child: Stack(
            children: [
              if (day.fill == WeekStripFill.gone)
                const Positioned.fill(child: CustomPaint(painter: _Hatch())),
              Padding(
                padding: EdgeInsets.only(
                  top: full ? 6 : 3,
                  bottom: full ? 9 : 6,
                ),
                child: Center(
                  child: Text(
                    label,
                    style: ansiMono(size: full ? 9.5 : 8.5, color: ink),
                  ),
                ),
              ),
              if (day.eats)
                Positioned(
                  left: 0,
                  right: 0,
                  bottom: full ? 3 : 2,
                  child: Center(
                    child: _Dot(size: full ? 4 : 3, color: ink),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Dot extends StatelessWidget {
  const _Dot({required this.size, required this.color});

  final double size;
  final Color color;

  // Clipped rather than decorated: the line size draws no decorated shape.
  @override
  Widget build(BuildContext context) => ClipOval(
    child: SizedBox.square(
      dimension: size,
      child: ColoredBox(color: color),
    ),
  );
}

/// The past-the-window hatch: diagonal strokes over the alarm wash.
class _Hatch extends CustomPainter {
  const _Hatch();

  @override
  void paint(Canvas canvas, Size size) {
    final stroke = Paint()
      ..color = AnsiColors.alarmLine
      ..strokeWidth = 1.5;
    for (var x = -size.height; x < size.width; x += 6) {
      canvas.drawLine(
        Offset(x, size.height),
        Offset(x + size.height, 0),
        stroke,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _Hatch old) => false;
}
