/// Display formatting for the Cook screen — pure Dart (no widgets), so the
/// batch-plan copy and the timeline geometry are unit-testable.
library;

import 'dart:math' as math;

import '../../planning/presentation/week_format.dart';
import '../../recipes/domain/component_math.dart';
import '../../recipes/presentation/component_format.dart';
import '../../recipes/presentation/format.dart';
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
  // A component session covers no meals — it answers other recipes' component
  // lines, in batches (step 8.6 / D3). Portions are the wrong denomination for
  // it, so the line names the plans it serves instead. The full card face
  // (the batch scale, "makes 1 cup, you need ¼") is the board's frame (f).
  if (session.isComponent) return 'covers ${session.demandedBy.join(' + ')}';

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

/// The batch scale a component session reads: *"×0.25 batch"*. Portions are
/// the wrong denomination for a sauce, so this never says portions — and it
/// never says `×1` as a stand-in, because a session only exists here once its
/// batch math resolved.
String componentScaleLabel(CookSession session) =>
    '${formatScale(session.batchesToCook ?? 0)} batch';

/// The day a component batch has to be ready BY — its demanding parents' cook
/// days, which is why the tile reads "Cook by Sat" and not "Cook Sat".
String componentWhenLabel(Iterable<int> days) {
  final sorted = days.toSet().toList()..sort();
  if (sorted.isEmpty) return 'Cook by';
  return 'Cook by ${sorted.map((d) => kWeekdayShort[d]).join(' + ')}';
}

/// A component session's "covers …" line: who needs it and when, closing with
/// the batch arithmetic when the target states a yield — *"covers Sausage
/// Sliders · cook Sat — makes 1 cup, you need 0.25"*.
///
/// [denomination] is the target's first stated yield, or null for a recipe
/// that says nothing about what it makes; the clause is simply dropped then,
/// never filled with a guess.
String componentCoversLine(
  CookSession session, {
  YieldDenomination? denomination,
}) {
  final days = (session.demands.map((d) => d.cookDay).toSet().toList()..sort())
      .map((d) => kWeekdayShort[d])
      .join(' + ');
  final head = 'covers ${session.demandedBy.join(' + ')} · cook $days';
  if (denomination == null) return head;
  final batches = session.batchesToCook ?? 0;
  return '$head — ${yieldText(denomination)}, '
      'you need ${formatQuantity(batches)}';
}

/// The amber note under a component session that needs less than a whole run
/// of the recipe (board frame f's split-note): a batch makes what it makes,
/// the day needs a share of it, and the rest is the cook's business — this app
/// does not track leftovers (an 8.6 non-goal, said out loud rather than
/// silently implied).
///
/// Null when the demand is a whole number of batches (nothing is left over) or
/// when the target states no yield (there is no honest sentence to write).
String? componentLeftoverNote(
  CookSession session, {
  YieldDenomination? denomination,
}) {
  final batches = session.batchesToCook;
  if (batches == null || denomination == null) return null;
  if (batches == batches.roundToDouble()) return null;
  return 'A batch makes ${formatQuantity(denomination.qty)} '
      '${denomination.unit.label} and ${kWeekdayFull[session.cookDay]} needs '
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
  ComponentFamilyMismatch() => 'yield in another family',
  ComponentCycle() => 'used inside itself',
};

/// The gap card's "covers …" line — *"covers Sausage Sliders · cook Sat — the
/// line asks for 0.25 cup"* (board frame f).
///
/// It quotes the same shape a resolved session's does, minus every number it
/// cannot honestly state. The closing clause is the one number a gap CAN
/// state: what the demanding line printed. It is deliberately unscaled and
/// un-converted — the whole reason this card exists is that the arithmetic
/// against the yield cannot be done.
///
/// A numberless line ([ComponentAmountMissing]) has no amount to quote, so the
/// clause is dropped rather than filled. With more than one demanding parent
/// each clause names its own, since "the line" would then be ambiguous.
String gapCoversLine(ComponentGap gap) {
  final days = (gap.demandedBy.map((d) => d.cookDay).toSet().toList()..sort())
      .map((d) => kWeekdayShort[d])
      .join(' + ');
  final parents = gap.demandedBy.map((d) => d.title).toSet().join(' + ');
  final head = 'covers $parents · cook $days';

  final asks = [
    for (final d in gap.demandedBy)
      if (d.quantity != null) d,
  ];
  if (asks.isEmpty) return head;
  if (gap.demandedBy.length == 1) {
    final ask = asks.single;
    return '$head — the line asks for '
        '${componentAmountText(ask.quantity, ask.unit)}';
  }
  final clauses = asks
      .map(
        (d) => '${d.title} asks for ${componentAmountText(d.quantity, d.unit)}',
      )
      .join(' · ');
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
  ComponentCycle() => '${gap.title} is used inside itself',
};

/// The warn state's body: what setting the missing fact would buy, and why
/// there is nothing in the meantime. Never "assume one batch" — that is
/// exactly the invented number this app refuses.
String gapBody(ComponentGap gap) => switch (gap.reason) {
  ComponentYieldMissing() =>
    'Set its yield and this session gets a scale. Until then there is no '
        'honest number to put here.',
  ComponentFamilyMismatch(:final lineFamily, :final yieldFamilies) =>
    'The line is in ${lineFamily.name} and the yield only says '
        '${yieldFamilies.map((f) => f.name).toSet().join(' / ')}. State a '
        'second denomination in that family — two stated facts, not an '
        'invented bridge.',
  ComponentAmountMissing() =>
    'Set an amount on that line and this session gets a scale. Until then '
        'there is no honest number to put here.',
  ComponentCycle() =>
    'A recipe cannot be built from itself. Change one of the links and the '
        'plan can derive it again.',
};

/// Whether the gap's one-tap fix is the target's yield — the cases the board
/// draws a "Set the yield" affordance for. An amount or a cycle is fixed on
/// the *parent's* line, so this card offers no button for them rather than
/// sending the reader somewhere that cannot help.
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
