/// Planning domain entities — the read aggregate the Week screen renders.
///
/// PURE DART (invariant 2): no `package:flutter`. A [WeekPlan] is one week
/// (addressed by its Monday `weekStart`) holding the [PlanEntry] meals planned
/// across its seven days. A [Member] is a person in the household; an entry's
/// [PlanEntry.eaterIds] point at them and the count is the entry's demand.
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

  const factory Member({required String id, required String displayName}) =
      _Member;

  /// The uppercase first letter of [displayName] for the avatar, or '?' when
  /// the name is empty.
  String get initial =>
      displayName.trim().isEmpty ? '?' : displayName.trim()[0].toUpperCase();
}

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

  /// The effective portion demand: the [portions] override, or the eater count.
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
  /// their stored order. Used to fill one day column of the grid. [entries] is
  /// assumed to already carry the repository's within-slot order (sort_order,
  /// created_at); this decorates with the source index for a stable sort, since
  /// Dart's [List.sort] is not guaranteed stable.
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
