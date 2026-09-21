/// The Cook screen: the derived batch cook plan for the viewed week. Read-only;
/// edit the Week and this re-derives.
///
/// On a phone each recipe is a card of session tiles; at [AnsiLayout.expanded]
/// the same plan is one schedule sheet ([CookSheet]).
library;

import 'package:flutter/foundation.dart' show listEquals;
import 'package:flutter/widgets.dart';
import 'package:forui/forui.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

import '../../../core/theme/ansi_theme.dart';
import '../../../core/theme/ansi_tokens.dart';
import '../../../core/week_shape.dart';
import '../../../shared/ansi_callout.dart';
import '../../../shared/ansi_error_state.dart';
import '../../../shared/ansi_layout.dart';
import '../../../shared/ansi_scroll.dart';
import '../../../shared/guarded_navigation.dart';
import '../../account/data/household_providers.dart';
import '../../planning/presentation/week_format.dart';
import '../../planning/presentation/week_header.dart';
import '../../planning/presentation/week_in_the_location.dart';
import '../../planning/presentation/week_view_models.dart';
import '../../recipes/domain/component_math.dart';
import '../../recipes/presentation/recipe_view_models.dart';
import '../domain/cook_plan.dart';
import 'cook_format.dart';
import 'cook_sheet.dart';
import 'cook_view_models.dart';

class CookView extends ConsumerWidget {
  const CookView({this.weekKey, super.key});

  /// The tab root's stable anchor: the header does not name the screen, so the
  /// smoke test waits on this key.
  static const rootKey = ValueKey('cook-root');

  /// `?week=YYYY-MM-DD`: the week this tab was opened at. It only seats the
  /// shared position ([viewedWeekStartProvider]) on arrival; see
  /// [WeekInTheLocation].
  final String? weekKey;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final plan = ref.watch(currentCookPlanProvider);
    final viewed = ref.watch(viewedWeekStartProvider);

    return WeekInTheLocation(
      path: '/cook',
      weekKey: weekKey,
      child: FScaffold(
        key: rootKey,
        // A tab root sits inside the shell's scaffold, which already shrinks
        // for the keyboard; a second inset would squeeze the content twice.
        resizeToAvoidBottomInset: false,
        // The week switcher is the whole title: no screen name, no pill.
        header: FHeader.nested(
          title: WeekSwitcher(
            showCopyLastWeek: false,
            // Only the already-derived week is labelled; other rows stay bare
            // rather than deriving more plans.
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
          data: (data) => _plan(context, data),
        ),
      ),
    );
  }

  /// The plan: a column of cards on a phone, one schedule sheet capped at
  /// [kCookSheetWidth] from [AnsiLayout.expanded] up.
  Widget _plan(BuildContext context, CookPlan data) {
    if (AnsiLayout.of(context) == AnsiLayout.expanded) {
      return Align(
        alignment: Alignment.topCenter,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: kCookSheetWidth),
          child: ListView(
            padding: ansiScrollPadding(
              context,
              const EdgeInsets.only(top: 6, bottom: 24),
            ),
            children: [
              const _PlanCaption(),
              if (data.isEmpty)
                const _NothingToCookLine()
              else
                CookSheet(plan: data),
            ],
          ),
        ),
      );
    }
    return ListView(
      padding: const EdgeInsets.only(top: 6, bottom: 24),
      children: [
        const _PlanCaption(),
        if (data.isEmpty) const _NothingToCookLine(),
        for (final recipe in data.recipes) ...[
          // A recipe both planned and demanded as a component shows two cards,
          // never summed.
          if (recipe.mealSessions.isNotEmpty) _RecipeCard(recipe: recipe),
          if (recipe.componentSessions.isNotEmpty)
            _ComponentCard(recipe: recipe),
        ],
        // Components the plan could not derive: a named gap, never a ×1.
        for (final gap in data.gaps) _GapCard(gap: gap),
      ],
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
class _RecipeCard extends ConsumerWidget {
  const _RecipeCard({required this.recipe});

  final RecipeCookPlan recipe;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // A recipe that is also somebody's component has its component sessions on
    // their own card, so "split" here counts only the meal ones.
    final meals = recipe.mealSessions;
    final split = meals.length > 1;
    final edited =
        (ref
                    .watch(viewedWeekOverridesProvider)
                    .asData
                    ?.value[recipe.recipeId] ??
                const [])
            .isNotEmpty;
    // The title link carries the viewed week (`?week=`) so the recipe page can
    // offer "Edit for this week".
    final weekKey = isoDateOf(ref.watch(viewedWeekStartProvider));
    final shape = ref.watch(weekShapeProvider);
    return _Card(
      accent: split,
      title: recipe.title,
      subtitle: recipeSummaryLine(recipe, editedThisWeek: edited),
      onTitleTap: () =>
          context.pushOnce('/recipes/${recipe.recipeId}?week=$weekKey'),
      children: [
        for (final (i, session) in meals.indexed) ...[
          if (i > 0) const SizedBox(height: 8),
          _SessionTile(session: session),
          if (session.hasFreezerRescue)
            _Note.freezer(freezerNoteFor(recipe.title, session, shape)),
        ],
        if (split) _Note.split(splitNoteFor(recipe)),
      ],
    );
  }
}

/// A sub-recipe's derived batches: the session card's anatomy, denominated in
/// batches and titled by the plans it answers.
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
    final shape = ref.watch(weekShapeProvider);
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
            _Note.freezer(freezerNoteFor(recipe.title, session, shape)),
          if (componentLeftoverNote(session, shape, denomination: denomination)
              case final note?)
            _Note.split(note),
        ],
      ],
    );
  }
}

/// A component the plan could not derive, in the session card's shape. It never
/// shows a scale and carries the one-tap fix where there is one.
class _GapCard extends ConsumerWidget {
  const _GapCard({required this.gap});

  final ComponentGap gap;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final shape = ref.watch(weekShapeProvider);
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
                      componentWhenLabel(
                        gap.demandedBy.map((d) => d.cookDay),
                        shape,
                      ),
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
                gapCoversLine(gap, shape),
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
            child: Text(title, style: ansiSerif(size: AnsiType.row)),
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

/// One cook session as a paper tile: cook day, scale, covers, timeline, plus
/// the whole-batch nudge when the factor is fractional. Tapping the nudge
/// toggles display only; nothing is persisted.
class _SessionTile extends ConsumerWidget {
  const _SessionTile({required this.session, this.denomination});

  final CookSession session;

  /// The target's first stated yield, for a component session's arithmetic.
  /// Null for a meal session or a recipe that states no yield.
  final YieldDenomination? denomination;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final key = cookSessionKey(session);
    // One set of words for both forms: the tile and the wide sheet's row read
    // the same speech, so neither decides on its own what a session says.
    final speech = SessionSpeech.of(
      session,
      ref.watch(weekShapeProvider),
      showWholeBatch: ref.watch(wholeBatchDisplayProvider(key)),
      denomination: denomination,
    );
    final nudge = speech.nudge;

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
                  speech.when,
                  style: ansiSans(size: 13, weight: FontWeight.w600),
                ),
              ),
              Text(
                speech.scale,
                style: ansiMono(size: 12, color: AnsiColors.herbDeep),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            speech.covers,
            style: ansiSans(size: 11, color: AnsiColors.muted),
          ),
          // The word a demanding line was written in, showing its work —
          // `3 blob → 45 g → 0.15 of a batch`. One per demand that said one.
          for (final word in speech.words) ...[
            const SizedBox(height: 4),
            Text(word, style: ansiMono(size: 10, color: AnsiColors.herbDeep)),
          ],
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
                      speech.wholeBatchShown
                          ? FLucideIcons.rotateCcw
                          : FLucideIcons.circleArrowUp,
                      size: 13,
                      color: AnsiColors.herbDeep,
                    ),
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      nudge,
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

/// The freshness timeline on the week's seven-day axis; geometry from
/// [CookTimelineSpec].
class CookTimeline extends ConsumerWidget {
  const CookTimeline({required this.session, super.key});

  final CookSession session;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return SizedBox(
      height: 30,
      width: double.infinity,
      child: CustomPaint(
        painter: _TrackPainter(
          CookTimelineSpec.of(session),
          // The ruler counts the week's own days, so its initials start where
          // the week does.
          initials: [
            for (final label in ref.watch(weekShapeProvider).shortLabels)
              label[0],
          ],
        ),
      ),
    );
  }
}

/// Paints the freshness track: the week bar, the fresh window, a frozen or gone
/// tail, day markers and a weekday-initial ruler.
class _TrackPainter extends CustomPainter {
  _TrackPainter(this.spec, {required this.initials});

  final CookTimelineSpec spec;

  /// One initial per day of the week, in the week's own order (Tue/Thu and
  /// Sat/Sun repeat, as usual).
  final List<String> initials;
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
          text: initials[day],
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
      !listEquals(old.spec.coveredDays, spec.coveredDays) ||
      !listEquals(old.initials, initials);
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

/// The empty state, shown inside the screen so the header and week switcher
/// stay.
class _NothingToCookLine extends ConsumerWidget {
  const _NothingToCookLine();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final suffix = formatDerivedWeekSuffix(
      ref.watch(viewedWeekStartProvider),
      ref.watch(currentWeekStartProvider),
      ref.watch(weekShapeProvider),
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
