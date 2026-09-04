/// Planning domain entities — the read aggregate the Week screen renders.
///
/// PURE DART (invariant 2): no `package:flutter`. A [WeekPlan] is one week
/// (addressed by its Monday `weekStart`) holding the [PlanEntry] meals planned
/// across its seven days. A [Member] is a person in the household; an entry's
/// [PlanEntry.eaterIds] point at them and the sum of their
/// [Member.portionFactor]s is the entry's demand ([demandPortions]) unless the
/// entry's whole-number [PlanEntry.portions] override says otherwise.
///
/// Meal slots are free text (spec §8, not an enum); [kDefaultMealSlots] are the
/// three the UI offers, and [mealSlotRank] orders known slots ahead of custom
/// ones within a day. [mondayOf] resolves the active week from a date.
library;

// Freezed needs each class's private `._` constructor before the factory (for
// the custom getters), which trips the unnamed-first sort lint.
// ignore_for_file: sort_unnamed_constructors_first
import 'package:freezed_annotation/freezed_annotation.dart';

part 'planning.freezed.dart';

/// A person in the household. Eaters on a [PlanEntry] reference its id;
/// [initial] is the avatar letter.
@freezed
abstract class Member with _$Member {
  const Member._();

  const factory Member({
    required String id,
    required String displayName,

    /// The person's usual portion as a multiple of one recipe serving: `0.75`
    /// for someone who eats three-quarters of a serving. A standing fact about
    /// the person, spent wherever a demand is counted — the cook plan, the
    /// shopping list and the macro lens all read it through [demandPortions].
    /// Quarter steps from 0.25 to 3; the default `1` makes a member weigh
    /// exactly one head.
    @Default(1.0) double portionFactor,
  }) = _Member;

  /// The uppercase first letter of [displayName] for the avatar, or '?' when
  /// the name is empty.
  String get initial =>
      displayName.trim().isEmpty ? '?' : displayName.trim()[0].toUpperCase();
}

/// The portion factors the household can be set to from the segment (P-D2):
/// the five quick picks, and *custom* in quarter steps between
/// [kPortionFactorMin] and [kPortionFactorMax].
const kPortionFactorPicks = [0.5, 0.75, 1.0, 1.25, 1.5];
const kPortionFactorMin = 0.25;
const kPortionFactorMax = 3.0;
const kPortionFactorStep = 0.25;

/// Whether [factor] is one the column accepts: a quarter step within
/// [kPortionFactorMin]..[kPortionFactorMax] (the `0026` check constraint,
/// mirrored so the sheet never offers a value the server would refuse).
bool isValidPortionFactor(double factor) {
  if (factor < kPortionFactorMin - 1e-9 || factor > kPortionFactorMax + 1e-9) {
    return false;
  }
  final steps = factor / kPortionFactorStep;
  return (steps - steps.roundToDouble()).abs() < 1e-9;
}

/// Σ [Member.portionFactor] over [eaterIds] — what the eaters on a meal
/// usually eat, in portions. An eater the roster no longer holds (a
/// tombstoned member) counts as one portion, exactly as the head-count did.
double eatersDemand(
  Iterable<String> eaterIds,
  Map<String, Member> membersById,
) => eaterIds.fold(0, (sum, id) => sum + (membersById[id]?.portionFactor ?? 1));

/// An entry's demand in portions (P-D1): the whole-number [PlanEntry.portions]
/// override when one is set, else [eatersDemand] over its eaters. Fractional
/// by design — `1¾` for a 1 and a ¾ eater — and printed as a fraction, never
/// rounded (P-D4). With every factor at 1 this is [PlanEntry.portionsOrDefault]
/// to the digit (P-D6).
double demandPortions(PlanEntry entry, Map<String, Member> membersById) =>
    entry.portions?.toDouble() ?? eatersDemand(entry.eaterIds, membersById);

/// One planned meal: a [recipeId] (with [recipeTitle] denormalised for display)
/// on [dayOfWeek] (0=Monday..6=Sunday) under a free-text [mealSlot], eaten by
/// [eaterIds]. [recipeTitle] is null when the recipe was deleted.
@freezed
abstract class PlanEntry with _$PlanEntry {
  const PlanEntry._();

  const factory PlanEntry({
    required String id,
    required int dayOfWeek,
    required String mealSlot,
    required String recipeId,
    String? recipeTitle,
    @Default(<String>[]) List<String> eaterIds,

    /// How many portions to cook for. Null means "track the eater count"; a
    /// number is an explicit override for big/small appetites (spec §8).
    int? portions,
  }) = _PlanEntry;

  /// The entry's own portion count before the household's factors: the
  /// [portions] override, or the eater HEAD-count. The demand a plan cooks
  /// for is [demandPortions], which weighs each eater by their
  /// [Member.portionFactor]; this is the factor-less figure the override
  /// stepper counts in.
  int get portionsOrDefault => portions ?? eaterIds.length;
}

/// One active week, addressed by [weekStart] (a Monday, date-only). [entries]
/// are every meal planned across the week; the view groups them by day.
@freezed
abstract class WeekPlan with _$WeekPlan {
  const WeekPlan._();

  const factory WeekPlan({
    required String id,
    required DateTime weekStart,
    String? label,
    @Default(<PlanEntry>[]) List<PlanEntry> entries,
  }) = _WeekPlan;

  /// The entries on [dayOfWeek] (0=Monday..6=Sunday), ordered by meal slot then
  /// their stored order — one day column of the grid. [entries] is assumed to
  /// already carry the repository's within-slot order (sort_order, created_at);
  /// this decorates with the source index for a stable sort, since Dart's
  /// [List.sort] is not guaranteed stable.
  List<PlanEntry> entriesForDay(int dayOfWeek) {
    final day = entries.where((e) => e.dayOfWeek == dayOfWeek).toList();
    final indexed = [for (var i = 0; i < day.length; i++) (i, day[i])]
      ..sort((a, b) {
        final ra = mealSlotRank(a.$2.mealSlot);
        final rb = mealSlotRank(b.$2.mealSlot);
        return ra != rb ? ra.compareTo(rb) : a.$1.compareTo(b.$1);
      });
    return [for (final p in indexed) p.$2];
  }
}

/// The meal slots the UI offers by default. Users may type any other label
/// (spec §8) — these are only the quick picks and the canonical display order.
const kDefaultMealSlots = ['Breakfast', 'Lunch', 'Dinner'];

/// Orders a meal slot within a day: the known slots first, in meal order, then
/// any custom slot (rank = [kDefaultMealSlots].length) alphabetically-stable by
/// insertion. Case-insensitive so "dinner" and "Dinner" rank together.
int mealSlotRank(String slot) {
  final i = kDefaultMealSlots.indexWhere(
    (s) => s.toLowerCase() == slot.toLowerCase(),
  );
  return i < 0 ? kDefaultMealSlots.length : i;
}

/// The Monday (date-only, UTC) of the week containing [date] — the app's active
/// week. Dart weekdays are 1=Mon..7=Sun, so Monday is `date - (weekday - 1)`.
DateTime mondayOf(DateTime date) {
  final d = DateTime.utc(date.year, date.month, date.day);
  return d.subtract(Duration(days: d.weekday - 1));
}
