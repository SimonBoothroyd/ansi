/// Riverpod reads of the household's fridge and freezer, for the Leftovers
/// page, its door on the Week, the picker's *Use up*, Cook's batch line and
/// the Week's `leftover` tag.
library;

import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../planning/presentation/week_view_models.dart';
import '../data/cook_plan_providers.dart';
import '../domain/leftovers.dart';

part 'leftovers_view_models.g.dart';

/// The household's leftovers today and every meal served from one, live.
/// Read from the week holding today, whatever week is on screen: the fridge
/// is now.
@riverpod
Stream<LeftoverShelves> leftoverShelves(Ref ref) => ref
    .watch(leftoverRepositoryProvider)
    .watchHouseholdLeftovers(
      weekStart: ref.watch(currentWeekStartProvider),
      today: ref.watch(todayProvider),
    );

/// The rows of [leftoverShelves], fridge first.
@riverpod
AsyncValue<List<Leftover>> fridgeAndFreezer(Ref ref) =>
    ref.watch(leftoverShelvesProvider).whenData((s) => s.rows);

/// Each meal served from a leftover, judged on its own day, by `plan_entry`
/// id: its shelf and any warning.
@riverpod
Map<String, LeftoverMeal> leftoverMeals(Ref ref) =>
    ref.watch(leftoverShelvesProvider).asData?.value.meals ?? const {};

/// Whether any row is behind its date: the dot on the Week's door.
@riverpod
bool anyLeftoverPastItsDate(Ref ref) {
  final today = ref.watch(todayProvider);
  return (ref.watch(fridgeAndFreezerProvider).asData?.value ?? const []).any(
    (l) => l.pastItsDate(today),
  );
}

/// Which shelf each stored row is on, by id: a meal planned from one wears
/// that shelf's tag on the Week.
@riverpod
Stream<Map<String, LeftoverPlace>> leftoverPlaces(Ref ref) =>
    ref.watch(leftoverRepositoryProvider).watchLeftoverPlaces();

/// The rows a meal on [day] can be planned from, fridge then freezer, each as
/// [leftoverOfferOn] offers it for that day: judged on [day], a fridge row
/// that will need freezing by then offered under Freezer. Only a recipe's
/// row: a meal is planned from a recipe. Empty for a day behind us.
@riverpod
List<Leftover> leftoversGoodOn(Ref ref, DateTime day) {
  final today = ref.watch(todayProvider);
  if (DateTime(day.year, day.month, day.day).isBefore(today)) return const [];
  final offers = [
    for (final left
        in ref.watch(fridgeAndFreezerProvider).asData?.value ??
            const <Leftover>[])
      if (leftoverOfferOn(left, day, today) case final offer?) offer,
  ];
  return [
    for (final place in LeftoverPlace.values)
      for (final offer in offers)
        if (offer.place == place) offer,
  ];
}
