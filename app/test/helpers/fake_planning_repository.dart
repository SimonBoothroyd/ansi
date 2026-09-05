/// A no-op [PlanningRepository] for widget tests that need the roster (and,
/// since plan 0027, its portion factors) but not the week.
///
/// Subclass and override what the test exercises. The roster is what
/// `members()` and `watchMembers()` hand out; `setPortionFactor` records the
/// write and re-emits the roster with the new factor, so a sheet that reads
/// `membersProvider` sees its own write land the way it does on the phone.
library;

import 'dart:async';

import 'package:ansi/core/units/units.dart';
import 'package:ansi/features/planning/domain/planning.dart';
import 'package:ansi/features/planning/domain/planning_repository.dart';

class FakePlanningRepository implements PlanningRepository {
  FakePlanningRepository([List<Member> roster = const []])
    : roster = [...roster];

  List<Member> roster;

  /// Every `(memberId, factor)` handed to [setPortionFactor], in order.
  final factorWrites = <(String, double)>[];

  final _roster = StreamController<List<Member>>.broadcast();

  @override
  Stream<WeekPlan?> watchWeek(DateTime weekStart) => Stream.value(null);

  @override
  Future<WeekPlan?> mostRecentWeekBefore(DateTime weekStart) async => null;

  @override
  Stream<List<Member>> watchMembers() async* {
    yield roster;
    yield* _roster.stream;
  }

  @override
  Future<void> setPortionFactor(String memberId, double factor) async {
    factorWrites.add((memberId, factor));
    roster = [
      for (final m in roster)
        if (m.id == memberId) m.copyWith(portionFactor: factor) else m,
    ];
    _roster.add(roster);
  }

  @override
  Stream<Map<String, DateTime>> watchLastPlanned() => Stream.value(const {});

  /// Every ingredient meal added through [addIngredientEntry], in order — the
  /// snack door's writes, for tests that assert what the picker wrote.
  final ingredientEntries =
      <
        ({
          int dayOfWeek,
          String mealSlot,
          String ingredientId,
          double? quantity,
          Unit? unit,
          String? measureId,
          List<String> eaterIds,
        })
      >[];

  @override
  Future<String> addEntry({
    required DateTime weekStart,
    required int dayOfWeek,
    required String mealSlot,
    required String recipeId,
    required List<String> eaterIds,
    int? portions,
  }) async => 'e';

  @override
  Future<String> addIngredientEntry({
    required DateTime weekStart,
    required int dayOfWeek,
    required String mealSlot,
    required String ingredientId,
    required List<String> eaterIds,
    double? quantity,
    Unit? unit,
    String? measureId,
    int? portions,
  }) async {
    ingredientEntries.add((
      dayOfWeek: dayOfWeek,
      mealSlot: mealSlot,
      ingredientId: ingredientId,
      quantity: quantity,
      unit: unit,
      measureId: measureId,
      eaterIds: eaterIds,
    ));
    return 'i';
  }

  @override
  Future<void> setEaters(String entryId, List<String> eaterIds) async {}

  @override
  Future<void> setPortions(String entryId, int? portions) async {}

  @override
  Future<void> removeEntry(String entryId) async {}

  @override
  Future<int> copyLastWeek(DateTime weekStart) async => 0;
}
