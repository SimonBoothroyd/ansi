/// Riverpod reads of the household's fridge and freezer, for the Leftovers
/// page, its door on the Week, the picker's *Use up* and Cook's batch line.
library;

import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../planning/presentation/week_view_models.dart';
import '../data/cook_plan_providers.dart';
import '../domain/leftovers.dart';

part 'leftovers_view_models.g.dart';

/// The household's leftovers today, fridge first, live. Read from the week
/// holding today, whatever week is on screen: the fridge is now.
@riverpod
Stream<List<Leftover>> fridgeAndFreezer(Ref ref) => ref
    .watch(leftoverRepositoryProvider)
    .watchHouseholdLeftovers(
      weekStart: ref.watch(currentWeekStartProvider),
      today: ref.watch(todayProvider),
    );

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

/// The rows a meal on [day] can be planned from, fridge then freezer: a fridge
/// row good on the day and not yet behind its date, any freezer row. Only a
/// recipe's row: a meal is planned from a recipe. Empty for a day behind us.
@riverpod
List<Leftover> leftoversGoodOn(Ref ref, DateTime day) {
  final today = ref.watch(todayProvider);
  if (DateTime(day.year, day.month, day.day).isBefore(today)) return const [];
  return [
    for (final left
        in ref.watch(fridgeAndFreezerProvider).asData?.value ??
            const <Leftover>[])
      if (left.recipeId != null &&
          left.isGoodOn(day) &&
          !(left.place == LeftoverPlace.fridge && left.pastItsDate(today)))
        left,
  ];
}
