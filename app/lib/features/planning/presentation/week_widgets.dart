/// Small shared widgets for the Week screen: the selectable [Pill] used by the
/// day/slot/eater pickers, the [EaterAvatar] initial-circle, the overlapping
/// [EaterAvatarStack] shown on a meal row (design board), the [PortionsChip]
/// and the [CookMarkerLine] beneath the title (D6), and the two targets a meal
/// carries wherever it is drawn — [EatersTarget] and [RemoveTarget].
///
/// A meal is drawn three times: as the phone's dish row, as the wide day
/// pane's large entry and as one line of the wide agenda. The pieces those
/// spellings share live here, so no two of them can print different facts or
/// open different doors.
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

/// What a meal's title READS as: the dish it names, or the standing words for
/// a target that is gone.
///
/// Both spellings of "gone" are here rather than at each drawing, because a
/// deleted recipe and a deleted ingredient are different sentences and every
/// surface must say the same one.
String mealTitleText(PlanEntry entry) =>
    entry.title ??
    (entry.isIngredient ? '(deleted ingredient)' : '(deleted recipe)');

/// Where a meal's title GOES, or null when there is nothing to open.
///
/// The thing it names: a recipe's page, carrying the week it is planned in
/// (`?week=`) so that page can offer the week door beside its own Edit, or —
/// for a bare ingredient (A-D5: an ingredient detail link at most, never a
/// recipe door on a row that is not a recipe) — its ingredient page, plain,
/// since a snack has no recipe to vary. A deleted target has no page, so the
/// title is inert and the meal's other targets carry the row.
String? mealTitleRoute(PlanEntry entry, {required String weekKey}) {
  if (entry.title == null) return null;
  return entry.isIngredient
      ? '/ingredients/${entry.ingredientId}'
      : '/recipes/${entry.recipeId}?week=$weekKey';
}

/// The portions a meal's chip should print, or null when there is no chip to
/// draw: an override only earns one when it DIFFERS from what its eaters would
/// have demanded on their own (their factors summed).
int? portionsChipFor(PlanEntry entry, List<Member> roster) {
  final override = entry.portions;
  if (override == null) return null;
  final usual = eatersDemand(entry.eaterIds, {for (final m in roster) m.id: m});
  return (override - usual).abs() > 1e-9 ? override : null;
}

/// The portions chip and the eater avatars as ONE tap target (E7), opening
/// the meal editor.
///
/// When a meal has neither — nobody eating and no override — the cluster
/// would otherwise be empty, which is both an untappable target and a silent
/// rendering of a real data condition (the macro lens excludes such an entry
/// with a reason). It says `nobody` instead: the state, named, and something
/// to aim at.
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
      // Vertical padding is the hit area, not decoration: the avatars are
      // 24 pt tall and this brings the target to ~44.
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

/// The `−` (E3): removes the meal, and hands back an undo.
///
/// Muted, not red. A destructive glyph on every row of a resting screen
/// shouts, and the colour was never what made this safe — the undo is. There
/// is deliberately no confirm dialog: it would tax every removal to prevent a
/// rare mis-tap, and everything needed to put the meal back is in hand.
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
    // Captured BEFORE the write: the undo fires from a toast up to six
    // seconds later, by which time this row is certainly gone — it is the row
    // that was just removed. `ref` and this context are unusable by then; the
    // container and the root overlay are not (`shared/write.dart`).
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
      // What would come back, in the words the row used: an undo you cannot
      // audit is a promise, not a control.
      detail: _undoDetail(),
      onUndo: () => unawaited(
        // The same door every other post-await write goes through
        // (`shared/write.dart`), so a failed undo says so instead of
        // vanishing.
        container.write(
          host,
          'put that meal back',
          // A new row with the same facts — the id was the removed one's, and
          // nothing downstream keys on it (the cook plan and the list both
          // re-derive from the week). A snack comes back as a snack, with its
          // amount: an undo that quietly dropped half the row would be worse
          // than no undo.
          () => entry.isIngredient
              ? repo.addIngredientEntry(
                  weekStart: weekStart,
                  dayOfWeek: entry.dayOfWeek,
                  mealSlot: entry.mealSlot,
                  ingredientId: entry.ingredientId!,
                  eaterIds: entry.eaterIds,
                  quantity: entry.quantity,
                  unit: entry.unit,
                  measureId: entry.measureId,
                  portions: entry.portions,
                )
              : repo.addEntry(
                  weekStart: weekStart,
                  dayOfWeek: entry.dayOfWeek,
                  mealSlot: entry.mealSlot,
                  recipeId: entry.recipeId!,
                  eaterIds: entry.eaterIds,
                  portions: entry.portions,
                ),
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

/// The lens (D8): `Everyone · Ada · Jun` — whose numbers the week is read as.
///
/// Selecting a person DIMS the meals they are not eating rather than removing
/// them: a hard filter renders a day the other person cooks for themselves as
/// an empty day, which is false. Dimming also makes a `⇄ shared` tag
/// unnecessary, because both avatars are right there.
///
/// The everyone option is called `Everyone`, never `Shared` — that word names a
/// per-entry fact, and one word cannot mean both.
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

/// The one add door a day card has (E5) — its last row, in every state.
///
/// v2 had two widgets here: a dashed `＋ Add a meal` box that existed only in
/// edit mode, and a separate `nothing planned` line that existed only in
/// presentation on an empty day. They were the same door wearing two hats,
/// and keeping them in step was a standing cost. This is one widget whose
/// only variation is its wording, so the affordance that fills a region is
/// always on the region (D5b, stated strictly).
///
/// It sits with the MEALS, above the day's total: it adds a *meal*, not a
/// number, so it belongs to the list it extends, and the macro line stays
/// what closes the card.
///
/// Deliberately not the dashed box in both states: seven permanent dashed
/// rectangles is the noise v2 built a whole mode to escape. The quiet mono
/// line carries the same door at a fraction of the weight.
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

  /// The inset around the line. The wide day pane has a margin to spend where
  /// a phone card does not.
  final EdgeInsets padding;

  /// Whether the line draws the hairline that separates it from the meals
  /// above.
  ///
  /// It does on a card, where the rule is the card's own grid. It does not in
  /// the wide agenda, where the only rules are the ones BETWEEN days — a
  /// seventh hairline inside each day would make seven days look like fourteen.
  final bool divider;

  @override
  Widget build(BuildContext context) {
    return AnsiTap(
      onTap: onTap,
      // The line is the door, so the ground is the line: a `＋` that lit on its
      // own would say the glyph is the target and the words beside it are not.
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

/// The dish row's SECOND line (D6, owner-ruled): the cook marker sits under
/// the title, not in a column beside it — so it reads as a sentence about the
/// dish, and can carry a full clause without squeezing the title.
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

  /// Whether the label may run onto further lines instead of ellipsising.
  ///
  /// A phone row has a whole width for one clause and clips what will not fit.
  /// The wide day pane wraps instead: it has no reason to shorten anything, and
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
