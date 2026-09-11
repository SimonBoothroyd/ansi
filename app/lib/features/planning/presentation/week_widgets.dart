/// Small shared widgets for the Week screen: the selectable [Pill] used by the
/// day/slot/eater pickers, the [EaterAvatar] initial-circle, the overlapping
/// [EaterAvatarStack] shown on a meal row (design board), and — since the week
/// redesign — the two pieces of a presentation dish row: the [PortionsChip]
/// and the [CookMarkerLine] beneath the title (D6).
library;

import 'package:flutter/widgets.dart';
import 'package:forui/forui.dart';

import '../../../core/theme/ansi_theme.dart';
import '../../../core/theme/ansi_tokens.dart';
import '../../../core/words.dart';
import '../domain/planning.dart';
import 'week_format.dart';
import 'week_variant_format.dart';

/// A rounded, tappable label that fills herb-green when [selected] (design
/// board `.pchip` / `.wkchip`). An [icon] renders instead of the label (the
/// bundled fonts lack glyphs like ＋, so affordance pills use icons).
class Pill extends StatelessWidget {
  const Pill({
    required this.selected,
    required this.onTap,
    this.label = '',
    this.icon,
    super.key,
  });

  final String label;
  final IconData? icon;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          color: selected ? AnsiColors.herb : AnsiColors.surface,
          border: Border.all(
            color: selected ? AnsiColors.herb : AnsiColors.line,
          ),
          borderRadius: BorderRadius.circular(999),
        ),
        child: icon != null
            // Sized to the text pills' line height so both pill kinds match.
            ? SizedBox(
                height: 16,
                child: Center(
                  child: Icon(
                    icon,
                    size: 14,
                    color: selected ? AnsiColors.surface : AnsiColors.muted,
                  ),
                ),
              )
            : Text(
                label,
                style: ansiMono(
                  size: 12,
                  color: selected ? AnsiColors.surface : AnsiColors.muted,
                ),
              ),
      ),
    );
  }
}

/// The avatar palette, indexed by a member's position in the roster so the same
/// person keeps a colour everywhere (Ada green, Jun ink — design board).
const _memberPalette = [
  AnsiColors.herb,
  AnsiColors.ink,
  AnsiColors.aging,
  AnsiColors.gone,
];

/// The colour for the member at roster position [rank].
Color memberColor(int rank) => _memberPalette[rank % _memberPalette.length];

/// A small initial-circle for a household member (design board `.av`), with a
/// white ring so it reads when overlapped. [dimmed] greys it for a member who
/// isn't selected/eating; [color] is the member's roster colour.
class EaterAvatar extends StatelessWidget {
  const EaterAvatar({
    required this.member,
    this.color = AnsiColors.herb,
    this.dimmed = false,
    super.key,
  });

  final Member member;
  final Color color;
  final bool dimmed;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 24,
      height: 24,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: dimmed ? AnsiColors.line : color,
        shape: BoxShape.circle,
        border: Border.all(color: AnsiColors.surface, width: 1.5),
      ),
      child: Text(
        member.initial,
        style: ansiMono(
          size: 11,
          color: dimmed ? AnsiColors.muted : AnsiColors.surface,
          weight: FontWeight.w600,
        ),
      ),
    );
  }
}

/// The overlapping avatar cluster on a meal row: the [roster] members who are
/// in [eaterIds], in roster order, each in their roster colour (board `.avs`).
class EaterAvatarStack extends StatelessWidget {
  const EaterAvatarStack({
    required this.roster,
    required this.eaterIds,
    super.key,
  });

  final List<Member> roster;
  final Set<String> eaterIds;

  @override
  Widget build(BuildContext context) {
    // Keep roster order (stable A, J) rather than the stored eater order.
    final eating = [
      for (var i = 0; i < roster.length; i++)
        if (eaterIds.contains(roster[i].id)) (i, roster[i]),
    ];
    if (eating.isEmpty) return const SizedBox.shrink();
    const size = 24.0;
    const step = 15.0; // overlap: each avatar shifts by < its width
    return SizedBox(
      width: size + (eating.length - 1) * step,
      height: size,
      child: Stack(
        children: [
          for (var j = 0; j < eating.length; j++)
            Positioned(
              left: j * step,
              child: EaterAvatar(
                member: eating[j].$2,
                color: memberColor(eating[j].$1),
              ),
            ),
        ],
      ),
    );
  }
}

/// `3 portions` — drawn ONLY when the entry's portions differ from its eater
/// count. A silent override is a fact about the cook plan and the shopping
/// list that the week could not otherwise show you; an override that merely
/// equals the eater count is not worth a chip.
class PortionsChip extends StatelessWidget {
  const PortionsChip({required this.portions, super.key});

  final int portions;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
      decoration: BoxDecoration(
        color: AnsiColors.paper,
        border: Border.all(color: AnsiColors.line),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        '$portions ${plural(portions, 'portion')}',
        style: ansiMono(size: 10, color: AnsiColors.muted),
      ),
    );
  }
}

/// The dish row's SECOND line (D6, owner-ruled): the cook marker sits under
/// the title, not in a column beside it — so it reads as a sentence about the
/// dish, and can carry a full clause without squeezing the title.
class CookMarkerLine extends StatelessWidget {
  const CookMarkerLine({required this.marker, this.todayDayOfWeek, super.key});

  final CookMarker marker;

  /// Today's index when the current week is on screen — see [cookMarkerLabel].
  final int? todayDayOfWeek;

  @override
  Widget build(BuildContext context) {
    final frozen = marker.kind == CookMarkerKind.freezerShare;
    return Row(
      children: [
        if (marker.kind == CookMarkerKind.cooks) ...[
          MiniFreshBar(position: marker.position),
          const SizedBox(width: 6),
        ],
        Flexible(
          child: Text(
            cookMarkerLabel(marker, todayDayOfWeek: todayDayOfWeek),
            overflow: TextOverflow.ellipsis,
            style: ansiMono(
              size: 10.5,
              color: frozen ? AnsiColors.frozen : AnsiColors.muted,
            ),
          ),
        ),
        if (frozen) ...[
          const SizedBox(width: 4),
          const Icon(
            FLucideIcons.snowflake,
            size: 11,
            color: AnsiColors.frozen,
          ),
        ] else if (marker.kind == CookMarkerKind.fromBatch) ...[
          const SizedBox(width: 6),
          MiniFreshBar(position: marker.position),
        ],
      ],
    );
  }
}

/// "edited for this week", beside the cook marker on the row's second line.
///
/// The cook marker's second, quieter voice — the one the board already uses
/// for *"from Monday's batch"*: derived, not fresh. It is a fact the row
/// prints and not a target, so it never moves onto the title line.
///
/// Every planned day of the recipe wears it, because the variant is per
/// `(week, recipe)`: one pot, one line set, and two rows that cannot disagree.
class EditedForThisWeekMark extends StatelessWidget {
  const EditedForThisWeekMark({super.key});

  @override
  Widget build(BuildContext context) => Container(
    decoration: BoxDecoration(
      color: AnsiColors.paper,
      border: Border.all(color: AnsiColors.line),
      borderRadius: BorderRadius.circular(7),
    ),
    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
    child: Text(
      kEditedForThisWeek,
      style: ansiMono(size: 9, color: AnsiColors.muted),
    ),
  );
}

/// The design board's fresh→gone gradient at 26px, with a notch showing where
/// this day sits in the batch's fridge window.
class MiniFreshBar extends StatelessWidget {
  const MiniFreshBar({required this.position, super.key});

  /// 0 = just cooked, 1 = the end of the window.
  final double position;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 26,
      height: 5,
      child: CustomPaint(painter: _MiniFreshPainter(position)),
    );
  }
}

class _MiniFreshPainter extends CustomPainter {
  const _MiniFreshPainter(this.position);

  final double position;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    final rrect = RRect.fromRectAndRadius(rect, const Radius.circular(2.5));
    canvas.drawRRect(
      rrect,
      Paint()
        ..shader = const LinearGradient(
          colors: [AnsiColors.fresh, AnsiColors.aging, AnsiColors.gone],
        ).createShader(rect),
    );
    // The notch: where this meal falls in the window.
    final x = position.clamp(0.0, 1.0) * (size.width - 2);
    canvas.drawRect(
      Rect.fromLTWH(x, -1, 2, size.height + 2),
      Paint()..color = AnsiColors.ink,
    );
  }

  @override
  bool shouldRepaint(_MiniFreshPainter old) => old.position != position;
}
