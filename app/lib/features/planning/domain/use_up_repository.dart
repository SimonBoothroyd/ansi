/// The facts *Use up* reads about last week's shop. Pure Dart.
library;

import 'use_up.dart';

/// What the week before a planned one left spare, and what every recipe in
/// the Library would use.
typedef UseUpFacts = ({List<SpareFood> spare, List<RecipeUse> recipes});

// One read, but an interface still: tests stand in a fake for the database.
// ignore: one_member_abstracts
abstract interface class UseUpRepository {
  /// The spare food the week before [weekStart] left on [today] — never older
  /// — and every live recipe's use of the vocabulary, per batch. One read.
  Future<UseUpFacts> lastWeekFor(DateTime weekStart, {required DateTime today});
}
