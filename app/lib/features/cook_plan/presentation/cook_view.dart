/// The Cook screen: the derived batch cook plan for the viewed week. Read-only;
/// edit the Week and this re-derives.
///
/// On a phone each recipe is a card of session tiles; at [AnsiLayout.expanded]
/// the same plan is one schedule sheet ([CookSheet]).
library;

import 'package:flutter/widgets.dart';
import 'package:forui/forui.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

import '../../../core/theme/ansi_theme.dart';
import '../../../core/theme/ansi_tokens.dart';
import '../../../core/week_shape.dart';
import '../../../shared/ansi_error_state.dart';
import '../../../shared/ansi_layout.dart';
import '../../../shared/ansi_scroll.dart';
import '../../../shared/ansi_tap.dart';
import '../../../shared/guarded_navigation.dart';
import '../../../shared/week_strip.dart';
import '../../account/data/household_providers.dart';
import '../../ask/domain/ask_screen.dart';
import '../../ask/presentation/ask_door.dart';
import '../../planning/presentation/week_header.dart';
import '../../planning/presentation/week_in_the_location.dart';
import '../../planning/presentation/week_view_models.dart';
import '../../recipes/domain/component_math.dart';
import '../../recipes/presentation/recipe_view_models.dart';
import '../domain/cook_plan.dart';
import '../domain/leftovers.dart';
import 'batch_leftover_line.dart';
import 'cook_format.dart';
import 'cook_sheet.dart';
import 'cook_view_models.dart';
import 'leftovers_view_models.dart';
import 'whole_batch_switch.dart';

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
          suffixes: const [AskDoor(tab: AskWeekTab.cook)],
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
              if (data.isEmpty && data.eatenFromEarlier.isEmpty)
                const _NothingToCookLine()
              else if (!data.isEmpty)
                CookSheet(plan: data),
              _EarlierMealLines(plan: data),
            ],
          ),
        ),
      );
    }
    return ListView(
      padding: const EdgeInsets.only(top: 6, bottom: 24),
      children: [
        // A meal eaten from an earlier week's cooking is a line of its own,
        // and the week is not empty for it.
        if (data.isEmpty && data.eatenFromEarlier.isEmpty)
          const _NothingToCookLine(),
        for (final recipe in data.recipes) ...[
          // A recipe both planned and demanded as a component shows two cards,
          // never summed.
          if (recipe.mealSessions.isNotEmpty) _RecipeCard(recipe: recipe),
          if (recipe.componentSessions.isNotEmpty)
            _ComponentCard(recipe: recipe),
        ],
        // Components the plan could not derive: a named gap, never a ×1.
        for (final gap in data.gaps) _GapCard(gap: gap),
        _EarlierMealLines(plan: data),
      ],
    );
  }
}

/// This week's meals eaten from a cooking an earlier week bought, one line
/// each: `Beef Ragù · Thu · from the freezer`. Nothing to cook or buy, and no
/// reminder: the line says where it comes from.
class _EarlierMealLines extends ConsumerWidget {
  const _EarlierMealLines({required this.plan});

  final CookPlan plan;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (plan.eatenFromEarlier.isEmpty) return const SizedBox.shrink();
    final shape = ref.watch(weekShapeProvider);
    final meals = earlierMealsOf(
      plan,
      weekStart: ref.watch(viewedWeekStartProvider),
      today: ref.watch(todayProvider),
      judged: ref.watch(leftoverMealsProvider),
    );
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 14, 20, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (final meal in meals)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Text(
                earlierMealLine(meal, shape),
                style: ansiMono(
                  size: 11.5,
                  color: switch (meal.source) {
                    EarlierSource.freezer => AnsiColors.chillInk,
                    EarlierSource.fridge => AnsiColors.herbDeep,
                    EarlierSource.cookIt => AnsiColors.ink,
                  },
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// One recipe's batch plan: a title, a week-level summary and its cook
/// sessions. A split shows as a second session, its strip saying why.
class _RecipeCard extends ConsumerWidget {
  const _RecipeCard({required this.recipe});

  final RecipeCookPlan recipe;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // A recipe that is also somebody's component has its component sessions on
    // their own card, so "split" here counts only the meal ones.
    final meals = recipe.mealSessions;
    final edited =
        (ref
                    .watch(viewedWeekOverridesProvider)
                    .asData
                    ?.value[recipe.recipeId] ??
                const [])
            .isNotEmpty;
    // The title link carries the viewed week (`?week=`) so the recipe page can
    // offer "Edit for this week", and the batch's amount (`?servings=`) so it
    // opens scaled to what is cooked.
    final weekStart = ref.watch(viewedWeekStartProvider);
    final weekKey = isoDateOf(weekStart);
    // The cook day the ticks say, so a skipped first meal moves it; a batch
    // not cooked yet keeps only until the dish's next cook.
    final today = ref.watch(todayProvider);
    final timelines = timelinesOf([
      for (final s in meals) sessionByTicks(s, weekStart, today),
    ]);
    return _Card(
      title: recipe.title,
      subtitle: recipeSummaryLine(recipe, editedThisWeek: edited),
      onTitleTap: () => context.pushOnce(
        recipePageRoute(
          recipe.recipeId,
          weekKey: weekKey,
          servings: cookTitleServings(meals),
        ),
      ),
      children: [
        for (final (i, session) in meals.indexed) ...[
          if (i > 0) const SizedBox(height: 8),
          _SessionTile(session: session, timeline: timelines[i]),
        ],
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
    final sessions = recipe.componentSessions;
    final parents = {for (final s in sessions) ...s.demandedBy}.toList();

    return _Card(
      title: componentCardTitle(recipe.title, parents),
      subtitle: componentSummaryLine(recipe),
      onTitleTap: () => context.pushOnce(
        recipePageRoute(recipe.recipeId, servings: cookTitleServings(sessions)),
      ),
      children: [
        for (final (i, session) in sessions.indexed) ...[
          if (i > 0) const SizedBox(height: 8),
          _SessionTile(
            session: session,
            denomination: denomination,
            timeline: CookTimelineSpec.of(session),
          ),
        ],
      ],
    );
  }
}

/// A component the plan could not derive, in the session card's shape. It never
/// shows a scale, and carries a button to each place its fix lives.
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

/// The warn block inside a gap card: the one-line problem, then a button per
/// place its fix lives ([gapFixes]), each opening the editor on the fix.
class _GapWarning extends StatelessWidget {
  const _GapWarning({required this.gap});

  final ComponentGap gap;

  @override
  Widget build(BuildContext context) {
    const tone = AnsiTone.caution;
    return Container(
      padding: const EdgeInsets.fromLTRB(10, 9, 10, 10),
      decoration: BoxDecoration(
        color: tone.fill,
        border: Border.all(color: tone.line),
        borderRadius: BorderRadius.circular(AnsiRadii.box),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.only(top: 1),
                child: Icon(FLucideIcons.flag, size: 14, color: tone.ink),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  gapHeadline(gap),
                  style: ansiSans(
                    size: 12.5,
                    color: tone.ink,
                    weight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
          for (final fix in gapFixes(gap)) ...[
            const SizedBox(height: 10),
            AnsiTap(
              onTap: () => context.pushOnce(fix.location),
              color: tone.ink,
              child: Container(
                padding: const EdgeInsets.symmetric(vertical: 9),
                decoration: BoxDecoration(
                  border: Border.all(color: tone.line),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Flexible(
                      child: Text(
                        fix.label,
                        textAlign: TextAlign.center,
                        style: ansiMono(size: 12, color: tone.ink),
                      ),
                    ),
                    const SizedBox(width: 3),
                    Icon(FLucideIcons.chevronRight, size: 13, color: tone.ink),
                  ],
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
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

  /// The week-level facts under the title; empty draws none.
  final String subtitle;
  final List<Widget> children;

  /// Opens the recipe the card derives from; null leaves the title inert.
  final VoidCallback? onTitleTap;

  /// Takes the amber border: an underivable component.
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
          if (subtitle.isNotEmpty) ...[
            const SizedBox(height: 3),
            Text(
              subtitle,
              style: ansiMono(size: 10.5, color: AnsiColors.muted),
            ),
          ],
          const SizedBox(height: 10),
          ...children,
        ],
      ),
    );
  }
}

/// One cook session as a paper tile: cook day, scale, covers and the compact
/// week strip. A fractional factor not cooked yet trades the scale for the
/// exact-or-whole switch, which the cooking keeps: the whole batch is
/// bought, and its spare is left over.
class _SessionTile extends ConsumerWidget {
  const _SessionTile({
    required this.session,
    required this.timeline,
    this.denomination,
  });

  final CookSession session;

  /// The strip's geometry ([timelinesOf]).
  final CookTimelineSpec timeline;

  /// The target's first stated yield, for a component session's arithmetic.
  /// Null for a meal session or a recipe that states no yield.
  final YieldDenomination? denomination;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final shape = ref.watch(weekShapeProvider);
    // One set of words for both forms: the tile and the wide sheet's row read
    // the same speech, so neither decides on its own what a session says.
    final speech = SessionSpeech.of(
      session,
      shape,
      denomination: denomination,
      weekStart: ref.watch(viewedWeekStartProvider),
      today: ref.watch(todayProvider),
    );
    // What was made is fixed once it is cooked: the switch is for a batch
    // still to cook.
    final choice = speech.cooked ? null : speech.wholeBatch;

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
              if (speech.cooked) ...[
                const Icon(
                  FLucideIcons.check,
                  size: 13,
                  color: AnsiColors.herb,
                ),
                const SizedBox(width: 4),
              ],
              Expanded(
                child: Text(
                  speech.when,
                  style: ansiSans(size: 13, weight: FontWeight.w600),
                ),
              ),
              // The switch states the scale when there is a choice of two.
              if (choice == null && speech.scaleShown)
                Text(
                  speech.scale,
                  style: ansiMono(size: 12, color: AnsiColors.herbDeep),
                ),
            ],
          ),
          // A cooked batch says what it left where its covers would be.
          if (speech.cooked)
            BatchLeftoverLine(session: session)
          else ...[
            const SizedBox(height: 6),
            Text(
              speech.covers,
              style: ansiSans(size: 11, color: AnsiColors.muted),
            ),
          ],
          // The word a demanding line was written in, showing its work —
          // `3 blob → 45 g → 0.15 of a batch`. One per demand that said one.
          for (final word in speech.words) ...[
            const SizedBox(height: 4),
            Text(word, style: ansiMono(size: 10, color: AnsiColors.herbDeep)),
          ],
          if (choice != null) ...[
            const SizedBox(height: 8),
            WholeBatchSwitch(
              exact: choice.exact,
              whole: choice.whole,
              wholeShown: speech.wholeBatchShown,
              onChanged: (whole) =>
                  chooseWholeBatch(context, ref, session, whole: whole),
            ),
          ],
          const SizedBox(height: 10),
          WeekStrip(
            days: timeline.stripDays(),
            shape: shape,
            size: WeekStripSize.compact,
          ),
          if (!session.isComponent && !speech.cooked)
            BatchLeftoverLine(session: session),
        ],
      ),
    );
  }
}

/// The empty state, shown inside the screen so the header and week switcher
/// stay.
class _NothingToCookLine extends StatelessWidget {
  const _NothingToCookLine();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 14, 20, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'nothing planned yet',
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
