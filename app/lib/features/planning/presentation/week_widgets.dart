/// Small shared widgets for the Week screen: the selectable [Pill] used by the
/// day/slot/eater pickers, the [EaterAvatar] initial-circle, and the overlapping
/// [EaterAvatarStack] shown on a meal row (design board).
library;

import 'package:flutter/widgets.dart';

import '../../../core/theme/ansi_theme.dart';
import '../../../core/theme/ansi_tokens.dart';
import '../domain/planning.dart';

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
