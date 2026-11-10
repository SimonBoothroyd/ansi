/// Riverpod reads of the household's fridge and freezer, for the Leftovers
/// page, its door on the Week, the picker's *Use up*, Cook's batch line and
/// the Week's `leftover` tag.
library;

import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../../core/week_shape.dart';
import '../../account/data/household_providers.dart';
import '../../planning/presentation/week_view_models.dart';
import '../data/cook_plan_providers.dart';
import '../domain/leftovers.dart';

part 'leftovers_view_models.g.dart';

/// The household's leftovers today and every meal served from one, live,
/// whatever week is on screen: the fridge is now.
@riverpod
Stream<LeftoverShelves> leftoverShelves(Ref ref) => ref
    .watch(leftoverRepositoryProvider)
    .watchHouseholdLeftovers(today: ref.watch(todayProvider));

/// The rows of [leftoverShelves], fridge first.
@riverpod
AsyncValue<List<Leftover>> fridgeAndFreezer(Ref ref) =>
    ref.watch(leftoverShelvesProvider).whenData((s) => s.rows);

/// Each meal linked to a cooking, judged on its own day, by `plan_entry` id:
/// its shelf and any warning.
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

/// The rows a meal on [day] can be planned from, fridge then freezer, each as
/// [leftoverOfferOn] offers it for that day: judged on [day], a fridge row
/// that will need freezing by then offered under Freezer. Soonest to go off
/// first within each. Only a recipe's row: a meal is planned from a recipe.
/// A day behind us is judged the same way, on that day: a pot good on it is
/// offered, so a meal added late can still be eaten from the fridge.
///
/// A pot not cooked yet is offered too (`cooks Sat`), once: a cooking whose
/// meals nobody ticked, and planned meals of an earlier week that no cooking
/// holds yet ([LeftoverShelves.pots]). A pot of [day]'s own week is not: a
/// meal there already shares it when it fits.
@riverpod
List<Leftover> leftoversGoodOn(Ref ref, DateTime day) {
  final today = ref.watch(todayProvider);
  final shelves = ref.watch(leftoverShelvesProvider).asData?.value;
  final week = ref.watch(weekShapeProvider).keyOf(day);
  final uncooked = <String>{};
  final offers = <Leftover>[];
  for (final left in [
    ...?shelves?.rows,
    for (final pot in shelves?.pots ?? const <Leftover>[])
      if (pot.plannedIn case final at? when isoDateOf(at) != week) pot,
  ]) {
    // A pot not cooked yet is one offer, whichever shelf it reads on.
    if (!left.cooked && !uncooked.add(left.id)) continue;
    if (leftoverOfferOn(left, day, today) case final offer?) offers.add(offer);
  }
  // A freezer with no limit goes off last.
  final never = DateTime(9999);
  offers.sort((a, b) => (a.goodUntil ?? never).compareTo(b.goodUntil ?? never));
  return [
    for (final place in LeftoverPlace.values)
      for (final offer in offers)
        if (offer.place == place) offer,
  ];
}
