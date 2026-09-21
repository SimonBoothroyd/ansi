/// Display formatting for the Cook screen — pure Dart (no widgets), so the
/// batch-plan copy and the timeline geometry are unit-testable.
library;

import 'dart:math' as math;

import '../../../core/units/number_format.dart';
import '../../../core/units/portions.dart';
import '../../../core/week_shape.dart';
import '../../../shared/format.dart';
import '../../planning/presentation/week_variant_format.dart';
import '../../recipes/domain/component_math.dart';
import '../../recipes/presentation/component_format.dart';
import '../domain/cook_plan.dart';

/// The batch multiplier, e.g. `×1`, `×1.5`, `×0.75`.
String formatScale(double factor) => '×${formatAmount(factor)}';

/// The week menu row's trailing label on the Cook tab: `2 cooks` / `1 cook` /
/// `nothing to cook`.
String formatCookCount(int sessions) => switch (sessions) {
  0 => 'nothing to cook',
  1 => '1 cook',
  _ => '$sessions cooks',
};

/// The whole-batch nudge line for a fractional session: "cook ×1 instead —
/// covers 4 portions · 1 portion left over · shopping still buys ×0.75". Advice
/// beside the raw factor; the shopping list keeps scaling by [rawFactor].
String wholeBatchNudgeLine(
  WholeBatchNudge nudge, {
  required double rawFactor,
}) =>
    'cook ×${nudge.factor} instead — covers '
    '${formatPortions(nudge.batchPortions)} · '
    '${formatPortions(nudge.leftoverPortions)} left over · '
    'shopping still buys ${formatScale(rawFactor)}';

/// The recipe card's summary line: total portions across the week plus shelf
/// life ("4 portions across the week · keeps 4 d"). A recipe the week varies
/// appends one clause and nothing else.
String recipeSummaryLine(RecipeCookPlan recipe, {bool editedThisWeek = false}) {
  final parts = <String>[
    '${formatPortions(recipe.totalPortions)} across the week',
  ];
  final keeps = recipe.keepsForDays;
  if (keeps != null) parts.add('keeps $keeps d');
  if (recipe.freezable) parts.add('freezable');
  if (editedThisWeek) parts.add(kEditedForThisWeek);
  return parts.join(' · ');
}

/// A session's "covers …" line, ending with the portion count. Collapses the
/// slot when every covered meal shares one ("Tue + Sat dinner").
String coversLine(CookSession session, WeekShape shape) {
  // A component session covers no meals, so the line names the plans it serves.
  if (session.isComponent) return 'covers ${session.demandedBy.join(' + ')}';

  final covers = session.covers;
  final slots = {for (final m in covers) m.mealSlot.toLowerCase()};
  final portions = formatPortions(session.totalPortions);

  if (slots.length == 1) {
    // Distinct days, one shared slot.
    final days = (<int>{
      for (final m in covers) m.dayOfWeek,
    }.toList()..sort()).map(shape.labelShort).join(' + ');
    return 'covers $days ${slots.first} · $portions';
  }
  final meals = covers
      .map(
        (m) => '${shape.labelShort(m.dayOfWeek)} ${m.mealSlot.toLowerCase()}',
      )
      .join(' + ');
  return 'covers $meals · $portions';
}

// --- Component sessions and gaps (step 8.6 / D3, board frame f) --------------

/// A component card's title: *"Romesco Aioli · for Sausage Sliders"* — the
/// sub-recipe, and the planned recipes whose lines called for it.
String componentCardTitle(String recipeTitle, List<String> parents) =>
    parents.isEmpty ? recipeTitle : '$recipeTitle · for ${parents.join(' + ')}';

/// A component card's summary line: what it is, then the shelf-life facts the
/// derived session inherits (they are the sub-recipe's OWN, not the parent's).
String componentSummaryLine(RecipeCookPlan recipe) => [
  'derived from a component line',
  if (recipe.keepsForDays != null) 'keeps ${recipe.keepsForDays} d',
  if (recipe.freezable) 'freezable',
].join(' · ');

/// The batch scale a component session reads: "×0.25 batch".
String componentScaleLabel(CookSession session) =>
    '${formatScale(session.batchesToCook ?? 0)} batch';

/// The day a component batch has to be ready BY — its demanding parents' cook
/// days, which is why the tile reads "Cook by Sat" and not "Cook Sat".
String componentWhenLabel(Iterable<int> days, WeekShape shape) {
  final sorted = days.toSet().toList()..sort();
  if (sorted.isEmpty) return 'Cook by';
  return 'Cook by ${sorted.map(shape.labelShort).join(' + ')}';
}

/// A component session's "covers …" line: "covers Sausage Sliders · cook Sat —
/// makes 1 cup, you need 0.25". [denomination] is the target's first stated
/// yield; null drops the closing clause.
String componentCoversLine(
  CookSession session,
  WeekShape shape, {
  YieldDenomination? denomination,
}) {
  final days = (session.demands.map((d) => d.cookDay).toSet().toList()..sort())
      .map(shape.labelShort)
      .join(' + ');
  final head = 'covers ${session.demandedBy.join(' + ')} · cook $days';
  if (denomination == null) return head;
  final batches = session.batchesToCook ?? 0;
  return '$head — ${yieldText(denomination)}, '
      'you need ${formatQuantity(batches)}';
}

/// The note under a component session that needs less than a whole batch;
/// leftovers are not tracked. Null when the demand is a whole number of batches
/// or the target states no yield.
String? componentLeftoverNote(
  CookSession session,
  WeekShape shape, {
  YieldDenomination? denomination,
}) {
  final batches = session.batchesToCook;
  if (batches == null || denomination == null) return null;
  if (batches == batches.roundToDouble()) return null;
  return 'A batch makes '
      '${formatQuantityIn(denomination.qty, denomination.unit)} '
      '${denomination.unit.label} and '
      '${shape.labelFull(session.cookDay)} needs '
      '${formatQuantity(batches)} — the rest is yours. Nothing here tracks '
      'the leftover.';
}

/// The gap card's summary line — the component-card one, with the reason in
/// the shelf-life slot: this card has no scale to inherit facts for.
String gapSummaryLine(ComponentGap gap) =>
    'derived from a component line · ${gapReasonShort(gap.reason)}';

/// The reason in three or four words, for the card's summary line.
String gapReasonShort(UnresolvedComponentAmount reason) => switch (reason) {
  ComponentAmountMissing() => 'no amount on the line',
  ComponentYieldMissing() => 'yield not set',
  ComponentMeasureMissing() => 'its measure is gone',
  ComponentFamilyMismatch() => 'yield in another family',
  ComponentCycle() => 'used inside itself',
};

/// The gap card's "covers …" line: "covers Sausage Sliders · cook Sat — the
/// line asks for 0.25 cup".
///
/// The closing clause quotes the demanding line unscaled and unconverted. It is
/// dropped for a numberless line ([ComponentAmountMissing]) and for a line
/// whose word has gone ([ComponentMeasureMissing]). With several demanding
/// parents each clause names its own.
String gapCoversLine(ComponentGap gap, WeekShape shape) {
  final days = (gap.demandedBy.map((d) => d.cookDay).toSet().toList()..sort())
      .map(shape.labelShort)
      .join(' + ');
  final parents = gap.demandedBy.map((d) => d.title).toSet().join(' + ');
  final head = 'covers $parents · cook $days';

  String said(ComponentDemandSource d) =>
      componentAmountText(d.quantity, d.unit, measureLabel: d.measureLabel);

  final asks = [
    for (final d in gap.demandedBy)
      if (d.quantity != null && !(d.saysAMeasure && d.measureLabel == null)) d,
  ];
  if (asks.isEmpty) return head;
  if (gap.demandedBy.length == 1) {
    return '$head — the line asks for ${said(asks.single)}';
  }
  final clauses = asks.map((d) => '${d.title} asks for ${said(d)}').join(' · ');
  return '$head — $clauses';
}

/// The warn state's headline — *"Romesco Aioli doesn't say how much it
/// makes"*. It names the thing to fix, never the failure.
String gapHeadline(ComponentGap gap) => switch (gap.reason) {
  ComponentYieldMissing() => '${gap.title} doesn’t say how much it makes',
  ComponentFamilyMismatch() =>
    '${gap.title}’s yield can’t answer this line’s unit',
  ComponentAmountMissing() =>
    'The line doesn’t say how much ${gap.title} it needs',
  ComponentMeasureMissing() =>
    'The line says a measure ${gap.title} hasn’t got any more',
  ComponentCycle() => '${gap.title} is used inside itself',
};

/// The warn state's body: what setting the missing fact would buy. Never
/// suggests assuming one batch.
String gapBody(ComponentGap gap) => switch (gap.reason) {
  ComponentYieldMissing() =>
    'Set its yield and this session gets a scale. Until then there is no '
        'honest number to put here.',
  ComponentFamilyMismatch(:final lineFamily, :final yieldFamilies) =>
    'The line is in ${lineFamily.said} and the yield only says '
        '${yieldFamilies.map((f) => f.said).toSet().join(' / ')}. State a '
        'second denomination in that family — two stated facts, not an '
        'invented bridge.',
  ComponentAmountMissing() =>
    'Set an amount on that line and this session gets a scale. Until then '
        'there is no honest number to put here.',
  ComponentMeasureMissing() =>
    'The number is kept; what it counted is not. Say that line’s amount '
        'again, in a measure ${gap.title} still has.',
  ComponentCycle() =>
    'A recipe cannot be built from itself. Change one of the links and the '
        'plan can derive it again.',
};

/// Whether the gap's one-tap fix is the target's yield. A missing amount or a
/// cycle is fixed on the parent's line, so those offer no button.
bool gapOffersYieldFix(ComponentGap gap) =>
    gap.reason is ComponentYieldMissing ||
    gap.reason is ComponentFamilyMismatch;

/// The amber "split" note: a later meal outran the fridge window, so the dish
/// becomes two cooks.
String splitNoteFor(RecipeCookPlan recipe) {
  final keeps = recipe.keepsForDays;
  final window = keeps == null ? 'shelf-life' : '$keeps-day';
  return 'A later meal falls past the $window window — cook it again, fresh.';
}

/// The blue "freezer" note for a session that reaches a far meal from the
/// freezer: cook once on the cook day, freeze the distant share.
String freezerNoteFor(
  String recipeTitle,
  CookSession session,
  WeekShape shape,
) {
  final cook = shape.labelFull(session.cookDay);
  final frozen = session.frozenDays;
  if (frozen.isEmpty) return '';
  if (frozen.length == 1) {
    final day = shape.labelFull(frozen.first);
    return '$day is far off, but $recipeTitle freezes — cook once $cook, '
        "freeze $day's share.";
  }
  final days = frozen.map(shape.labelFull).join(' & ');
  return '$days are far off, but $recipeTitle freezes — cook once $cook, '
      'freeze those shares.';
}

/// The geometry of a session's freshness timeline on the week's axis (day
/// coordinates 0..6).
///
/// From the cook day a fresh window runs for the fridge shelf life; a freezable
/// session extends into a frozen tail to reach a later meal, otherwise a "gone"
/// tail runs to the week's last day. Each of [coveredDays] is a marker;
/// [cookDay] is the solid one.
class CookTimelineSpec {
  const CookTimelineSpec({
    required this.cookDay,
    required this.coveredDays,
    required this.freshTo,
    required this.frozenTo,
    required this.hasGone,
  });

  factory CookTimelineSpec.of(CookSession session) {
    final cookDay = session.cookDay;
    final covered = session.coveredDays;
    final keeps = session.keepsForDays;

    // Unknown shelf life: green simply spans from the cook day to the last
    // meal (never invent an expiry), no frozen or gone tail.
    if (keeps == null) {
      final last = math.max(session.lastCoveredDay, cookDay).toDouble();
      return CookTimelineSpec(
        cookDay: cookDay,
        coveredDays: covered,
        freshTo: last,
        frozenTo: last,
        hasGone: false,
      );
    }

    // The fridge window end, clamped to the week's last day.
    final windowEnd = math.min(cookDay + keeps, 6).toDouble();
    if (session.hasFreezerRescue) {
      // Amber from the fridge edge out to the last frozen meal.
      final frozenTo = math.min(session.frozenDays.last, 6).toDouble();
      return CookTimelineSpec(
        cookDay: cookDay,
        coveredDays: covered,
        freshTo: windowEnd,
        frozenTo: windowEnd < frozenTo ? frozenTo : windowEnd,
        hasGone: false,
      );
    }
    return CookTimelineSpec(
      cookDay: cookDay,
      coveredDays: covered,
      freshTo: windowEnd,
      frozenTo: windowEnd,
      // A hatched tail runs to the week's end when the window closes first.
      hasGone: windowEnd < 6,
    );
  }

  /// The day the batch is cooked (0..6 from the week's first day) — the solid
  /// marker.
  final int cookDay;

  /// The days a meal is eaten from this batch — the markers.
  final List<int> coveredDays;

  /// Day coordinate where the green fresh window ends.
  final double freshTo;

  /// Day coordinate where the blue frozen tail ends (== [freshTo] when the
  /// session doesn't lean on the freezer).
  final double frozenTo;

  /// Whether a hatched "gone" tail runs from [frozenTo] to the week's end.
  final bool hasGone;
}

/// Everything one cook session says, gathered once so the phone's tile and the
/// desk's row print the same words.
class SessionSpeech {
  const SessionSpeech({
    required this.when,
    required this.scale,
    required this.trackScale,
    required this.covers,
    required this.wholeBatchShown,
    this.words = const [],
    this.nudge,
  });

  /// The speech for [session] in the week's [shape]. [showWholeBatch] is the
  /// display toggle's state (never persisted); [denomination] is the target's
  /// stated yield for a component session, null dropping the clause.
  factory SessionSpeech.of(
    CookSession session,
    WeekShape shape, {
    bool showWholeBatch = false,
    YieldDenomination? denomination,
  }) {
    // A component session is never nudged to a whole batch: batches ARE its
    // denomination (the domain returns null for it).
    final nudge = wholeBatchNudgeFor(session);
    final whole = nudge != null && showWholeBatch;
    final component = session.isComponent;
    return SessionSpeech(
      when: component
          // A component batch has to be ready BY its parents' cook day, not on
          // one of its own.
          ? componentWhenLabel(session.demands.map((d) => d.cookDay), shape)
          : 'Cook ${shape.labelShort(session.cookDay)}',
      scale: component
          ? componentScaleLabel(session)
          : whole
          ? '×${nudge.factor}'
          : formatScale(session.scaleFactor),
      trackScale: component
          ? formatScale(session.batchesToCook ?? 0)
          : whole
          ? '×${nudge.factor}'
          : formatScale(session.scaleFactor),
      covers: component
          ? componentCoversLine(session, shape, denomination: denomination)
          : coversLine(session, shape),
      // One line per demand said in one of this recipe's own words.
      words: [
        for (final d in session.demands)
          if (componentDemandLine(
                quantity: d.quantity,
                measure: d.measure,
                batches: d.batches,
              )
              case final line?)
            line,
      ],
      wholeBatchShown: whole,
      nudge: nudge == null
          ? null
          : whole
          ? 'showing the whole batch — tap for the honest '
                '${formatScale(session.scaleFactor)}'
          : wholeBatchNudgeLine(nudge, rawFactor: session.scaleFactor),
    );
  }

  /// The day this batch is named for — `Cook Mon`, or a component's `Cook by
  /// Sat`.
  final String when;

  /// The scale as the reader sees it: `×1.5`, a component's `×0.25 batch`, or
  /// the nudged whole batch while the toggle is on.
  final String scale;

  /// The same scale with no denomination word, for the tick on a seven-day
  /// track where a day is sixty-odd pixels wide.
  final String trackScale;

  /// The "covers …" sentence.
  final String covers;

  /// One line per demand said in one of the recipe's own words: "3 blob → 45 g
  /// → 0.15 of a batch" ([componentDemandLine]). Empty for meal sessions and
  /// catalog-unit demands.
  final List<String> words;

  /// Whether the whole-batch view is the one on screen.
  final bool wholeBatchShown;

  /// The whole-batch line — the nudge before a tap, the way back after one.
  /// Null when the batch is already whole, and for every component session.
  final String? nudge;
}

/// What one day carries on a Cook row's track: nothing, a day this batch feeds,
/// or a day it feeds past its keep window (reachable only from the freezer).
enum CookTrackDot { none, eaten, pastWindow }

/// One day of one recipe's track on the wide Cook sheet.
class CookTrackDay {
  const CookTrackDay({
    this.keeps = false,
    this.cookScale,
    this.unscaled = false,
    this.dot = CookTrackDot.none,
  });

  /// The keep window runs through this day — the herb-soft band.
  final bool keeps;

  /// A cook session starts here, and this is its `×N` — the herb tick.
  final String? cookScale;

  /// A batch is wanted here and the plan could not scale it: the tick of a
  /// component gap.
  final bool unscaled;

  /// Whether a meal eats from this recipe today, and whether it is inside the
  /// window.
  final CookTrackDot dot;
}

/// The seven days of one recipe's track, merged from all of its sessions.
///
/// Each session contributes a tick on its cook day, a band to the end of its
/// keep window ([CookTimelineSpec] owns the geometry) and a dot on every other
/// day it feeds, amber past the window. Sessions of one recipe never share a
/// day.
List<CookTrackDay> cookTrackDays(List<(CookSession, String)> sessions) {
  final keeps = List.filled(7, false);
  final scales = List<String?>.filled(7, null);
  final dots = List.filled(7, CookTrackDot.none);
  for (final (session, scale) in sessions) {
    if (session.cookDay < 0 || session.cookDay > 6) continue;
    final spec = CookTimelineSpec.of(session);
    scales[session.cookDay] = scale;
    final windowEnd = spec.freshTo.floor().clamp(0, 6);
    for (var day = session.cookDay; day <= windowEnd; day++) {
      keeps[day] = true;
    }
    for (final day in session.coveredDays) {
      if (day == session.cookDay || day < 0 || day > 6) continue;
      dots[day] = day > spec.freshTo
          ? CookTrackDot.pastWindow
          : CookTrackDot.eaten;
    }
  }
  return [
    for (var day = 0; day < 7; day++)
      CookTrackDay(keeps: keeps[day], cookScale: scales[day], dot: dots[day]),
  ];
}

/// The track of a component the plan could not derive: a tick on every day a
/// batch is wanted, no band and no scale.
List<CookTrackDay> cookTrackDaysForGap(Iterable<int> days) {
  final wanted = days.where((d) => d >= 0 && d <= 6).toSet();
  return [
    for (var day = 0; day < 7; day++)
      CookTrackDay(unscaled: wanted.contains(day)),
  ];
}

/// The day-of-month figure under a day's initials on the sheet's shared axis.
String cookSheetDayNumber(DateTime weekStart, int dayOfWeek) =>
    '${weekStart.add(Duration(days: dayOfWeek)).day}';
