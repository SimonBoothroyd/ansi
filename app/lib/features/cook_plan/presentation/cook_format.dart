/// Display formatting for the Cook screen — pure Dart (no widgets), so the
/// batch-plan copy and the timeline geometry are unit-testable.
library;

import 'dart:math' as math;

import '../../planning/presentation/week_format.dart';
import '../domain/cook_plan.dart';

/// The batch multiplier, e.g. `×1`, `×1.5`, `×0.75`. Trims trailing zeros.
String formatScale(double factor) {
  final s = factor
      .toStringAsFixed(2)
      .replaceAll(RegExp(r'0+$'), '')
      .replaceAll(RegExp(r'\.$'), '');
  return '×$s';
}

/// "1 portion" / "4 portions" — a count with the right plural.
String formatPortions(int count) => '$count portion${count == 1 ? '' : 's'}';

/// [formatPortions] for a possibly-fractional count ("2.5 portions") — whole
/// batches of a fractional `servings_base` yield these. Trims like
/// [formatScale].
String formatPortionsAmount(double count) {
  final s = count
      .toStringAsFixed(2)
      .replaceAll(RegExp(r'0+$'), '')
      .replaceAll(RegExp(r'\.$'), '');
  return '$s portion${s == '1' ? '' : 's'}';
}

/// The whole-batch nudge line for a fractional session (step 7.6):
/// "cook ×1 instead — covers 4 portions · 1 portion left over · shopping
/// still buys ×0.75". The honest raw factor stays on the tile; this is
/// advice beside it, never a replacement (invariant 3) — and the closing
/// clause is honest about the accepted gap (tech-debt tracker): the shopping
/// list keeps scaling by [rawFactor], so a cook following the advice tops up
/// by eye until the nudge is persisted and the list can read it.
String wholeBatchNudgeLine(
  WholeBatchNudge nudge, {
  required double rawFactor,
}) =>
    'cook ×${nudge.factor} instead — covers '
    '${formatPortionsAmount(nudge.batchPortions)} · '
    '${formatPortionsAmount(nudge.leftoverPortions)} left over · '
    'shopping still buys ${formatScale(rawFactor)}';

/// The recipe card's summary line: total portions across the week plus its
/// shelf-life descriptors (e.g. "4 portions across the week · keeps 4 d").
String recipeSummaryLine(RecipeCookPlan recipe) {
  final parts = <String>[
    '${formatPortions(recipe.totalPortions)} across the week',
  ];
  final keeps = recipe.keepsForDays;
  if (keeps != null) parts.add('keeps $keeps d');
  if (recipe.freezable) parts.add('freezable');
  return parts.join(' · ');
}

/// A session's "covers …" line. Collapses the slot when every covered meal
/// shares one ("Tue + Sat dinner"); otherwise spells each out ("Mon dinner +
/// Thu lunch"). Ends with the portion count.
String coversLine(CookSession session) {
  final covers = session.covers;
  final slots = {for (final m in covers) m.mealSlot.toLowerCase()};
  final portions = formatPortions(session.totalPortions);

  if (slots.length == 1) {
    // Distinct days, one shared slot.
    final days = (<int>{
      for (final m in covers) m.dayOfWeek,
    }.toList()..sort()).map((d) => kWeekdayShort[d]).join(' + ');
    return 'covers $days ${slots.first} · $portions';
  }
  final meals = covers
      .map((m) => '${kWeekdayShort[m.dayOfWeek]} ${m.mealSlot.toLowerCase()}')
      .join(' + ');
  return 'covers $meals · $portions';
}

/// The amber "split" note: a later meal outran the fridge window, so the dish
/// becomes two cooks.
String splitNoteFor(RecipeCookPlan recipe) {
  final keeps = recipe.keepsForDays;
  final window = keeps == null ? 'shelf-life' : '$keeps-day';
  return 'A later meal falls past the $window window — cook it again, fresh.';
}

/// The blue "freezer" note for a session that reaches a far meal from the
/// freezer: cook once on the cook day, freeze the distant share.
String freezerNoteFor(String recipeTitle, CookSession session) {
  final cook = kWeekdayFull[session.cookDay];
  final frozen = session.frozenDays;
  if (frozen.isEmpty) return '';
  if (frozen.length == 1) {
    final day = kWeekdayFull[frozen.first];
    return '$day is far off, but $recipeTitle freezes — cook once $cook, '
        "freeze $day's share.";
  }
  final days = frozen.map((d) => kWeekdayFull[d]).join(' & ');
  return '$days are far off, but $recipeTitle freezes — cook once $cook, '
      'freeze those shares.';
}

/// The geometry of a session's freshness timeline on a fixed **Mon→Sun** axis
/// (day coordinates 0..6). Painting it against the whole week keeps every
/// session comparable at a glance and shows where in the week it sits.
///
/// From the cook day, a green fresh window runs for the fridge shelf life; a
/// freezable session extends into a blue "frozen" tail to reach a later meal;
/// otherwise a hatched "gone" tail runs from the window's end to Sunday. Each
/// eaten day ([coveredDays]) is a marker; the [cookDay] is the solid one.
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

    // The fridge window end, clamped to Sunday.
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
      // A hatched tail runs to Sunday when the window closes before then.
      hasGone: windowEnd < 6,
    );
  }

  /// The day the batch is cooked (0=Mon..6=Sun) — the solid marker.
  final int cookDay;

  /// The days a meal is eaten from this batch — the markers.
  final List<int> coveredDays;

  /// Day coordinate where the green fresh window ends.
  final double freshTo;

  /// Day coordinate where the blue frozen tail ends (== [freshTo] when the
  /// session doesn't lean on the freezer).
  final double frozenTo;

  /// Whether a hatched "gone" tail runs from [frozenTo] to Sunday.
  final bool hasGone;
}
