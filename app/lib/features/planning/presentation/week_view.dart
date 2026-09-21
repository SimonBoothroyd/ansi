/// The Week: the meal-planning screen, and the input to the derived cook plan
/// and shopping list.
///
/// One screen with no edit mode. A row's title opens the recipe; its portions
/// chip and avatars open the meal editor; `−` removes the meal with an undo
/// toast. Each day card ends with the one add door and the day's macro line. At
/// [AnsiLayout.expanded] the same view model draws as two panes
/// (`week_wide.dart`).
library;

import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:forui/forui.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

import '../../../core/theme/ansi_theme.dart';
import '../../../core/theme/ansi_tokens.dart';
import '../../../core/units/units.dart';
import '../../../core/week_shape.dart';
import '../../../shared/ansi_error_state.dart';
import '../../../shared/ansi_layout.dart';
import '../../../shared/guarded_navigation.dart';
import '../../../shared/write.dart';
import '../../account/data/household_providers.dart';
import '../../cook_plan/domain/cook_plan.dart';
import '../../cook_plan/presentation/cook_view_models.dart';
import '../../ingredients/domain/allowed_units.dart';
import '../../ingredients/presentation/quantity_unit_sheet.dart';
import '../../receipts/data/receipt_providers.dart';
import '../domain/planning.dart';
import 'confirm_meal_sheet.dart';
import 'copy_last_week.dart';
import 'recipe_picker_sheet.dart';
import 'week_format.dart';
import 'week_header.dart';
import 'week_in_the_location.dart';
import 'week_macro_widgets.dart';
import 'week_view_models.dart';
import 'week_wide.dart';
import 'week_widgets.dart';

/// The add flow: pick a recipe, ingredient or meal out, then confirm slot,
/// eaters and portions. The slot starts on the day's first unfilled default
/// ([defaultMealSlot]). A bare ingredient stops at the quantity sheet first.
Future<void> _addMealFlow(
  BuildContext context,
  WidgetRef ref, {
  required DateTime weekStart,
  required int dayOfWeek,
}) async {
  // The picker's keyboard can unmount the day card that opened this flow, so
  // the confirm sheet opens from a context that outlives it and the slot is
  // settled before any await.
  final host = hostContextOf(context);
  final week = ref.read(viewedWeekProvider).asData?.value;
  final slot = defaultMealSlot(week?.entriesForDay(dayOfWeek) ?? const []);
  final picked = await showRecipePickerSheet(
    context,
    dayOfWeek: dayOfWeek,
    slot: slot,
  );
  if (picked == null) return;

  final MealTarget target;
  switch (picked) {
    case PickedRecipe(:final recipe):
      target = RecipeMeal(recipe);
    case PickedIngredientMeal(:final ingredient):
      // Opens on the row's first chip: its own word for one, else `piece`
      // (ADR-0015).
      final result = await showQuantityUnitSheet(
        // The host outlives the row — see [hostContextOf].
        // ignore: use_build_context_synchronously
        host.context,
        ingredient: ingredient,
        requireQuantity: true,
        confirmLabel: 'Next',
      );
      // Backing out of the amount backs out of the whole add.
      if (result is! QuantitySaved) return;
      target = SnackMeal(
        ingredient: ingredient,
        quantity: result.quantity,
        unit: switch (result.choice) {
          // A measure-quantified row stores the count fallback beside the
          // measure id.
          MeasureOption() => pieces,
          RecipeMeasureOption(:final measure) => notAWordForAnIngredient(
            measure,
          ),
          UnitOption(:final unit) => unit,
        },
        measure: switch (result.choice) {
          MeasureOption(:final measure) => measure,
          RecipeMeasureOption(:final measure) => notAWordForAnIngredient(
            measure,
          ),
          UnitOption() => null,
        },
      );
    case PickedMealOut(:final label):
      // A meal out needs nothing settled first.
      target = OutMeal(label);
  }

  await showConfirmMealSheet(
    // The host outlives the row — see [hostContextOf].
    // ignore: use_build_context_synchronously
    host.context,
    weekStart: weekStart,
    dayOfWeek: dayOfWeek,
    slot: slot,
    target: target,
  );
}

class WeekView extends HookConsumerWidget {
  const WeekView({this.weekKey, this.dayKey, super.key});

  /// `?week=YYYY-MM-DD` — the week to open at ([WeekInTheLocation]).
  final String? weekKey;

  /// `?day=YYYY-MM-DD` — the day the wide day pane stands on. The URL holds the
  /// choice, so a refresh keeps it; a date from another week does not match and
  /// the pane falls back to its default.
  final String? dayKey;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final weekStart = ref.watch(viewedWeekStartProvider);
    final week = ref.watch(viewedWeekProvider);
    // An empty roster draws no avatars and no lens chips; it arrives with the
    // first sync.
    final roster = ref.watch(membersProvider).asData?.value ?? const <Member>[];
    // The Cook tab's derivation for this week; null while it loads.
    final cookPlan = ref.watch(currentCookPlanProvider).asData?.value;

    // "cooks today" is only true of the week containing today. Read off
    // [Today], not `DateTime.now()`, so it re-fires at midnight.
    final isThisWeek = weekStart == ref.watch(currentWeekStartProvider);
    final shape = ref.watch(weekShapeProvider);
    final todayDayOfWeek = isThisWeek
        ? shape.offsetOf(ref.watch(todayProvider))
        : null;

    final lastWeek = ref.watch(lastWeekProvider).asData?.value;

    // null = Everyone; a member id = that person's lens. The lens stays out of
    // the URL so a shared link is never silently scoped to one eater.
    final lens = useState<String?>(null);
    // The wide day pane's day from `?day=`; null means the default (see
    // [WeekWide]).
    final chosen = dayKey == null ? null : DateTime.tryParse(dayKey!);
    final selectedDay = chosen != null && shape.weekStartOf(chosen) == weekStart
        ? shape.offsetOf(chosen)
        : null;
    final day = selectedDay ?? todayDayOfWeek ?? 0;
    final scope =
        roster
            .where((m) => m.id == lens.value)
            .map((m) => m.displayName)
            .firstOrNull ??
        'Everyone';

    return WeekInTheLocation(
      path: '/week',
      weekKey: weekKey,
      // Only the wide day pane stands on a day, so only it names one.
      also: AnsiLayout.of(context) == AnsiLayout.expanded
          ? {'day': isoDateOf(shape.dateFor(weekStart, day))}
          : const {},
      child: FScaffold(
        // A tab root sits inside the shell's scaffold, which already shrinks
        // for the keyboard; a second inset would squeeze the content twice.
        resizeToAvoidBottomInset: false,
        // "Copy last week" lives in the switcher menu, plus the empty-week chip
        // below.
        header: FHeader.nested(
          title: WeekSwitcher(
            // The menu details only the week on screen ("9 meals").
            detailFor: (monday) => week.asData == null || monday != weekStart
                ? null
                : formatMealCount(week.asData!.value?.entries.length ?? 0),
          ),
        ),
        child: week.when(
          loading: () => const Center(child: FCircularProgress()),
          error: (e, st) => AnsiErrorState(
            what: 'the week',
            error: e,
            stackTrace: st,
            onRetry: () => ref.invalidate(viewedWeekProvider),
          ),
          // A null plan draws seven empty days.
          data: (plan) {
            final empty = plan == null || plan.entries.isEmpty;
            if (AnsiLayout.of(context) == AnsiLayout.expanded) {
              return WeekWide(
                weekStart: weekStart,
                plan: plan,
                roster: roster,
                lens: lens,
                scope: scope,
                cookPlan: cookPlan,
                todayDayOfWeek: todayDayOfWeek,
                selectedDay: day,
                onSelectDay: (d) => context.restateOnce(
                  weekLocation(
                    '/week',
                    weekStart,
                    also: {'day': isoDateOf(shape.dateFor(weekStart, d))},
                  ),
                ),
                onAddMeal: (dayOfWeek) => unawaited(
                  _addMealFlow(
                    context,
                    ref,
                    weekStart: weekStart,
                    dayOfWeek: dayOfWeek,
                  ),
                ),
                onCopyLastWeek: empty && lastWeek != null
                    ? () => unawaited(
                        copyLastWeekInto(context, ref, weekStart: weekStart),
                      )
                    : null,
              );
            }
            return ListView(
              padding: const EdgeInsets.only(top: 8, bottom: 24),
              children: [
                if (empty)
                  _FirstMealBar(
                    weekStart: weekStart,
                    hasLastWeek: lastWeek != null,
                    onCopyLastWeek: () => unawaited(
                      copyLastWeekInto(context, ref, weekStart: weekStart),
                    ),
                  ),
                CopyLastWeekNotice(weekStart: weekStart),
                WeekLensRow(lens: lens, roster: roster),
                for (var d = 0; d < 7; d++)
                  _DayCard(
                    weekStart: weekStart,
                    dayOfWeek: d,
                    entries: plan?.entriesForDay(d) ?? const [],
                    roster: roster,
                    lens: lens.value,
                    scope: scope,
                    cookPlan: cookPlan,
                    todayDayOfWeek: todayDayOfWeek,
                  ),
                WeekMacroBand(
                  macros: ref.watch(weekMacrosProvider(lens.value)),
                  cost: ref.watch(weekCostProvider(lens.value)),
                  // Never reconciled with the planned cost (ADR-0017).
                  spent: ref.watch(receiptsForWeekProvider(weekStart)),
                  shape: shape,
                  scope: scope,
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

/// One day as a card: its name and date, its meals grouped by slot, the add
/// door and the day's macro line.
class _DayCard extends ConsumerWidget {
  const _DayCard({
    required this.weekStart,
    required this.dayOfWeek,
    required this.entries,
    required this.roster,
    required this.lens,
    required this.scope,
    required this.cookPlan,
    required this.todayDayOfWeek,
  });

  final DateTime weekStart;
  final int dayOfWeek;
  final List<PlanEntry> entries;
  final List<Member> roster;
  final String? lens;
  final String scope;
  final CookPlan? cookPlan;
  final int? todayDayOfWeek;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // The lens dims, it does not remove: every meal on the day still renders.
    final visible = entries;

    // entriesForDay is slot-ordered, so group consecutive runs under one label.
    final groups = <List<PlanEntry>>[];
    for (final e in visible) {
      if (groups.isNotEmpty &&
          groups.last.first.mealSlot.toLowerCase() ==
              e.mealSlot.toLowerCase()) {
        groups.last.add(e);
      } else {
        groups.add([e]);
      }
    }

    final isToday = todayDayOfWeek == dayOfWeek;
    return Stack(
      children: [
        Container(
          margin: const EdgeInsets.fromLTRB(16, 12, 16, 0),
          decoration: BoxDecoration(
            color: AnsiColors.paper,
            border: Border.all(color: AnsiColors.line),
            borderRadius: BorderRadius.circular(16),
          ),
          child: _body(context, ref, groups, visible, isToday),
        ),
        // Today's left rule is painted over the card's edge: a rounded box may
        // not have per-side border colours.
        if (isToday)
          Positioned(
            left: 16,
            top: 24,
            bottom: 12,
            child: Container(
              width: 3,
              decoration: const BoxDecoration(
                color: AnsiColors.herb,
                borderRadius: BorderRadius.horizontal(left: Radius.circular(2)),
              ),
            ),
          ),
      ],
    );
  }

  Widget _body(
    BuildContext context,
    WidgetRef ref,
    List<List<PlanEntry>> groups,
    List<PlanEntry> visible,
    bool isToday,
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 10),
          child: Row(
            children: [
              Text(
                ref.watch(weekShapeProvider).labelFull(dayOfWeek),
                style: ansiSerif(size: AnsiType.row),
              ),
              const SizedBox(width: 8),
              // Weeks vary, so the date is needed.
              Text(
                formatDayDate(weekStart, dayOfWeek),
                style: ansiMono(size: 11, color: AnsiColors.muted),
              ),
              const Spacer(),
              if (isToday)
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 7,
                    vertical: 2,
                  ),
                  decoration: BoxDecoration(
                    color: AnsiColors.herbSoft,
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Text(
                    'TODAY',
                    style: ansiMono(
                      size: 9,
                      color: AnsiColors.herbDeep,
                      letterSpacing: 1,
                    ),
                  ),
                ),
            ],
          ),
        ),
        for (final group in groups)
          _SlotGroup(
            group: group,
            roster: roster,
            lens: lens,
            cookPlan: cookPlan,
            todayDayOfWeek: todayDayOfWeek,
          ),
        // The one add door, always the card's last row; on an empty day it says
        // `nothing planned`.
        AddMealLine(
          empty: visible.isEmpty,
          onTap: () => _addMealFlow(
            context,
            ref,
            weekStart: weekStart,
            dayOfWeek: dayOfWeek,
          ),
        ),
        // The day's total with its denominator; absent on an empty day.
        if (visible.isNotEmpty)
          DayMacroLine(
            macros: ref.watch(dayMacrosProvider(dayOfWeek, lens)),
            scope: scope,
          ),
      ],
    );
  }
}

/// One meal slot within a day: the slot label once on the left, its dish(es)
/// stacked on the right.
class _SlotGroup extends StatelessWidget {
  const _SlotGroup({
    required this.group,
    required this.roster,
    required this.lens,
    required this.cookPlan,
    required this.todayDayOfWeek,
  });

  final List<PlanEntry> group;
  final List<Member> roster;
  final String? lens;
  final CookPlan? cookPlan;
  final int? todayDayOfWeek;

  @override
  Widget build(BuildContext context) {
    // The slot label sits in a left gutter, vertically centred beside its
    // dishes.
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 4, 12, 4),
      decoration: const BoxDecoration(
        border: Border(top: BorderSide(color: AnsiColors.line)),
      ),
      child: Row(
        children: [
          SizedBox(
            width: 62,
            child: Text(
              group.first.mealSlot.toUpperCase(),
              style: ansiMono(
                size: 10,
                color: AnsiColors.muted,
                letterSpacing: 0.5,
              ),
            ),
          ),
          Expanded(
            child: Column(
              children: [
                for (final e in group)
                  _DishRow(
                    entry: e,
                    roster: roster,
                    // A meal this person is not eating is dimmed, not gone.
                    dimmed: lens != null && !e.eaterIds.contains(lens),
                    cookPlan: cookPlan,
                    todayDayOfWeek: todayDayOfWeek,
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// A single dish within a slot, on up to two lines: the title with its eaters
/// and portions chip, then the cook marker (absent for a single-meal cook).
///
/// Three targets: the title opens the recipe; the chip and avatars together
/// open the meal editor; `−` removes the meal with an undo toast.
class _DishRow extends ConsumerWidget {
  const _DishRow({
    required this.entry,
    required this.roster,
    required this.dimmed,
    required this.cookPlan,
    required this.todayDayOfWeek,
  });

  final PlanEntry entry;
  final List<Member> roster;
  final bool dimmed;
  final CookPlan? cookPlan;
  final int? todayDayOfWeek;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final kind = entry.kind;
    final snack = kind == PlanEntryKind.ingredient;
    final out = kind == PlanEntryKind.out;
    final plan = cookPlan;
    // Only a recipe has a cook marker; a snack shows its amount and a meal out
    // its tag and figures instead.
    final marker = plan == null || kind != PlanEntryKind.recipe
        ? null
        : cookMarkerFor(
            plan,
            recipeId: entry.recipeId!,
            dayOfWeek: entry.dayOfWeek,
            mealSlot: entry.mealSlot,
          );
    // The recipe page offers its week door only to an arrival naming a week
    // that plans the recipe.
    final weekKey = isoDateOf(ref.watch(viewedWeekStartProvider));
    final route = mealTitleRoute(entry, weekKey: weekKey);
    // The variant is per (week, recipe), so every planned day of it says so.
    final edited =
        (ref.watch(viewedWeekOverridesProvider).asData?.value[entry.recipeId] ??
                const [])
            .isNotEmpty;
    return Opacity(
      opacity: dimmed ? 0.38 : 1,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  // [mealTitleRoute] decides the page. A deleted target has
                  // none, so the title is inert.
                  onTap: route == null ? null : () => context.pushOnce(route),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 10),
                    child: Text(
                      mealTitleText(entry),
                      // A recipe reads emphasised, a bare ingredient at
                      // ordinary weight, a meal out plain italic.
                      style: entry.title == null
                          ? ansiSans(size: 15, color: AnsiColors.muted)
                          : ansiSans(
                              size: snack || out ? 14 : 15,
                              color: snack || out
                                  ? AnsiColors.ink
                                  : AnsiColors.herbDeep,
                              weight: snack || out
                                  ? FontWeight.w400
                                  : FontWeight.w600,
                            ).copyWith(
                              fontStyle: out
                                  ? FontStyle.italic
                                  : FontStyle.normal,
                            ),
                    ),
                  ),
                ),
              ),
              EatersTarget(
                entry: entry,
                roster: roster,
                portions: portionsChipFor(entry, roster),
              ),
              RemoveTarget(entry: entry, roster: roster),
            ],
          ),
          if (marker != null || edited)
            Padding(
              padding: const EdgeInsets.only(bottom: 6),
              // A Row, not a Wrap: the marker line has a Flexible label, and a
              // Wrap hands its children unbounded width.
              child: Row(
                children: [
                  if (marker != null)
                    Flexible(
                      child: CookMarkerLine(
                        marker: marker,
                        todayDayOfWeek: todayDayOfWeek,
                      ),
                    ),
                  if (marker != null && edited) const SizedBox(width: 6),
                  if (edited) const EditedForThisWeekMark(),
                ],
              ),
            ),
          // The snack's amount sits where a cook marker would.
          if (snack)
            Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Text(
                snackAmount(entry),
                overflow: TextOverflow.ellipsis,
                style: ansiMono(size: 10.5, color: AnsiColors.muted),
              ),
            ),
          // A meal out shows its `out` tag and its figures, or their absence.
          if (out)
            Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: OutMealLine(entry: entry),
            ),
        ],
      ),
    );
  }
}

/// The empty week's primary add door, at the top of the list. `copy last week`
/// sits beside it only while the week has no entries.
class _FirstMealBar extends ConsumerWidget {
  const _FirstMealBar({
    required this.weekStart,
    required this.hasLastWeek,
    required this.onCopyLastWeek,
  });

  final DateTime weekStart;
  final bool hasLastWeek;
  final VoidCallback onCopyLastWeek;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          FButton(
            prefix: const Icon(FLucideIcons.plus),
            onPress: () =>
                _addMealFlow(context, ref, weekStart: weekStart, dayOfWeek: 0),
            child: const Text('Add the first meal'),
          ),
          if (hasLastWeek)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Align(child: CopyLastWeekChip(onTap: onCopyLastWeek)),
            ),
        ],
      ),
    );
  }
}
