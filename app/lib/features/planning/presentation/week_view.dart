/// The Week — the meal-planning screen, and the INPUT to the derived
/// cook-plan / shopping pipeline (steps 5–6).
///
/// **One screen, one state.** There is no presentation/edit mode: no tap here
/// is destructive, and a mode that blanks the numbers you are editing against
/// costs more than it explains.
///
/// **A row's controls are the facts the row prints.** The title opens the
/// recipe it names. The portions chip and eater avatars are ONE target — they
/// open `meal_editor_sheet.dart`, which holds the row's other printed facts:
/// its slot (the gutter label it sits under), who is eating and the portions.
/// The `−` removes the meal, with an undo toast rather than a confirm: a
/// destructive control on every row of a resting screen is defensible only
/// because the act is trivially reversible, so the screen makes it so. The
/// day is deliberately not a field — a row does not print a day as a value,
/// its *position* is its day — so a meal changes day by removing it and
/// adding it again through the picker's "already this week" quick picks.
///
/// **One add door, in every state.** `＋ add a meal` is the last row of every
/// day card, sitting with the meals and above the day's total, because it adds
/// a *meal*, not a number. On an empty day it is the same line saying `nothing
/// planned`.
///
/// **The numbers are honest and never hidden.** Each day card foots with its
/// own macro line and that line's denominator; the list foots with the week
/// band. The lens above the cards rescopes both — and DIMS the meals a person
/// is not eating rather than deleting them, because a day somebody else cooks
/// for themselves is not an empty day.
///
/// **There is no blank-week page.** A week with nothing in it is this same
/// screen with nothing in it: header, switcher, lens row, seven day cards and
/// the week band all render, exactly as they do for a full week.
///
/// **At [AnsiLayout.expanded] the same week is one day beside the week that
/// scrolls** — a 560 px day pane and a vertical agenda (`week_wide.dart`). It
/// is one view model, one set of words and one set of doors, drawn in two
/// shapes: this file's list below the band, the two panes above it.
///
/// The week itself is a position, not a singleton — see `week_header.dart` and
/// `week_view_models.dart`.
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

/// The add flow: pick from the ONE door, then confirm slot/eaters/portions.
///
/// The slot it starts on follows the day: the next default slot the day has
/// not filled yet ([defaultMealSlot]), read off the viewed week before the
/// first sheet opens. A recipe goes straight to the confirm sheet — its
/// amount is its portions. A bare ingredient (step 8.14) stops at the shipped
/// quantity sheet first, opened on the row's default unit — `piece`, weighed
/// by the row's own piece weight (ADR-0015), so "1 bar" is a bar. A meal eaten
/// out goes straight through too, since its words are all of it; the confirm
/// sheet then asks the questions every kind shares, and one only it is asked.
Future<void> _addMealFlow(
  BuildContext context,
  WidgetRef ref, {
  required DateTime weekStart,
  required int dayOfWeek,
}) async {
  // The picker's search brings the keyboard, which shrinks the week's list
  // under it: the day card whose door opened this flow can be unmounted by
  // the time a recipe is tapped. The confirm sheet opens from a context that
  // outlives the card (`hostContextOf`), so the pick is never dropped — and
  // the slot is settled here, before anything is awaited, for the same reason.
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
      // The sheet opens on the row's own default unit — `piece`, weighed by
      // the row's piece weight, on a counted food (ADR-0015).
      final result = await showQuantityUnitSheet(
        // The host outlives the row — see [hostContextOf].
        // ignore: use_build_context_synchronously
        host.context,
        ingredient: ingredient,
        requireQuantity: true,
        confirmLabel: 'Next',
      );
      // Backing out of the amount backs out of the whole add: an entry with
      // no amount is a real state, but not one anybody asked for here.
      if (result is! QuantitySaved) return;
      target = SnackMeal(
        ingredient: ingredient,
        quantity: result.quantity,
        unit: switch (result.choice) {
          // A measure counts THINGS, so its row stores the honest count
          // fallback beside the measure id — the same pair every other
          // measure-quantified row in the app stores.
          MeasureOption() => pieces,
          UnitOption(:final unit) => unit,
        },
        measure: switch (result.choice) {
          MeasureOption(:final measure) => measure,
          UnitOption() => null,
        },
      );
    case PickedMealOut(:final label):
      // Nothing to settle first: the words ARE the meal, and the only
      // question left is the one the confirm sheet's optional fold asks.
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

  /// `?week=YYYY-MM-DD` — the week this tab was opened at, seated on arrival so
  /// a refresh or a pasted link opens the week you were looking at
  /// ([WeekInTheLocation]).
  final String? weekKey;

  /// `?day=YYYY-MM-DD` — which day the wide day pane stands on. **The URL is
  /// where that choice lives**, not a notifier beside it: the `›` restates the
  /// location and the pane reads it back, so one refresh lands on the same day
  /// and back still leaves the week in one press (`restateOnce`).
  ///
  /// A date rather than an index, so it says what it means in a shared link and
  /// so a date left over from another week simply does not match — the pane
  /// falls back to its default (today, or the week's first day) instead of
  /// pointing at a day this week does not have.
  final String? dayKey;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final weekStart = ref.watch(viewedWeekStartProvider);
    final week = ref.watch(viewedWeekProvider);
    // Decorative emptiness, weighed (D6): an empty roster draws no avatars and
    // no lens chips. The week's own meals — the thing this screen is for — are
    // unaffected, and the roster arrives with the first sync.
    final roster = ref.watch(membersProvider).asData?.value ?? const <Member>[];
    // The cook markers are a READ of the derivation the Cook tab draws, for
    // this same week (D6). Null while it loads — a row simply has no second
    // line until it arrives.
    final cookPlan = ref.watch(currentCookPlanProvider).asData?.value;

    // "cooks today" is only true of the week containing today.
    // Read off [Today], not `DateTime.now()`: the week start is the same all
    // week,
    // so only the day provider re-fires this at a Tuesday midnight.
    final isThisWeek = weekStart == ref.watch(currentWeekStartProvider);
    final shape = ref.watch(weekShapeProvider);
    final todayDayOfWeek = isThisWeek
        ? shape.offsetOf(ref.watch(todayProvider))
        : null;

    final lastWeek = ref.watch(lastWeekProvider).asData?.value;

    // null = Everyone; a member id = that person's lens (D8: it dims, it does
    // not remove).
    //
    // The lens stays a notifier and stays OUT of the URL: it is a question
    // about how the numbers are being read, not a position, and a link that
    // silently scoped a household's week to one eater would be a link nobody
    // meant to send.
    final lens = useState<String?>(null);
    // Which day the wide day pane draws, read off `?day=` — null means "the
    // default" (see [WeekWide]). A date from another week does not match and so
    // does not count.
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
      // The day is only a question the WIDE day pane asks. A phone draws all
      // seven days and stands on none of them, so it names none — the one thing
      // that differs by width in the whole location.
      also: AnsiLayout.of(context) == AnsiLayout.expanded
          ? {'day': isoDateOf(shape.dateFor(weekStart, day))}
          : const {},
      child: FScaffold(
        // A tab root sits INSIDE the shell's scaffold, which already shrinks
        // the branch area for the keyboard; a second scaffold subtracting the
        // same inset squeezes the content twice (Android showed a list a few
        // lines tall after the sign-in keyboard).
        resizeToAvoidBottomInset: false,
        // "Copy last week" has ONE permanent home — the switcher menu — plus
        // the empty-week chip below.
        header: FHeader.nested(
          title: WeekSwitcher(
            // The menu speaks in this tab's derivation — "9 meals" — for the
            // week on screen; the other rows stay bare.
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
          // `watchWeek` emitting null stops meaning "show a different screen"
          // and starts meaning "seven empty days" (D5).
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
                  // What the week's receipts came to, beside what it plans to
                  // cook. Never reconciled (ADR-0017).
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

/// One day of the week as a card: its name and date, its meals grouped by
/// slot, and — in presentation the day's macro line, in edit the dashed
/// add-meal door (D1's density switch).
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
    // D8: the lens DIMS, it does not remove. Every meal on the day still
    // renders, so a day the other person cooks for themselves is not
    // mistaken for an empty one.
    final visible = entries;

    // entriesForDay is already slot-ordered, so same-slot entries are
    // contiguous — group consecutive runs under one slot label.
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
        // The herb left rule pins today (D2). It is PAINTED over the card's
        // edge rather than being a thicker left border, because a rounded box
        // may not have per-side colours.
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
              // The date is load-bearing once weeks vary (D6).
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
        // E5: one add door, always, as the card's last ROW — with the meals
        // it extends, above the day's total. On an empty day it is the same
        // line saying `nothing planned`, so the first meal lands on the day
        // you pointed at (D5b) and there is no second widget to keep in step.
        AddMealLine(
          empty: visible.isEmpty,
          onTap: () => _addMealFlow(
            context,
            ref,
            weekStart: weekStart,
            dayOfWeek: dayOfWeek,
          ),
        ),
        // The day's own honest total, with its denominator (D4). Absent on an
        // empty day: `no meals` is a state, never `0 kcal`.
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
    // The board's week frame: the slot label sits in a left gutter ON THE
    // SAME LINE as the dish name (vertically centred with the row), never
    // floating above it — a multi-dish slot centres the label beside the
    // stack, exactly like the frame's split rows.
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
                    // D8: a meal this person is not eating is dimmed, not gone.
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

/// A single dish within a slot — and, since v3, three targets on one row.
///
/// Two lines, not one column of cells (D6, owner-ruled): the title with its
/// eaters (and a portions chip when the override differs) on the first, the
/// cook marker on the second — absent entirely for a single-meal cook, which
/// collapses the row back to one line.
///
/// **A row's controls are the facts the row prints** (E7):
///
/// * the **title** opens the recipe it names;
/// * the **portions chip + avatars** are ONE target — they open the meal
///   editor, whose fields are the slot, the eaters and the portions. One
///   target, not two, because the chip is conditional: a chip-only tap would
///   be missing from most rows and could never *set* a first override;
/// * the **`−`** removes the meal, with an undo toast (E3).
///
/// This is not the old `›`, which was drawn but announced "the row navigates"
/// and so competed with the row itself. The test a target has to pass is not
/// "is the row's tap unambiguous" but **"is the target drawn"** — which is
/// also why there is no long-press anywhere on this screen.
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
    // E6: the marker is never suppressed — there is no mode left to suppress
    // it in, and the cook consequence is most worth reading while planning.
    //
    // Only a RECIPE has a cook marker, and that is a ruling, not an omission
    // (step 8.14 / A-D5): nothing about a protein bar or a canteen lunch is
    // cooked, so a row that drew a shelf-life chip or a batch hint would be
    // describing a recipe. What the meal IS takes the marker's place instead —
    // a snack's stated amount, a meal out's tag and figures.
    final marker = plan == null || kind != PlanEntryKind.recipe
        ? null
        : cookMarkerFor(
            plan,
            recipeId: entry.recipeId!,
            dayOfWeek: entry.dayOfWeek,
            mealSlot: entry.mealSlot,
          );
    // The week this row belongs to, carried into the dish's page: the recipe
    // page's week door is only offered to an arrival that names a week which
    // actually plans the recipe.
    final weekKey = isoDateOf(ref.watch(viewedWeekStartProvider));
    final route = mealTitleRoute(entry, weekKey: weekKey);
    // Every planned day of a varied recipe says so, because the variant is
    // per (week, recipe) — two rows describing one pot cannot disagree.
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
                  // The title opens the thing it NAMES, with the week it is
                  // planned in — [mealTitleRoute] holds which page that is, for
                  // this row and for the wide day pane both. A deleted target
                  // has no page to open, so the title is inert; the row's other
                  // two targets still work, because the meal is still a real
                  // row on the week.
                  onTap: route == null ? null : () => context.pushOnce(route),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 10),
                    child: Text(
                      mealTitleText(entry),
                      // Three weights, because there are three kinds (A-D5).
                      // The dish's emphasis is what says "this is a dish with
                      // a page behind it", so a bare ingredient reads at the
                      // row's ordinary weight — and a meal eaten out, which
                      // has no page at all, reads plain and italic: the
                      // household's own words rather than a title.
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
              // A Row, not a Wrap: the marker line is itself a Row with a
              // Flexible label, and a Wrap hands its children unbounded width.
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
          // The snack's amount sits exactly where a cook marker would (A-D5)
          // — the row's second line says what this meal IS, since nothing
          // about it is cooked.
          if (snack)
            Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Text(
                snackAmount(entry),
                overflow: TextOverflow.ellipsis,
                style: ansiMono(size: 10.5, color: AnsiColors.muted),
              ),
            ),
          // And the meal eaten out says the same thing in its own terms: the
          // `out` tag, and the figures it was given or the absence of them.
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

/// The empty week's one obvious door, at the top of the list.
///
/// Seven identical quiet lines have no focal point, so the primary lives here;
/// each day's own `nothing planned` line is still its add door, which is what
/// makes the first meal land on the day you MEANT (the old CTA always added to
/// the week's first day, `dayOfWeek: 0`).
///
/// `copy last week` sits beside it only while the week has zero entries. Its
/// permanent home is the switcher menu (D2).
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
