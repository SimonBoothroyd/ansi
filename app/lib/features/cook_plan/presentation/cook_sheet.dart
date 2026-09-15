/// The Cook plan at the expanded band — the whole week as ONE schedule sheet.
///
/// **Why not cards.** The phone draws a card per recipe because a hand's width
/// holds one; a desk given the same cards has to put them in a grid, and a grid
/// of cards is mostly air around one timeline with a hole wherever a card is
/// short. The width's real dividend is a SHARED AXIS: seven day columns drawn
/// once, every recipe a row against them, so "what am I cooking on Tuesday" is
/// a glance down a column instead of a comparison of seven little bars.
///
/// **The row.** The recipe and its week-level facts on the left; the track in
/// the middle — a herb tick with its `×N` on the cook day, a herb-soft band
/// for as long as the batch keeps, a dot on every day it feeds, amber for a
/// day past the window; and on the right the same sentences the phone's tile
/// prints, with the split or freezer note hanging in the row's margin behind a
/// 2 px rule rather than in a box.
///
/// **It is the phone's plan, not a second one.** One view model
/// (`cook_view_models.dart`), one set of words and one set of rulings about
/// them ([SessionSpeech]), one keep-window geometry ([CookTimelineSpec]
/// through [cookTrackDays]) and the same doors: the recipe title opens the
/// recipe for this week, the whole-batch nudge toggles the same display state,
/// and a component gap offers the same fix. What changes is the shape.
library;

import 'package:flutter/widgets.dart';
import 'package:forui/forui.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

import '../../../core/theme/ansi_theme.dart';
import '../../../core/theme/ansi_tokens.dart';
import '../../../core/week_shape.dart';
import '../../../shared/guarded_navigation.dart';
import '../../account/data/household_providers.dart';
import '../../planning/presentation/week_view_models.dart';
import '../../recipes/presentation/recipe_view_models.dart';
import '../domain/cook_plan.dart';
import 'cook_format.dart';
import 'cook_view_models.dart';

/// How wide the schedule sheet is ever drawn: the recipe column, seven days at
/// their full 66 px pitch, and the column of words, centred in the pane. Past
/// this the sheet stops growing — a seven-day axis wider than this is a poster,
/// not a planner.
const kCookSheetWidth = 1140.0;

/// The recipe and its week-level facts.
const _nameColumn = 330.0;

/// The sentences at the row's end: the sessions, and the notes in the margin.
const _saysColumn = 300.0;

const _columnGap = 24.0;

/// The keep band's height, and the height of a whole day cell — band, then the
/// `×N` under the tick.
const _bandHeight = 24.0;
const _trackHeight = 46.0;

class CookSheet extends ConsumerWidget {
  const CookSheet({required this.plan, super.key});

  final CookPlan plan;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final shape = ref.watch(weekShapeProvider);
    final weekStart = ref.watch(viewedWeekStartProvider);
    // The herb day is only a day of the week containing today; read off the day
    // provider, so a midnight re-fires it and nothing else does.
    final today = weekStart == ref.watch(currentWeekStartProvider)
        ? shape.offsetOf(ref.watch(todayProvider))
        : null;

    final rows = <Widget>[
      for (final recipe in plan.recipes) ...[
        // Two denominations, two rows: a recipe that is both planned and
        // demanded as a component states its portions and its batches on their
        // own rows, never summed.
        if (recipe.mealSessions.isNotEmpty) _MealRow(recipe: recipe),
        if (recipe.componentSessions.isNotEmpty) _ComponentRow(recipe: recipe),
      ],
      // Components the plan could not derive: a named gap, never a ×1.
      for (final gap in plan.gaps) _GapRow(gap: gap),
    ];

    return Padding(
      padding: const EdgeInsets.fromLTRB(0, 18, 0, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _HeadRow(weekStart: weekStart, shape: shape, today: today),
          const _Rule(),
          // The faint verticals belong to the sheet, not to a row: every row
          // reads against the same seven days, so the lines run behind all of
          // them at once.
          Stack(
            children: [
              const Positioned.fill(
                child: CustomPaint(painter: _DayVerticalsPainter()),
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  for (final (i, row) in rows.indexed) ...[
                    if (i > 0) const _Rule(),
                    row,
                  ],
                ],
              ),
            ],
          ),
          const _Rule(),
          const _TrackKey(),
        ],
      ),
    );
  }
}

/// The seven days, once, over the whole sheet. Today takes the herb tick above
/// its initials.
class _HeadRow extends StatelessWidget {
  const _HeadRow({
    required this.weekStart,
    required this.shape,
    required this.today,
  });

  final DateTime weekStart;
  final WeekShape shape;
  final int? today;

  @override
  Widget build(BuildContext context) {
    return _SheetRow(
      name: Align(
        alignment: Alignment.bottomLeft,
        child: Padding(
          padding: const EdgeInsets.only(bottom: 3),
          child: Text(
            'RECIPE',
            style: ansiMono(
              size: 9,
              color: AnsiColors.muted,
              letterSpacing: 1.4,
            ),
          ),
        ),
      ),
      track: Row(
        children: [
          for (var day = 0; day < 7; day++)
            Expanded(
              child: Column(
                children: [
                  Container(
                    height: 2,
                    margin: const EdgeInsets.fromLTRB(12, 0, 12, 7),
                    color: today == day ? AnsiColors.herb : null,
                  ),
                  Text(
                    shape.labelShort(day).toUpperCase(),
                    style: ansiMono(
                      size: 9.5,
                      color: today == day ? AnsiColors.herb : AnsiColors.muted,
                      letterSpacing: 1.1,
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.only(top: 3),
                    child: Text(
                      cookSheetDayNumber(weekStart, day),
                      style: ansiMono(
                        size: 9,
                        color: today == day
                            ? AnsiColors.herb
                            : AnsiColors.muted,
                      ),
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
      says: const SizedBox.shrink(),
      padding: const EdgeInsets.only(bottom: 9),
    );
  }
}

/// The sheet's one grid: name, track, words. Every row — the head included —
/// goes through this, which is what keeps a Tuesday in the head over the
/// Tuesdays under it.
class _SheetRow extends StatelessWidget {
  const _SheetRow({
    required this.name,
    required this.track,
    required this.says,
    this.padding = const EdgeInsets.fromLTRB(0, 20, 0, 20),
  });

  final Widget name;
  final Widget track;
  final Widget says;
  final EdgeInsets padding;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: padding,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(width: _nameColumn, child: name),
          const SizedBox(width: _columnGap),
          // The track takes what the pane leaves, so a narrower desk loses day
          // pitch and never the axis: 66 px at the cap, less below it.
          Expanded(child: track),
          const SizedBox(width: _columnGap),
          SizedBox(width: _saysColumn, child: says),
        ],
      ),
    );
  }
}

/// One recipe's meal batches: the row the Cook plan is mostly made of.
class _MealRow extends ConsumerWidget {
  const _MealRow({required this.recipe});

  final RecipeCookPlan recipe;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final shape = ref.watch(weekShapeProvider);
    final sessions = recipe.mealSessions;
    // A recipe that is also somebody's component has its component sessions on
    // their own row, so "split" here counts only the meal ones.
    final split = sessions.length > 1;
    final edited =
        (ref
                    .watch(viewedWeekOverridesProvider)
                    .asData
                    ?.value[recipe.recipeId] ??
                const [])
            .isNotEmpty;
    final speeches = [
      for (final session in sessions)
        SessionSpeech.of(
          session,
          shape,
          showWholeBatch: ref.watch(
            wholeBatchDisplayProvider(cookSessionKey(session)),
          ),
        ),
    ];
    // The title carries the week it is cooking for, so the recipe page can
    // offer "Edit for this week" beside its own Edit. Cook stays read-only.
    final weekKey = isoDateOf(ref.watch(viewedWeekStartProvider));

    return _SheetRow(
      name: _Name(
        title: recipe.title,
        facts: recipeSummaryLine(recipe, editedThisWeek: edited),
        onTap: () =>
            context.pushOnce('/recipes/${recipe.recipeId}?week=$weekKey'),
      ),
      track: CookTrack(
        rowKey: recipe.recipeId,
        days: cookTrackDays([
          for (final (i, session) in sessions.indexed)
            (session, speeches[i].trackScale),
        ]),
      ),
      says: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (final (i, session) in sessions.indexed) ...[
            if (i > 0) const SizedBox(height: 13),
            _Says(
              speech: speeches[i],
              onToggleWholeBatch: () => ref
                  .read(
                    wholeBatchDisplayProvider(cookSessionKey(session)).notifier,
                  )
                  .toggle(),
            ),
            if (session.hasFreezerRescue)
              _MarginNote.freezer(freezerNoteFor(recipe.title, session, shape)),
          ],
          if (split) _MarginNote.split(splitNoteFor(recipe)),
        ],
      ),
    );
  }
}

/// A sub-recipe's derived batches: the same row, denominated in batches and
/// titled by the plans it answers.
class _ComponentRow extends ConsumerWidget {
  const _ComponentRow({required this.recipe});

  final RecipeCookPlan recipe;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final shape = ref.watch(weekShapeProvider);
    final sessions = recipe.componentSessions;
    final parents = {for (final s in sessions) ...s.demandedBy}.toList();
    // The yield the batch math already used, off the recipe list that carries
    // it — stating the fact the arithmetic ran on, not fetching a new one.
    final denomination = ref
        .watch(recipeListProvider)
        .asData
        ?.value
        .where((r) => r.id == recipe.recipeId)
        .firstOrNull
        ?.yields
        .firstOrNull;
    final speeches = [
      for (final session in sessions)
        SessionSpeech.of(session, shape, denomination: denomination),
    ];

    return _SheetRow(
      name: _Name(
        title: componentCardTitle(recipe.title, parents),
        facts: componentSummaryLine(recipe),
        onTap: () => context.pushOnce('/recipes/${recipe.recipeId}'),
      ),
      track: CookTrack(
        rowKey: '${recipe.recipeId}-component',
        days: cookTrackDays([
          for (final (i, session) in sessions.indexed)
            (session, speeches[i].trackScale),
        ]),
      ),
      says: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (final (i, session) in sessions.indexed) ...[
            if (i > 0) const SizedBox(height: 13),
            _Says(speech: speeches[i]),
            if (session.hasFreezerRescue)
              _MarginNote.freezer(freezerNoteFor(recipe.title, session, shape)),
            if (componentLeftoverNote(
                  session,
                  shape,
                  denomination: denomination,
                )
                case final note?)
              _MarginNote.split(note),
          ],
        ],
      ),
    );
  }
}

/// A component the plan could not derive: the days a batch is wanted, no scale
/// anywhere, and the one-tap fix where there is one.
class _GapRow extends ConsumerWidget {
  const _GapRow({required this.gap});

  final ComponentGap gap;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final shape = ref.watch(weekShapeProvider);
    final parents = gap.demandedBy.map((d) => d.title).toSet().toList();
    final days = gap.demandedBy.map((d) => d.cookDay);

    return _SheetRow(
      name: _Name(
        title: componentCardTitle(gap.title, parents),
        facts: gapSummaryLine(gap),
      ),
      track: CookTrack(
        rowKey: '${gap.recipeId}-gap',
        days: cookTrackDaysForGap(days),
      ),
      says: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Expanded(
                child: Text(
                  componentWhenLabel(days, shape),
                  style: ansiMono(size: 10, color: AnsiColors.herbDeep),
                ),
              ),
              Text(
                'no scale',
                style: ansiMono(size: 10, color: AnsiColors.aging),
              ),
            ],
          ),
          Padding(
            padding: const EdgeInsets.only(top: 5),
            child: Text(
              gapCoversLine(gap, shape),
              style: ansiMono(
                size: 9.5,
                color: AnsiColors.muted,
              ).copyWith(height: 1.45),
            ),
          ),
          _MarginNote.split('${gapHeadline(gap)} — ${gapBody(gap)}'),
          if (gapOffersYieldFix(gap))
            _MarginDoor(
              label: 'Set the yield',
              onTap: () => context.pushOnce('/recipes/${gap.recipeId}/edit'),
            ),
        ],
      ),
    );
  }
}

/// The recipe and its week-level facts, the title being the door back to the
/// recipe the row derives from.
class _Name extends StatelessWidget {
  const _Name({required this.title, required this.facts, this.onTap});

  final String title;
  final String facts;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: onTap,
          child: Text(
            title,
            style: ansiSerif(size: AnsiType.row).copyWith(height: 1.2),
          ),
        ),
        Padding(
          padding: const EdgeInsets.only(top: 7),
          child: Text(
            facts,
            style: ansiMono(size: 9.5, color: AnsiColors.muted),
          ),
        ),
      ],
    );
  }
}

/// One session's sentences at the row's end — the cook day with its scale, the
/// covers line, and the whole-batch line where the batch is fractional.
class _Says extends StatelessWidget {
  const _Says({required this.speech, this.onToggleWholeBatch});

  final SessionSpeech speech;
  final VoidCallback? onToggleWholeBatch;

  @override
  Widget build(BuildContext context) {
    final nudge = speech.nudge;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          '${speech.when} ${speech.scale}',
          style: ansiMono(size: 10, color: AnsiColors.herbDeep),
        ),
        Padding(
          padding: const EdgeInsets.only(top: 5),
          child: Text(
            speech.covers,
            style: ansiMono(
              size: 9.5,
              color: AnsiColors.muted,
            ).copyWith(height: 1.45),
          ),
        ),
        if (nudge != null)
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: onToggleWholeBatch,
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Padding(
                    padding: const EdgeInsets.only(top: 1),
                    child: Icon(
                      speech.wholeBatchShown
                          ? FLucideIcons.rotateCcw
                          : FLucideIcons.circleArrowUp,
                      size: 12,
                      color: AnsiColors.herbDeep,
                    ),
                  ),
                  const SizedBox(width: 5),
                  Expanded(
                    child: Text(
                      nudge,
                      style: ansiMono(
                        size: 9.5,
                        color: AnsiColors.herbDeep,
                      ).copyWith(height: 1.45),
                    ),
                  ),
                ],
              ),
            ),
          ),
      ],
    );
  }
}

/// A note in the row's margin: the words behind a 2 px rule instead of inside a
/// box, because nothing on this sheet is enclosed.
class _MarginNote extends StatelessWidget {
  const _MarginNote._({
    required this.rule,
    required this.ink,
    required this.text,
  });

  factory _MarginNote.split(String text) => _MarginNote._(
    rule: AnsiColors.aging,
    ink: AnsiColors.cautionInk,
    text: text,
  );

  factory _MarginNote.freezer(String text) => _MarginNote._(
    rule: AnsiColors.frozen,
    ink: AnsiColors.chillInk,
    text: text,
  );

  final Color rule;
  final Color ink;
  final String text;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(top: 13),
    // The rule is as tall as the words it stands beside, and nothing above
    // these rows bounds their height — so the height has to be measured from
    // the text rather than stretched into infinity.
    child: IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(width: 2, child: ColoredBox(color: rule)),
          const SizedBox(width: 9),
          Expanded(
            child: Text(
              text,
              style: ansiMono(size: 9.5, color: ink).copyWith(height: 1.5),
            ),
          ),
        ],
      ),
    ),
  );
}

/// The one door a margin note carries — a component gap's fix.
class _MarginDoor extends StatelessWidget {
  const _MarginDoor({required this.label, required this.onTap});

  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(top: 9, left: 11),
    child: GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(label, style: ansiMono(size: 9.5, color: AnsiColors.herbDeep)),
          const SizedBox(width: 3),
          const Icon(
            FLucideIcons.chevronRight,
            size: 12,
            color: AnsiColors.herbDeep,
          ),
        ],
      ),
    ),
  );
}

/// One recipe's seven days: a flex cell per day, so the day a mark sits in is
/// the day the head names above it at any pane width.
class CookTrack extends StatelessWidget {
  const CookTrack({required this.rowKey, required this.days, super.key});

  /// What the cells are keyed by — the recipe, and which of its two
  /// denominations this row is.
  final String rowKey;

  /// The seven days, from [cookTrackDays].
  final List<CookTrackDay> days;

  @override
  Widget build(BuildContext context) => SizedBox(
    height: _trackHeight,
    child: Row(
      children: [
        for (final (day, marks) in days.indexed)
          Expanded(
            child: CookTrackCell(
              key: ValueKey('cook-track-$rowKey-$day'),
              marks: marks,
            ),
          ),
      ],
    ),
  );
}

/// One day of one row's track: the band it keeps through, the tick it is cooked
/// on, and the dot of a meal that eats from it.
class CookTrackCell extends StatelessWidget {
  const CookTrackCell({required this.marks, super.key});

  final CookTrackDay marks;

  @override
  Widget build(BuildContext context) {
    final scale = marks.cookScale;
    return Stack(
      children: [
        if (marks.keeps)
          const Positioned(
            left: 0,
            right: 0,
            top: 0,
            height: _bandHeight,
            child: ColoredBox(color: AnsiColors.herbSoft),
          ),
        if (marks.dot != CookTrackDot.none)
          Positioned.fill(
            child: Align(
              alignment: Alignment.topCenter,
              child: Padding(
                padding: const EdgeInsets.only(top: 9),
                child: Container(
                  width: 6,
                  height: 6,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: marks.dot == CookTrackDot.pastWindow
                        ? AnsiColors.aging
                        : AnsiColors.herb,
                  ),
                ),
              ),
            ),
          ),
        if (scale != null || marks.unscaled)
          Positioned.fill(
            child: Row(
              children: [
                // The tick stands a little into the day rather than on its
                // edge: a cook happens ON that day, and an edge would read as
                // the boundary between two.
                const Spacer(flex: 42),
                Expanded(
                  flex: 58,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                        width: 2,
                        height: _bandHeight,
                        color: marks.unscaled
                            ? AnsiColors.aging
                            : AnsiColors.herb,
                      ),
                      if (scale != null)
                        Padding(
                          padding: const EdgeInsets.only(top: 5),
                          child: Text(
                            scale,
                            maxLines: 1,
                            style: ansiMono(
                              size: 9.5,
                              color: AnsiColors.herbDeep,
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }
}

/// The faint day boundaries, behind every row at once.
///
/// It reads the sheet's own geometry rather than the window's: the track starts
/// where the name column ends and stops where the words begin, so the six lines
/// land on the same boundaries the flex cells divide at.
class _DayVerticalsPainter extends CustomPainter {
  const _DayVerticalsPainter();

  @override
  void paint(Canvas canvas, Size size) {
    const left = _nameColumn + _columnGap;
    final right = size.width - _saysColumn - _columnGap;
    if (right <= left) return;
    final pitch = (right - left) / 7;
    final paint = Paint()..color = AnsiColors.line;
    for (var day = 1; day < 7; day++) {
      final x = left + pitch * day;
      canvas.drawRect(Rect.fromLTWH(x, 0, 1, size.height), paint);
    }
  }

  @override
  bool shouldRepaint(covariant _DayVerticalsPainter old) => false;
}

/// The sheet's hairline: the head from the rows, a row from the next, and the
/// last row from the key under it.
class _Rule extends StatelessWidget {
  const _Rule();

  @override
  Widget build(BuildContext context) =>
      const ColoredBox(color: AnsiColors.line, child: SizedBox(height: 1));
}

/// What the marks mean, once, under the sheet — the convention the track is
/// read with, stated instead of learned.
class _TrackKey extends StatelessWidget {
  const _TrackKey();

  @override
  Widget build(BuildContext context) {
    final label = ansiMono(size: 9, color: AnsiColors.muted);
    return Padding(
      padding: const EdgeInsets.only(left: _nameColumn + _columnGap, top: 14),
      child: Row(
        children: [
          Container(width: 2, height: 11, color: AnsiColors.herb),
          const SizedBox(width: 6),
          Text('cook', style: label),
          const SizedBox(width: 18),
          Container(
            width: 6,
            height: 6,
            decoration: const BoxDecoration(
              shape: BoxShape.circle,
              color: AnsiColors.herb,
            ),
          ),
          const SizedBox(width: 6),
          Text('eaten', style: label),
          const SizedBox(width: 18),
          Container(width: 16, height: 9, color: AnsiColors.herbSoft),
          const SizedBox(width: 6),
          Text('keeps', style: label),
          const SizedBox(width: 18),
          Container(
            width: 6,
            height: 6,
            decoration: const BoxDecoration(
              shape: BoxShape.circle,
              color: AnsiColors.aging,
            ),
          ),
          const SizedBox(width: 6),
          Text('past the window', style: label),
        ],
      ),
    );
  }
}
