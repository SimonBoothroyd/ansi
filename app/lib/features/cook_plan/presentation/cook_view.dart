/// The Cook screen — the DERIVED batch cook plan (spec §4). The counterpart to
/// the Week: it groups the active week's meals by recipe and splits each into
/// cook sessions bounded by shelf life. Read-only; nothing here is planned or
/// persisted — edit the Week, and this re-derives.
///
/// Each recipe is a card; each cook session a paper tile showing the cook day,
/// the honest scale factor, the meals it covers, and a fresh→gone timeline. A
/// split recipe (a later meal outran the fridge window) is flagged; a freezer
/// rescue (a freezable dish reaching a far meal from the freezer) gets its own
/// note. Nothing to sync: the plan re-derives per device from synced inputs.
library;

import 'package:flutter/foundation.dart' show listEquals;
import 'package:flutter/widgets.dart';
import 'package:forui/forui.dart';
import 'package:go_router/go_router.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

import '../../../core/theme/mise_theme.dart';
import '../../../core/theme/mise_tokens.dart';
import '../../../shared/mise_bottom_nav.dart';
import '../../planning/presentation/week_format.dart';
import '../domain/cook_plan.dart';
import 'cook_format.dart';
import 'cook_view_models.dart';

class CookView extends ConsumerWidget {
  const CookView({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final plan = ref.watch(currentCookPlanProvider);

    return FScaffold(
      footer: const MiseBottomNav(current: MiseTab.cook),
      header: FHeader.nested(
        title: Text('Batch cook plan', style: miseHeaderTitle()),
      ),
      child: plan.when(
        loading: () => const Center(child: FCircularProgress()),
        error: (e, _) {
          debugPrint('cook plan failed: $e');
          return Center(
            child: Text(
              'Could not work out the cook plan.',
              textAlign: TextAlign.center,
              style: miseMono(size: 13, color: MiseColors.muted),
            ),
          );
        },
        data: (data) => data.isEmpty
            ? const _EmptyCookPlan()
            : ListView(
                padding: const EdgeInsets.only(top: 6, bottom: 24),
                children: [
                  const _PlanCaption(),
                  for (final recipe in data.recipes)
                    _RecipeCard(recipe: recipe),
                ],
              ),
      ),
    );
  }
}

class _PlanCaption extends StatelessWidget {
  const _PlanCaption();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 4, 20, 4),
      child: Text(
        'grouped by recipe · split by shelf life',
        style: miseMono(
          size: 10.5,
          color: MiseColors.muted,
          letterSpacing: 0.5,
        ),
      ),
    );
  }
}

/// One recipe's batch plan: a title, a week-level summary, its cook sessions,
/// and any split / freezer note. A split card takes the amber accent border.
class _RecipeCard extends StatelessWidget {
  const _RecipeCard({required this.recipe});

  final RecipeCookPlan recipe;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 12, 16, 0),
      padding: const EdgeInsets.fromLTRB(14, 14, 14, 12),
      decoration: BoxDecoration(
        color: MiseColors.surface,
        border: Border.all(
          color: recipe.isSplit ? MiseColors.aging : MiseColors.line,
        ),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(recipe.title, style: miseSerif(size: 19)),
          const SizedBox(height: 3),
          Text(
            recipeSummaryLine(recipe),
            style: miseMono(size: 10.5, color: MiseColors.muted),
          ),
          const SizedBox(height: 10),
          for (final (i, session) in recipe.sessions.indexed) ...[
            if (i > 0) const SizedBox(height: 8),
            _SessionTile(session: session),
            if (session.hasFreezerRescue)
              _Note.freezer(freezerNoteFor(recipe.title, session)),
          ],
          if (recipe.isSplit) _Note.split(splitNoteFor(recipe)),
        ],
      ),
    );
  }
}

/// One cook session as a paper tile: cook day · scale · covers · timeline,
/// plus the whole-batch nudge when the raw factor is fractional (step 7.6).
/// Tapping the nudge toggles the tile's DISPLAY between the honest raw factor
/// and the nudged whole batch — nothing is persisted, and the shopping list
/// keeps scaling by the raw factor either way (invariant 3).
class _SessionTile extends ConsumerWidget {
  const _SessionTile({required this.session});

  final CookSession session;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final nudge = wholeBatchNudgeFor(session);
    final key = cookSessionKey(session);
    final showWhole =
        nudge != null && ref.watch(wholeBatchDisplayProvider(key));

    return Container(
      padding: const EdgeInsets.fromLTRB(11, 10, 11, 11),
      decoration: BoxDecoration(
        color: MiseColors.paper,
        borderRadius: BorderRadius.circular(11),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Expanded(
                child: Text(
                  'Cook ${kWeekdayShort[session.cookDay]}',
                  style: miseSans(size: 13, weight: FontWeight.w600),
                ),
              ),
              Text(
                showWhole
                    ? '×${nudge.factor}'
                    : formatScale(session.scaleFactor),
                style: miseMono(size: 12, color: MiseColors.herbDeep),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            coversLine(session),
            style: miseSans(size: 11, color: MiseColors.muted),
          ),
          if (nudge != null) ...[
            const SizedBox(height: 6),
            GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () =>
                  ref.read(wholeBatchDisplayProvider(key).notifier).toggle(),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Padding(
                    padding: const EdgeInsets.only(top: 1),
                    child: Icon(
                      showWhole
                          ? FLucideIcons.rotateCcw
                          : FLucideIcons.circleArrowUp,
                      size: 13,
                      color: MiseColors.herbDeep,
                    ),
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      showWhole
                          ? 'showing the whole batch — tap for the honest '
                                '${formatScale(session.scaleFactor)}'
                          : wholeBatchNudgeLine(nudge),
                      style: miseMono(size: 10.5, color: MiseColors.herbDeep),
                    ),
                  ),
                ],
              ),
            ),
          ],
          const SizedBox(height: 10),
          CookTimeline(session: session),
        ],
      ),
    );
  }
}

/// The freshness timeline on a fixed Mon→Sun axis: a green fresh window from
/// the cook day, a blue tail when a share is frozen to reach a later meal, or
/// a hatched "gone" tail to Sunday; every eaten day is a marker (the cook day
/// solid), with a weekday ruler beneath.
class CookTimeline extends StatelessWidget {
  const CookTimeline({required this.session, super.key});

  final CookSession session;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 30,
      width: double.infinity,
      child: CustomPaint(painter: _TrackPainter(CookTimelineSpec.of(session))),
    );
  }
}

/// Paints the Mon→Sun freshness track: a neutral week bar overlaid with the
/// green fresh window, a blue frozen tail or hatched gone tail, day markers
/// (the cook day solid, other eaten days ringed), and a weekday-initial ruler.
class _TrackPainter extends CustomPainter {
  _TrackPainter(this.spec);

  final CookTimelineSpec spec;

  // Mon..Sun initials for the ruler (Tue/Thu and Sat/Sun repeat, as usual).
  static const _initials = ['M', 'T', 'W', 'T', 'F', 'S', 'S'];
  static const _padX = 8.0;
  static const _barH = 8.0;
  static const _barCy = 8.0;

  @override
  void paint(Canvas canvas, Size size) {
    final axisW = size.width - 2 * _padX;
    if (axisW <= 0) return;
    double xOf(num day) => _padX + (day / 6) * axisW;
    const top = _barCy - _barH / 2;

    // The whole-week base track.
    final base = RRect.fromRectAndRadius(
      Rect.fromLTRB(xOf(0), top, xOf(6), top + _barH),
      const Radius.circular(4),
    );
    canvas
      ..drawRRect(base, Paint()..color = MiseColors.line)
      ..save()
      ..clipRRect(base);

    void fill(num from, num to, Color color) {
      if (to <= from) return;
      canvas.drawRect(
        Rect.fromLTRB(xOf(from), top, xOf(to), top + _barH),
        Paint()..color = color,
      );
    }

    // Hatched "gone" tail (drawn first; fresh/frozen sit on top).
    if (spec.hasGone) {
      final rect = Rect.fromLTRB(xOf(spec.frozenTo), top, xOf(6), top + _barH);
      canvas.drawRect(rect, Paint()..color = const Color(0xFFF6EDE9));
      final stroke = Paint()
        ..color = const Color(0xFFDCC7BE)
        ..strokeWidth = 1.5;
      for (var lx = rect.left - _barH; lx < rect.right; lx += 5) {
        canvas.drawLine(
          Offset(lx, rect.bottom),
          Offset(lx + _barH, rect.top),
          stroke,
        );
      }
    }
    fill(spec.freshTo, spec.frozenTo, MiseColors.frozen);
    fill(spec.cookDay, spec.freshTo, MiseColors.fresh);
    canvas.restore();

    // Day markers: other eaten days as rings, the cook day as a solid pin.
    final ring = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2
      ..color = MiseColors.herb;
    for (final day in spec.coveredDays) {
      if (day == spec.cookDay) continue;
      final c = Offset(xOf(day), _barCy);
      canvas
        ..drawCircle(c, 4.5, Paint()..color = MiseColors.paper)
        ..drawCircle(c, 4.5, ring);
    }
    final cook = Offset(xOf(spec.cookDay), _barCy);
    canvas
      ..drawCircle(cook, 6, Paint()..color = MiseColors.paper)
      ..drawCircle(cook, 4.5, Paint()..color = MiseColors.herb);

    // The weekday ruler; eaten days are emphasised.
    final eaten = spec.coveredDays.toSet();
    for (var day = 0; day < 7; day++) {
      final on = eaten.contains(day);
      final tp = TextPainter(
        text: TextSpan(
          text: _initials[day],
          style: TextStyle(
            fontFamily: 'IBM Plex Mono',
            fontSize: 9,
            color: on ? MiseColors.herbDeep : MiseColors.muted,
            fontWeight: on ? FontWeight.w600 : FontWeight.w400,
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      tp.paint(canvas, Offset(xOf(day) - tp.width / 2, 20));
    }
  }

  @override
  bool shouldRepaint(covariant _TrackPainter old) =>
      old.spec.cookDay != spec.cookDay ||
      old.spec.freshTo != spec.freshTo ||
      old.spec.frozenTo != spec.frozenTo ||
      old.spec.hasGone != spec.hasGone ||
      !listEquals(old.spec.coveredDays, spec.coveredDays);
}

/// An inline note — split (amber) or freezer (blue) — under the sessions.
class _Note extends StatelessWidget {
  const _Note._({
    required this.icon,
    required this.text,
    required this.background,
    required this.border,
    required this.foreground,
  });

  factory _Note.split(String text) => _Note._(
    icon: FLucideIcons.flag,
    text: text,
    background: const Color(0xFFFBF3E3),
    border: const Color(0xFFF0DCB0),
    foreground: const Color(0xFF7A5A16),
  );

  factory _Note.freezer(String text) => _Note._(
    icon: FLucideIcons.snowflake,
    text: text,
    background: const Color(0xFFEAF1F5),
    border: const Color(0xFFD2E2EC),
    foreground: const Color(0xFF3B6076),
  );

  final IconData icon;
  final String text;
  final Color background;
  final Color border;
  final Color foreground;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(top: 8),
      padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
      decoration: BoxDecoration(
        color: background,
        border: Border.all(color: border),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 1),
            child: Icon(icon, size: 14, color: foreground),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(text, style: miseSans(size: 12, color: foreground)),
          ),
        ],
      ),
    );
  }
}

/// The blank state: no meals planned, so nothing to cook. Points at the Week.
class _EmptyCookPlan extends StatelessWidget {
  const _EmptyCookPlan();

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(24, 48, 24, 32),
      children: [
        const Icon(FLucideIcons.cookingPot, size: 44, color: MiseColors.herb),
        const SizedBox(height: 14),
        Text(
          'Nothing to cook yet',
          textAlign: TextAlign.center,
          style: miseSerif(size: 24),
        ),
        const SizedBox(height: 8),
        Text(
          'Plan some meals on the Week and Mise works out the batches — '
          'what to cook, when, and how much.',
          textAlign: TextAlign.center,
          style: miseMono(size: 12, color: MiseColors.muted),
        ),
        const SizedBox(height: 22),
        FButton(
          onPress: () => context.go('/week'),
          child: const Text('Plan the week'),
        ),
      ],
    );
  }
}
