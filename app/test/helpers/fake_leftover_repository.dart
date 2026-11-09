/// A [LeftoverRepository] that hands back canned shelves and records every
/// write, for the screens that read the fridge and the freezer.
library;

import 'package:ansi/features/cook_plan/domain/leftover_repository.dart';
import 'package:ansi/features/cook_plan/domain/leftovers.dart';

class FakeLeftoverRepository implements LeftoverRepository {
  FakeLeftoverRepository([this.rows = const [], this.meals = const {}]);

  /// What [watchHouseholdLeftovers] hands out, whatever the day.
  final List<Leftover> rows;

  /// The meals served from a cooking, by entry id, beside [rows].
  final Map<String, LeftoverMeal> meals;

  @override
  Stream<LeftoverShelves> watchHouseholdLeftovers({required DateTime today}) =>
      Stream.value(LeftoverShelves(rows: rows, meals: meals));

  /// Every `(row, portions)` handed to [setLeftoverPortions].
  final portionWrites = <(Leftover, double)>[];

  /// Every row handed to [freezeLeftover].
  final freezes = <Leftover>[];

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
  Future<LeftoverUndo> freezeLeftover(Leftover left) async {
    freezes.add(left);
    return (changes: ['freeze-${left.id}'], gone: const <String>[]);
  }

  @override
  Future<LeftoverUndo> markLeftoversGone(List<Leftover> lefts) async {
    gone.add(lefts);
    return (changes: const <String>[], gone: [for (final l in lefts) l.id]);
  }

  /// Every undo handed to [undoLeftovers].
  final undone = <LeftoverUndo>[];

  @override
  Future<void> undoLeftovers(LeftoverUndo undo) async => undone.add(undo);

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
