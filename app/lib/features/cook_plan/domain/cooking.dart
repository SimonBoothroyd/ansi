/// A cooking: one pot, remembered rather than re-derived. Pure Dart.
///
/// A cooking is **born** at the first tick on any meal of its group, or at
/// the first pick from it, and keeps its id from then on. Meals link to it
/// (`plan_entry.cooking`); its own meals and meals picked from it later are
/// the same kind of link. Before birth, a week's unlinked meals of a recipe
/// group into one cooking by shelf life ([cookingGroupOf]), days 0..6 of that
/// week alone.
///
/// What it **made** is fixed at its first tick; before that it is the live
/// sum of its linked meals' portions ([madeOf]). Whether it was **cooked**,
/// and on which day, is read from the ticks every time ([cookDayOfCooking]),
/// so an untick needs no write. Food said by hand (added on the Leftovers
/// page, or carried over from the old fridge rows) is dated by its `since`.
/// A cooking is **bought** in the week of its earliest linked meal
/// ([boughtIn]); a linked meal in any other week buys nothing.
library;

import 'package:meta/meta.dart';

import 'cook_plan.dart';

/// Where a leftover is kept.
enum LeftoverPlace { fridge, freezer }

/// A `cooking` row as stored. Exactly one of [recipeId] or [label].
@immutable
class Cooking {
  const Cooking({
    required this.id,
    this.recipeId,
    this.label,
    this.made,
    this.place,
    this.since,
    this.goneAt,
  }) : assert(
         (recipeId == null) != (label == null),
         'a recipe or words, never both (the server refuses it)',
       );

  final String id;
  final String? recipeId;

  /// The household's own words for food the app has no recipe for.
  final String? label;

  /// Portions made, fixed at the first tick; null while it is the live sum
  /// of its linked meals ([madeOf]).
  final double? made;

  /// Where food said by hand went; null on a cooking dated by its ticks.
  final LeftoverPlace? place;

  /// The day food said by hand was cooked; null on a cooking dated by its
  /// ticks.
  final DateTime? since;

  /// When it was said to have gone off: final, an untick never brings it
  /// back.
  final DateTime? goneAt;

  /// Food said by hand, dated by [since] rather than by ticks.
  bool get saidByHand => since != null;

  @override
  String toString() =>
      'Cooking($id, ${recipeId ?? label}, made $made'
      '${since == null ? '' : ', ${place?.name} since $since'}'
      '${goneAt == null ? '' : ', gone'})';
}

/// One live meal linked to a cooking, as a reader hands it in: the week it is
/// planned in, its day, its planned [portions] and the shares its live ticks
/// say were eaten. A tick counts even if its member was taken off the meal
/// since: they ate a portion.
@immutable
class CookingMeal {
  const CookingMeal({
    required this.entryId,
    required this.weekStart,
    required this.day,
    required this.portions,
    this.eaten = 0,
  });

  final String entryId;

  /// The first day of the week the meal is planned in: the buy week, for a
  /// cooking's earliest meal.
  final DateTime weekStart;

  /// The meal's calendar day.
  final DateTime day;

  /// What the meal demands: its portions override, else its eaters' factors.
  final double portions;

  /// What its ticks say was eaten, uncapped.
  final double eaten;

  /// Whether anybody ticked it.
  bool get ticked => eaten > 1e-9;

  /// What it takes from its cooking on [today]: a meal behind today its
  /// ticked shares, never more than its portions; today's or a later meal
  /// its planned portions in full, spoken for.
  double takeOn(DateTime today) {
    if (!_dateOnly(day).isBefore(_dateOnly(today))) return portions;
    if (eaten <= 0) return 0;
    return eaten > portions ? portions : eaten;
  }

  @override
  String toString() => 'CookingMeal($entryId, $day, $portions, ate $eaten)';
}

/// A recipe's name and shelf life, as a cooking's dates read them.
typedef CookingShelfLife = ({
  String title,
  int? keepsForDays,
  bool freezable,
  int? freezerDays,
});

/// The sum of a cooking's live change rows, per shelf.
typedef CookingChanges = ({double fridge, double freezer});

/// What [cooking] made: [Cooking.made] once fixed, else the live sum of its
/// [meals]' portions.
double madeOf(Cooking cooking, List<CookingMeal> meals) =>
    cooking.made ?? meals.fold<double>(0, (s, m) => s + m.portions);

/// The day [cooking] was cooked: its `since` for food said by hand, else the
/// earliest day of its [meals] anybody ticked, in whatever order the ticks
/// came. Null while nobody ticked any: not cooked (yet).
DateTime? cookDayOfCooking(Cooking cooking, List<CookingMeal> meals) {
  final since = cooking.since;
  if (since != null) return _dateOnly(since);
  DateTime? earliest;
  for (final m in meals) {
    if (!m.ticked) continue;
    final day = _dateOnly(m.day);
    if (earliest == null || day.isBefore(earliest)) earliest = day;
  }
  return earliest;
}

/// The day a cooking nobody ticked is to be cooked on [today]: the first of
/// its [meals] not yet behind us (`cook Thu`). Null once every meal is behind
/// us: it was never cooked, and nothing is left.
DateTime? nextCookDayOf(List<CookingMeal> meals, DateTime today) {
  final day = _dateOnly(today);
  DateTime? next;
  for (final m in meals) {
    final d = _dateOnly(m.day);
    if (d.isBefore(day)) continue;
    if (next == null || d.isBefore(next)) next = d;
  }
  return next;
}

/// The first day of the week [cooking] is bought and costed in: the week of
/// its earliest linked meal (by day, then id, so every reader agrees). Null
/// for food said by hand, which is bought already, and for a cooking with no
/// live meal.
DateTime? boughtIn(Cooking cooking, List<CookingMeal> meals) {
  if (cooking.saidByHand || meals.isEmpty) return null;
  final first = meals.reduce((a, b) {
    final d = _dateOnly(a.day).compareTo(_dateOnly(b.day));
    if (d != 0) return d < 0 ? a : b;
    return a.entryId.compareTo(b.entryId) <= 0 ? a : b;
  });
  return _dateOnly(first.weekStart);
}

/// One meal of a week not yet in a cooking, as the group rule reads it: its
/// id and day (0..6 of its week), in the week's own order.
typedef UnlinkedMeal = ({String entryId, int dayOfWeek});

/// The meals [entryId] would share a cooking with if it were born now: its
/// week's [unlinked] meals of the same recipe, grouped by shelf life exactly
/// as the cook plan groups them ([clusterSessions]), fridge life
/// [kAssumedFridgeDays] when unknown. The group's first meal is its anchor.
/// Just [entryId] when it is not among [unlinked].
List<String> cookingGroupOf(
  String entryId, {
  required List<UnlinkedMeal> unlinked,
  int? keepsForDays,
  bool freezable = false,
  int? freezerDays,
}) {
  final sessions = clusterSessions(
    PlannedRecipe(
      recipeId: '',
      title: '',
      servingsBase: 1,
      keepsForDays: keepsForDays,
      freezable: freezable,
      freezerDays: freezerDays,
      meals: [
        for (final m in unlinked)
          CoveredMeal(
            dayOfWeek: m.dayOfWeek,
            mealSlot: '',
            portions: 1,
            entryId: m.entryId,
          ),
      ],
    ),
  );
  for (final s in sessions) {
    final ids = [for (final m in s.covers) m.entryId!];
    if (ids.contains(entryId)) return ids;
  }
  return [entryId];
}

/// The id of the cooking a [group] is born into: a cooking one of its meals
/// already links to ([linkedTo]); else one whose id is one of its meals' ids
/// ([cookingIds], the cookings that exist); else the group's anchor, its
/// first meal. Two phones with the same plan compute the same id, so a birth
/// uploaded twice is one row.
String birthIdFor(
  List<String> group, {
  Iterable<String> linkedTo = const [],
  Set<String> cookingIds = const {},
}) {
  if (linkedTo.firstOrNull case final id?) return id;
  for (final id in group) {
    if (cookingIds.contains(id)) return id;
  }
  return group.first;
}

DateTime _dateOnly(DateTime d) => DateTime(d.year, d.month, d.day);
