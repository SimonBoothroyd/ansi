/// The Cook screen: the derived batch cook plan for the viewed week. Read-only;
/// edit the Week and this re-derives.
///
/// On a phone each recipe is a card of session tiles; at [AnsiLayout.expanded]
/// the same plan is one schedule sheet ([CookSheet]).
library;

import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:forui/forui.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

import '../../../core/theme/ansi_theme.dart';
import '../../../core/theme/ansi_tokens.dart';
import '../../../core/units/portions.dart';
import '../../../core/week_shape.dart';
import '../../../shared/ansi_chip.dart';
import '../../../shared/ansi_error_state.dart';
import '../../../shared/ansi_layout.dart';
import '../../../shared/ansi_scroll.dart';
import '../../../shared/ansi_tap.dart';
import '../../../shared/guarded_navigation.dart';
import '../../../shared/week_strip.dart';
import '../../../shared/write.dart';
import '../../account/data/household_providers.dart';
import '../../ask/domain/ask_screen.dart';
import '../../ask/presentation/ask_door.dart';
import '../../planning/presentation/week_header.dart';
import '../../planning/presentation/week_in_the_location.dart';
import '../../planning/presentation/week_view_models.dart';
import '../../recipes/domain/component_math.dart';
import '../../recipes/presentation/recipe_view_models.dart';
import '../data/cook_plan_providers.dart';
import '../domain/cook_plan.dart';
import 'cook_format.dart';
import 'cook_sheet.dart';
import 'cook_view_models.dart';
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
    // offer "Edit for this week".
    final weekKey = isoDateOf(ref.watch(viewedWeekStartProvider));
    return _Card(
      title: recipe.title,
      subtitle: recipeSummaryLine(recipe, editedThisWeek: edited),
      onTitleTap: () =>
          context.pushOnce('/recipes/${recipe.recipeId}?week=$weekKey'),
      children: [
        for (final (i, session) in meals.indexed) ...[
          if (i > 0) const SizedBox(height: 8),
          _SessionTile(session: session),
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
      onTitleTap: () => context.pushOnce('/recipes/${recipe.recipeId}'),
      children: [
        for (final (i, session) in sessions.indexed) ...[
          if (i > 0) const SizedBox(height: 8),
          _SessionTile(session: session, denomination: denomination),
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
/// week strip. A fractional factor trades the scale for the exact-or-whole
/// switch, which is display only; nothing is persisted.
class _SessionTile extends ConsumerWidget {
  const _SessionTile({required this.session, this.denomination});

  final CookSession session;

  /// The target's first stated yield, for a component session's arithmetic.
  /// Null for a meal session or a recipe that states no yield.
  final YieldDenomination? denomination;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final key = cookSessionKey(session);
    final shape = ref.watch(weekShapeProvider);
    // One set of words for both forms: the tile and the wide sheet's row read
    // the same speech, so neither decides on its own what a session says.
    final speech = SessionSpeech.of(
      session,
      shape,
      showWholeBatch: ref.watch(wholeBatchDisplayProvider(key)),
      denomination: denomination,
    );
    final choice = speech.wholeBatch;

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
              // The switch states the scale when there is a choice of two.
              if (choice == null)
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
          if (choice != null) ...[
            const SizedBox(height: 8),
            WholeBatchSwitch(
              exact: choice.exact,
              whole: choice.whole,
              wholeShown: speech.wholeBatchShown,
              onChanged: (whole) => ref
                  .read(wholeBatchDisplayProvider(key).notifier)
                  .show(whole: whole),
            ),
          ],
          const SizedBox(height: 10),
          WeekStrip(
            days: CookTimelineSpec.of(session).stripDays(),
            shape: shape,
            size: WeekStripSize.compact,
          ),
          if (!session.isComponent) LeftoverQuestion(session: session),
        ],
      ),
    );
  }
}

/// Once a batch's days are over and fewer portions were ticked than planned:
/// what became of the rest — kept, binned, or eaten after all. Either member
/// may answer; it is about the pot, not a person.
class LeftoverQuestion extends ConsumerWidget {
  const LeftoverQuestion({required this.session, super.key});

  final CookSession session;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final key = session.leftoverKey;
    final left = session.uneatenPortions;
    if (key == null ||
        left <= 0 ||
        !session.isOverAfter(ref.watch(viewedWeekDaysPassedProvider))) {
      return const SizedBox.shrink();
    }
    final answer = ref.watch(viewedWeekLeftoversProvider).asData?.value[key];
    final repo = ref.read(cookPlanRepositoryProvider);

    void answerAll(LeftoverAnswer? a, String what) =>
        unawaited(ref.write(context, what, () => repo.setLeftover(key, a)));

    if (answer != null) {
      final said = leftoverAnswerLine(answer);
      return Padding(
        padding: const EdgeInsets.only(top: 10),
        child: AnsiTap(
          onTap: () => answerAll(null, 'change that'),
          semanticsLabel: 'Change what happened to the leftovers',
          child: Row(
            children: [
              Expanded(
                child: Text(
                  said,
                  style: ansiMono(
                    size: 11,
                    color: answer.binned > 0
                        ? AnsiColors.gone
                        : AnsiColors.herbDeep,
                  ),
                ),
              ),
              Text('›', style: ansiSans(size: 13, color: AnsiColors.muted)),
            ],
          ),
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.only(top: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            '${formatPortions(left)} left',
            style: ansiSans(size: 12.5, weight: FontWeight.w600),
          ),
          const SizedBox(height: 6),
          Row(
            children: [
              for (final (i, (label, answer)) in [
                ('Kept', (kept: left, binned: 0.0, eaten: 0.0)),
                ('Binned', (kept: 0.0, binned: left, eaten: 0.0)),
                ('Eaten', (kept: 0.0, binned: 0.0, eaten: left)),
              ].indexed) ...[
                if (i > 0) const SizedBox(width: 6),
                AnsiChip(
                  label: label,
                  selected: false,
                  expand: true,
                  onTap: () => answerAll(answer, 'say what happened'),
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }
}

/// `1 portion kept`, `2 portions binned`, `1 kept · 1 binned`.
String leftoverAnswerLine(LeftoverAnswer a) {
  final parts = [
    if (a.kept > 0) (a.kept, 'kept'),
    if (a.binned > 0) (a.binned, 'binned'),
    if (a.eaten > 0) (a.eaten, 'eaten after all'),
  ];
  if (parts.isEmpty) return 'nothing left';
  if (parts.length == 1) {
    return '${formatPortions(parts.single.$1)} ${parts.single.$2}';
  }
  return [for (final (n, w) in parts) '${formatFraction(n)} $w'].join(' · ');
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
