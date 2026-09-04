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
import 'package:hooks_riverpod/hooks_riverpod.dart';

import '../../../core/theme/ansi_theme.dart';
import '../../../core/theme/ansi_tokens.dart';
import '../../../shared/ansi_callout.dart';
import '../../../shared/ansi_error_state.dart';
import '../../../shared/guarded_navigation.dart';
import '../../planning/presentation/week_format.dart';
import '../../planning/presentation/week_header.dart';
import '../../planning/presentation/week_view_models.dart';
import '../../recipes/domain/component_math.dart';
import '../../recipes/presentation/recipe_view_models.dart';
import '../domain/cook_plan.dart';
import 'cook_format.dart';
import 'cook_view_models.dart';

class CookView extends ConsumerWidget {
  const CookView({super.key});

  /// The tab root's stable anchor: the header no longer names the screen, so
  /// the smoke test waits on this key instead of a title.
  static const rootKey = ValueKey('cook-root');

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final plan = ref.watch(currentCookPlanProvider);
    final viewed = ref.watch(viewedWeekStartProvider);

    return FScaffold(
      key: rootKey,
      // A tab root sits INSIDE the shell's scaffold, which already shrinks
      // the branch area for the keyboard; a second scaffold subtracting the
      // same inset squeezes the content twice (Android showed a list a few
      // lines tall after the sign-in keyboard).
      resizeToAvoidBottomInset: false,
      // D7a/D7c: the plan derives from the ONE viewed week, so the switcher
      // is the whole title — no screen name (the lit tab says where you are),
      // no pill (the switcher's dot and its "This week" item are the same
      // information). No "copy last week": that is a Week write (D7b).
      header: FHeader.nested(
        title: WeekSwitcher(
          showCopyLastWeek: false,
          // The menu speaks in this tab's derivation — "2 cooks", not "9
          // meals" — for the week it has already derived. The other rows stay
          // bare rather than deriving two more plans just to label them.
          detailFor: (weekStart) {
            final data = plan.asData?.value;
            if (data == null || weekStart != viewed) return null;
            return formatCookCount(
              data.recipes.fold(0, (n, r) => n + r.sessions.length),
            );
          },
        ),
      ),
      child: plan.when(
        loading: () => const Center(child: FCircularProgress()),
        error: (e, st) => AnsiErrorState(
          what: 'the cook plan',
          error: e,
          stackTrace: st,
          onRetry: () => ref.invalidate(currentCookPlanProvider),
        ),
        data: (data) => ListView(
          padding: const EdgeInsets.only(top: 6, bottom: 24),
          children: [
            const _PlanCaption(),
            if (data.isEmpty) const _NothingToCookLine(),
            for (final recipe in data.recipes) ...[
              // Two denominations, two cards (D3): a recipe that is both
              // planned and demanded as a component shows its portions
              // and its batches side by side, never summed.
              if (recipe.mealSessions.isNotEmpty) _RecipeCard(recipe: recipe),
              if (recipe.componentSessions.isNotEmpty)
                _ComponentCard(recipe: recipe),
            ],
            // Components the plan could not derive: a named gap, never
            // a ×1 (D3).
            for (final gap in data.gaps) _GapCard(gap: gap),
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
        style: ansiMono(
          size: 10.5,
          color: AnsiColors.muted,
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
    // A recipe that is also somebody's component has its component sessions on
    // their own card, so "split" here counts only the meal ones.
    final meals = recipe.mealSessions;
    final split = meals.length > 1;
    return _Card(
      accent: split,
      title: recipe.title,
      subtitle: recipeSummaryLine(recipe),
      onTitleTap: () => context.pushOnce('/recipes/${recipe.recipeId}'),
      children: [
        for (final (i, session) in meals.indexed) ...[
          if (i > 0) const SizedBox(height: 8),
          _SessionTile(session: session),
          if (session.hasFreezerRescue)
            _Note.freezer(freezerNoteFor(recipe.title, session)),
        ],
        if (split) _Note.split(splitNoteFor(recipe)),
      ],
    );
  }
}

/// A sub-recipe's derived batches (step 8.6 / D3, board frame f): the same
/// card anatomy, denominated in batches and titled by the plans it answers.
///
/// The yield it quotes ("makes 1 cup, you need 0.25") comes off the recipe
/// list, which carries it since 8.6 — a session that resolved was resolved
/// *against* that yield, so naming it is stating the fact the math used, not
/// fetching a new one.
class _ComponentCard extends ConsumerWidget {
  const _ComponentCard({required this.recipe});

  final RecipeCookPlan recipe;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final denomination = ref
        .watch(recipeListProvider)
        .asData
        ?.value
        .where((r) => r.id == recipe.recipeId)
        .firstOrNull
        ?.yields
        .firstOrNull;
    final sessions = recipe.componentSessions;
    final parents = {for (final s in sessions) ...s.demandedBy}.toList();

    return _Card(
      title: componentCardTitle(recipe.title, parents),
      subtitle: componentSummaryLine(recipe),
      onTitleTap: () => context.pushOnce('/recipes/${recipe.recipeId}'),
      children: [
        for (final (i, session) in sessions.indexed) ...[
          if (i > 0) const SizedBox(height: 8),
          _SessionTile(session: session, denomination: denomination),
          if (session.hasFreezerRescue)
            _Note.freezer(freezerNoteFor(recipe.title, session)),
          if (componentLeftoverNote(session, denomination: denomination)
              case final note?)
            _Note.split(note),
        ],
      ],
    );
  }
}

/// A component the plan could NOT derive (D3): the named gap, in the session
/// card's shape so it reads as the session it would have been. It never shows
/// a scale — assuming one batch is exactly the invented number this app
/// refuses — and it carries the one-tap fix where there is one.
class _GapCard extends StatelessWidget {
  const _GapCard({required this.gap});

  final ComponentGap gap;

  @override
  Widget build(BuildContext context) {
    final parents = gap.demandedBy.map((d) => d.title).toSet().toList();
    return _Card(
      accent: true,
      title: componentCardTitle(gap.title, parents),
      subtitle: gapSummaryLine(gap),
      children: [
        Container(
          padding: const EdgeInsets.fromLTRB(11, 10, 11, 11),
          decoration: BoxDecoration(
            color: AnsiColors.paper,
            borderRadius: BorderRadius.circular(11),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      componentWhenLabel(gap.demandedBy.map((d) => d.cookDay)),
                      style: ansiSans(size: 13, weight: FontWeight.w600),
                    ),
                  ),
                  Text(
                    'no scale',
                    style: ansiMono(size: 12, color: AnsiColors.aging),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              Text(
                gapCoversLine(gap),
                style: ansiSans(size: 11, color: AnsiColors.muted),
              ),
              const SizedBox(height: 10),
              _GapWarning(gap: gap),
            ],
          ),
        ),
      ],
    );
  }
}

/// The warn block inside a gap card: what is missing, what setting it buys,
/// and (where the fix lives on the target) one tap to go set it.
class _GapWarning extends StatelessWidget {
  const _GapWarning({required this.gap});

  final ComponentGap gap;

  @override
  Widget build(BuildContext context) => AnsiCallout(
    tone: AnsiTone.caution,
    icon: FLucideIcons.flag,
    title: gapHeadline(gap),
    body: gapBody(gap),
    action: gapOffersYieldFix(gap) ? 'Set the yield' : null,
    onAction: () => context.pushOnce('/recipes/${gap.recipeId}/edit'),
  );
}

/// The card shell every plan card shares: paper tile, title, summary line, and
/// whatever sessions or states sit under it.
class _Card extends StatelessWidget {
  const _Card({
    required this.title,
    required this.subtitle,
    required this.children,
    this.accent = false,
    this.onTitleTap,
  });

  final String title;
  final String subtitle;
  final List<Widget> children;

  /// Opens the recipe the card derives from; null leaves the title inert.
  final VoidCallback? onTitleTap;

  /// Takes the amber border — a split recipe, or an underivable component.
  final bool accent;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 12, 16, 0),
      padding: const EdgeInsets.fromLTRB(14, 14, 14, 12),
      decoration: BoxDecoration(
        color: AnsiColors.surface,
        border: Border.all(color: accent ? AnsiColors.aging : AnsiColors.line),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // The card's title is the way back to the recipe it derives from —
          // the Cook screen is read-only, so this is the only door here.
          GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: onTitleTap,
            child: Text(title, style: ansiSerif(size: 19)),
          ),
          const SizedBox(height: 3),
          Text(subtitle, style: ansiMono(size: 10.5, color: AnsiColors.muted)),
          const SizedBox(height: 10),
          ...children,
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
  const _SessionTile({required this.session, this.denomination});

  final CookSession session;

  /// The target's first stated yield, for a COMPONENT session's arithmetic
  /// ("makes 1 cup, you need 0.25"). Null for a meal session, and for a
  /// component whose recipe states no yield — the clause is dropped, never
  /// guessed.
  final YieldDenomination? denomination;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // A component session is never nudged to a whole batch: batches ARE its
    // denomination (the domain returns null for it).
    final nudge = wholeBatchNudgeFor(session);
    final key = cookSessionKey(session);
    final showWhole =
        nudge != null && ref.watch(wholeBatchDisplayProvider(key));
    final component = session.isComponent;

    return Container(
      padding: const EdgeInsets.fromLTRB(11, 10, 11, 11),
      decoration: BoxDecoration(
        color: AnsiColors.paper,
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
                  component
                      // A component batch has to be ready BY its parents' cook
                      // day, not on one of its own (D3).
                      ? componentWhenLabel(
                          session.demands.map((d) => d.cookDay),
                        )
                      : 'Cook ${kWeekdayShort[session.cookDay]}',
                  style: ansiSans(size: 13, weight: FontWeight.w600),
                ),
              ),
              Text(
                component
                    ? componentScaleLabel(session)
                    : showWhole
                    ? '×${nudge.factor}'
                    : formatScale(session.scaleFactor),
                style: ansiMono(size: 12, color: AnsiColors.herbDeep),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            component
                ? componentCoversLine(session, denomination: denomination)
                : coversLine(session),
            style: ansiSans(size: 11, color: AnsiColors.muted),
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
                      color: AnsiColors.herbDeep,
                    ),
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      showWhole
                          ? 'showing the whole batch — tap for the honest '
                                '${formatScale(session.scaleFactor)}'
                          : wholeBatchNudgeLine(
                              nudge,
                              rawFactor: session.scaleFactor,
                            ),
                      style: ansiMono(size: 10.5, color: AnsiColors.herbDeep),
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
      ..drawRRect(base, Paint()..color = AnsiColors.line)
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
    fill(spec.freshTo, spec.frozenTo, AnsiColors.frozen);
    fill(spec.cookDay, spec.freshTo, AnsiColors.fresh);
    canvas.restore();

    // Day markers: other eaten days as rings, the cook day as a solid pin.
    final ring = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2
      ..color = AnsiColors.herb;
    for (final day in spec.coveredDays) {
      if (day == spec.cookDay) continue;
      final c = Offset(xOf(day), _barCy);
      canvas
        ..drawCircle(c, 4.5, Paint()..color = AnsiColors.paper)
        ..drawCircle(c, 4.5, ring);
    }
    final cook = Offset(xOf(spec.cookDay), _barCy);
    canvas
      ..drawCircle(cook, 6, Paint()..color = AnsiColors.paper)
      ..drawCircle(cook, 4.5, Paint()..color = AnsiColors.herb);

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
            color: on ? AnsiColors.herbDeep : AnsiColors.muted,
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
  const _Note._({required this.tone, required this.icon, required this.text});

  factory _Note.split(String text) =>
      _Note._(tone: AnsiTone.caution, icon: FLucideIcons.flag, text: text);

  factory _Note.freezer(String text) =>
      _Note._(tone: AnsiTone.chill, icon: FLucideIcons.snowflake, text: text);

  final AnsiTone tone;
  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(top: 8),
    child: AnsiCallout(tone: tone, icon: icon, body: text),
  );
}

/// Nothing planned, said INSIDE the screen (week redesign D5b/D5c).
///
/// This replaces a full-bleed page with a cooking-pot icon and one button — a
/// dead end with a single exit, on a screen whose header (and week switcher)
/// it hid. The house rule now is that a screen never swaps itself out for a
/// data condition: the chrome stays, and the empty region carries the
/// affordance that would fill it.
class _NothingToCookLine extends ConsumerWidget {
  const _NothingToCookLine();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final suffix = formatDerivedWeekSuffix(
      ref.watch(viewedWeekStartProvider),
      ref.watch(currentWeekStartProvider),
    );
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 14, 20, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'nothing planned for ${suffix ?? 'this week'} yet — the batches '
            'are worked out from the meals you put on the week',
            style: ansiMono(size: 11.5, color: AnsiColors.muted),
          ),
          const SizedBox(height: 10),
          GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () => context.goOnce('/week'),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(FLucideIcons.plus, size: 12, color: AnsiColors.herb),
                const SizedBox(width: 5),
                Text(
                  'plan a meal',
                  style: ansiMono(size: 11.5, color: AnsiColors.herbDeep),
                ),
                const SizedBox(width: 3),
                const Icon(
                  FLucideIcons.chevronRight,
                  size: 12,
                  color: AnsiColors.herbDeep,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
