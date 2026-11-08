/// A [LeftoverRepository] that hands back canned shelves and records every
/// write, for the screens that read the fridge and the freezer.
library;

import 'package:ansi/features/cook_plan/domain/leftover_repository.dart';
import 'package:ansi/features/cook_plan/domain/leftovers.dart';

class FakeLeftoverRepository implements LeftoverRepository {
  FakeLeftoverRepository([this.rows = const [], this.places = const {}]);

  /// What [watchHouseholdLeftovers] hands out, whatever the day.
  final List<Leftover> rows;

  /// What [watchLeftoverPlaces] hands out.
  final Map<String, LeftoverPlace> places;

  @override
  Stream<List<Leftover>> watchHouseholdLeftovers({
    required DateTime weekStart,
    required DateTime today,
  }) => Stream.value(rows);

  @override
  Stream<Map<String, LeftoverPlace>> watchLeftoverPlaces() =>
      Stream.value(places);

  /// Every `(row, portions)` handed to [setLeftoverPortions].
  final portionWrites = <(Leftover, double)>[];

  /// Every `(row, since)` handed to [freezeLeftover].
  final freezes = <(Leftover, DateTime)>[];

  /// Every list handed to [markLeftoversGone].
  final gone = <List<Leftover>>[];

  /// Every row handed to [addLeftover].
  final added =
      <
        ({
          LeftoverPlace place,
          double portions,
          DateTime since,
          String? recipeId,
          String? label,
        })
      >[];

  @override
  Future<void> setLeftoverPortions(Leftover left, double portions) async =>
      portionWrites.add((left, portions));

  @override
  Future<void> freezeLeftover(Leftover left, {required DateTime since}) async =>
      freezes.add((left, since));

  @override
  Future<void> markLeftoversGone(List<Leftover> lefts) async => gone.add(lefts);

  @override
  Future<String> addLeftover({
    required LeftoverPlace place,
    required double portions,
    required DateTime since,
    String? recipeId,
    String? label,
  }) async {
    added.add((
      place: place,
      portions: portions,
      since: since,
      recipeId: recipeId,
      label: label,
    ));
    return 'new';
  }
}
