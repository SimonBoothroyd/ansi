/// Shared widgets for the Week screen: [Pill], [EaterAvatar],
/// [EaterAvatarStack], [PortionsChip], [CookMarkerLine], and a meal's two
/// targets, [EatersTarget] and [RemoveTarget]. The phone row, the wide day pane
/// and the wide agenda all draw a meal from these.
library;

import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:forui/forui.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

import '../../../core/theme/ansi_theme.dart';
import '../../../core/theme/ansi_tokens.dart';
import '../../../core/units/portions.dart';
import '../../../core/words.dart';
import '../../../shared/ansi_chip.dart';
import '../../../shared/ansi_tap.dart';
import '../../../shared/ansi_toast.dart';
import '../../../shared/write.dart';
import '../../account/data/household_providers.dart';
import '../data/planning_providers.dart';
import '../domain/planning.dart';
import 'meal_editor_sheet.dart';
import 'week_format.dart';
import 'week_variant_format.dart';
import 'week_view_models.dart';

/// A rounded, tappable label that fills herb-green when [selected]. An [icon]
/// renders instead of the label (the bundled fonts lack glyphs like ＋).
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
    return AnsiTap(
      onTap: onTap,
      radius: AnsiRadii.pill,
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

/// The avatar palette, indexed by a member's roster position so a person keeps
/// one colour everywhere.
const _memberPalette = [
  AnsiColors.herb,
  AnsiColors.ink,
  AnsiColors.aging,
  AnsiColors.gone,
];

/// The colour for the member at roster position [rank].
Color memberColor(int rank) => _memberPalette[rank % _memberPalette.length];

/// An initial-circle for a household member, ringed white so it reads when
/// overlapped. [dimmed] greys it; [color] is the member's roster colour.
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

/// The overlapping avatars on a meal row: the [roster] members in [eaterIds],
/// in roster order.
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

/// `3 portions` — drawn only when the entry's portions differ from its eaters'
/// demand.
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

/// A meal's title text: the thing it names, or [deletedTargetLabel].
String mealTitleText(PlanEntry entry) =>
    entry.title ?? deletedTargetLabel(entry);

/// Where a meal's title goes: a recipe's page with the week it is planned in
/// (`?week=`), a bare ingredient's page, or null for a deleted target or a meal
/// eaten out.
String? mealTitleRoute(PlanEntry entry, {required String weekKey}) {
  if (entry.title == null) return null;
  return switch (entry.kind) {
    PlanEntryKind.recipe => '/recipes/${entry.recipeId}?week=$weekKey',
    PlanEntryKind.ingredient => '/ingredients/${entry.ingredientId}',
    PlanEntryKind.out => null,
  };
}

/// The portions a meal's chip prints, or null when the override equals what its
/// eaters' factors sum to.
int? portionsChipFor(PlanEntry entry, List<Member> roster) {
  final override = entry.portions;
  if (override == null) return null;
  final usual = eatersDemand(entry.eaterIds, {for (final m in roster) m.id: m});
  return (override - usual).abs() > 1e-9 ? override : null;
}

/// The portions chip and eater avatars as one tap target, opening the meal
/// editor. With no eaters and no override it says `nobody`, so the target is
/// never empty.
class EatersTarget extends StatelessWidget {
  const EatersTarget({
    required this.entry,
    required this.roster,
    required this.portions,
    super.key,
  });

  final PlanEntry entry;
  final List<Member> roster;
  final int? portions;

  @override
  Widget build(BuildContext context) {
    final nobody = entry.eaterIds.isEmpty && portions == null;
    return AnsiTap(
      onTap: () => showMealEditorSheet(context, entry: entry),
      semanticsLabel: 'Who is eating',
      // Vertical padding is the hit area: it brings the 24 pt avatars to ~44.
      padding: const EdgeInsets.fromLTRB(8, 10, 4, 10),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (portions != null) ...[
            PortionsChip(portions: portions!),
            const SizedBox(width: 8),
          ],
          if (nobody)
            Text('nobody', style: ansiMono(size: 10, color: AnsiColors.muted))
          else
            EaterAvatarStack(roster: roster, eaterIds: entry.eaterIds.toSet()),
        ],
      ),
    );
  }
}

/// The `−`: removes the meal and offers an undo toast. Muted, with no confirm
/// dialog, because the undo makes it safe.
class RemoveTarget extends ConsumerWidget {
  const RemoveTarget({required this.entry, required this.roster, super.key});

  final PlanEntry entry;
  final List<Member> roster;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return AnsiTap(
      onTap: () => unawaited(_remove(context, ref)),
      semanticsLabel: 'Remove the meal',
      color: AnsiColors.muted,
      padding: const EdgeInsets.fromLTRB(8, 10, 4, 10),
      child: const Icon(FLucideIcons.minus, size: 16),
    );
  }

  Future<void> _remove(BuildContext context, WidgetRef ref) async {
    final repo = ref.read(planningRepositoryProvider);
    final weekStart = ref.read(viewedWeekStartProvider);
    // Captured before the write: the undo fires from a toast after this row is
    // gone, when `ref` and this context are unusable (`shared/write.dart`).
    final container = ProviderScope.containerOf(context, listen: false);
    final host = hostContextOf(context);
    final day = ref.read(weekShapeProvider).labelFull(entry.dayOfWeek);
    final removed = await ref.writeOk(
      context,
      'remove that meal',
      () => repo.removeEntry(entry.id),
    );
    if (!removed) return;
    showAnsiUndoToast(
      // The host outlives the row — and the row is the one just removed.
      // ignore: use_build_context_synchronously
      host.context,
      what: 'Removed ${entry.title ?? 'that meal'} from $day.',
      // What would come back, in the row's own words.
      detail: _undoDetail(),
      onUndo: () => unawaited(
        // Through `shared/write.dart`, so a failed undo reports itself.
        container.write(
          host,
          'put that meal back',
          // A new row with the same facts; nothing downstream keys on the old
          // id. Each kind comes back with everything it carried.
          () => switch (entry.kind) {
            PlanEntryKind.ingredient => repo.addIngredientEntry(
              weekStart: weekStart,
              dayOfWeek: entry.dayOfWeek,
              mealSlot: entry.mealSlot,
              ingredientId: entry.ingredientId!,
              eaterIds: entry.eaterIds,
              quantity: entry.quantity,
              unit: entry.unit,
              measureId: entry.measureId,
              portions: entry.portions,
            ),
            PlanEntryKind.out => repo.addOutEntry(
              weekStart: weekStart,
              dayOfWeek: entry.dayOfWeek,
              mealSlot: entry.mealSlot,
              label: entry.label!,
              eaterIds: entry.eaterIds,
              macros: entry.macros,
              portions: entry.portions,
            ),
            PlanEntryKind.recipe => repo.addEntry(
              weekStart: weekStart,
              dayOfWeek: entry.dayOfWeek,
              mealSlot: entry.mealSlot,
              recipeId: entry.recipeId!,
              eaterIds: entry.eaterIds,
              portions: entry.portions,
            ),
          },
        ),
      ),
    );
  }

  String _undoDetail() {
    final names = [
      for (final m in roster)
        if (entry.eaterIds.contains(m.id)) m.displayName,
    ];
    final demand = eatersDemand(entry.eaterIds, {
      for (final m in roster) m.id: m,
    });
    final portions = entry.portions?.toDouble() ?? demand;
    return [
      entry.mealSlot.toLowerCase(),
      if (names.isNotEmpty) names.join(' & '),
      formatPortions(portions),
    ].join(' · ');
  }
}

/// The lens: `Everyone · Ada · Jun` — whose numbers the week is read as.
/// Selecting a person dims the meals they are not eating rather than removing
/// them.
class WeekLensRow extends StatelessWidget {
  const WeekLensRow({required this.lens, required this.roster, super.key});

  final ValueNotifier<String?> lens;
  final List<Member> roster;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 0),
      child: Row(
        children: [
          Text('for', style: ansiMono(size: 10, color: AnsiColors.muted)),
          const SizedBox(width: 8),
          AnsiChip(
            label: 'Everyone',
            selected: lens.value == null,
            onTap: () => lens.value = null,
          ),
          for (final (i, m) in roster.indexed)
            Padding(
              padding: const EdgeInsets.only(left: 8),
              child: AnsiChip(
                label: m.displayName,
                selected: lens.value == m.id,
                icon: EaterAvatar(member: m, color: memberColor(i)),
                onTap: () => lens.value = m.id,
              ),
            ),
        ],
      ),
    );
  }
}

/// A day's one add door: the last row of its meals, above the day's total. It
/// reads `nothing planned` on an empty day.
class AddMealLine extends StatelessWidget {
  const AddMealLine({
    required this.empty,
    required this.onTap,
    this.padding = const EdgeInsets.fromLTRB(16, 10, 16, 12),
    this.divider = true,
    super.key,
  });

  /// Whether the day has no meals — the wording, and nothing else, changes.
  final bool empty;
  final VoidCallback onTap;

  /// The inset around the line.
  final EdgeInsets padding;

  /// Whether the line draws a hairline above it. True on a card; false in the
  /// wide agenda, where rules only separate days.
  final bool divider;

  @override
  Widget build(BuildContext context) {
    return AnsiTap(
      onTap: onTap,
      // The whole line is the target, so the whole line highlights.
      radius: 0,
      child: Container(
        padding: padding,
        decoration: BoxDecoration(
          border: divider
              ? const Border(top: BorderSide(color: AnsiColors.line))
              : null,
        ),
        child: Row(
          children: [
            Icon(
              FLucideIcons.plus,
              size: 11,
              color: empty ? AnsiColors.muted : AnsiColors.herb,
            ),
            const SizedBox(width: 6),
            Text(
              empty ? 'nothing planned' : 'add a meal',
              style: ansiMono(
                size: 11,
                color: empty ? AnsiColors.muted : AnsiColors.herb,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// The dish row's second line: the cook marker, under the title so it can carry
/// a full clause.
class CookMarkerLine extends ConsumerWidget {
  const CookMarkerLine({
    required this.marker,
    this.todayDayOfWeek,
    this.wrap = false,
    super.key,
  });

  final CookMarker marker;

  /// Today's offset within the week when the current week is on screen — see
  /// [cookMarkerLabel].
  final int? todayDayOfWeek;

  /// Whether the label wraps instead of ellipsising. The wide day pane wraps:
  /// half of `from Tuesday's batch` names the wrong day.
  final bool wrap;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final frozen = marker.kind == CookMarkerKind.freezerShare;
    return Row(
      children: [
        if (marker.kind == CookMarkerKind.cooks) ...[
          MiniFreshBar(position: marker.position),
          const SizedBox(width: 6),
        ],
        Flexible(
          child: Text(
            cookMarkerLabel(
              marker,
              ref.watch(weekShapeProvider),
              todayDayOfWeek: todayDayOfWeek,
            ),
            overflow: wrap ? TextOverflow.clip : TextOverflow.ellipsis,
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

/// "edited for this week", beside the cook marker. A printed fact, not a
/// target. Every planned day of the recipe wears it, because the variant is per
/// `(week, recipe)`.
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

/// The agenda's one-glyph mark for a meal eaten out: a hollow dot.
const kMealOutIcon = FLucideIcons.circle;

/// The `out` tag a meal eaten out wears where a dish wears its cook marker. Not
/// a target.
class OutTag extends StatelessWidget {
  const OutTag({super.key});

  @override
  Widget build(BuildContext context) => Container(
    decoration: BoxDecoration(
      color: AnsiColors.paper,
      border: Border.all(color: AnsiColors.line),
      borderRadius: BorderRadius.circular(7),
    ),
    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
    child: Text('out', style: ansiMono(size: 9, color: AnsiColors.muted)),
  );
}

/// A meal eaten out's second line: the [OutTag] and the stated per-portion
/// figures, or the words for their absence ([outMacroLine]).
class OutMealLine extends StatelessWidget {
  const OutMealLine({required this.entry, this.size = 10.5, super.key});

  final PlanEntry entry;

  /// The line's size — the phone row's 10.5, the wide day pane's 11.
  final double size;

  @override
  Widget build(BuildContext context) => Row(
    children: [
      const OutTag(),
      const SizedBox(width: 6),
      Flexible(
        child: Text(
          outMacroLine(entry),
          overflow: TextOverflow.ellipsis,
          style: ansiMono(size: size, color: AnsiColors.muted),
        ),
      ),
    ],
  );
}

/// The fresh→gone gradient at 26px, with a notch where this day sits in the
/// batch's fridge window.
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
