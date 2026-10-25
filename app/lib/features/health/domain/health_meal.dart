/// What this phone's member ate, as Health Connect is told it. Pure Dart.
///
/// Each phone sends only its own member's meals: the planned meals they
/// ticked, at their share, and what they had instead. A meal whose macros do
/// not resolve is not sent and is named, never sent as zeros. What was sent is
/// kept as a content key per record, so [diffHealth] can say exactly what to
/// write and what to take back.
library;

import 'package:meta/meta.dart';

import '../../../core/units/macros.dart';
import '../../../core/week_shape.dart';
import '../../planning/domain/planning.dart';
import '../../planning/domain/week_macros.dart';
import '../../recipes/domain/recipe_macros.dart';

/// Health Connect's meal types. A slot the household named itself is
/// [unknown].
enum HealthMealType { breakfast, lunch, dinner, snack, unknown }

/// The meal type a slot reads as.
HealthMealType mealTypeOf(String slot) => switch (slot.trim().toLowerCase()) {
  'breakfast' => HealthMealType.breakfast,
  'lunch' => HealthMealType.lunch,
  'dinner' => HealthMealType.dinner,
  'snack' || 'snacks' => HealthMealType.snack,
  _ => HealthMealType.unknown,
};

/// One meal, as one Health Connect nutrition record.
@immutable
class HealthMeal {
  const HealthMeal({
    required this.id,
    required this.name,
    required this.day,
    required this.at,
    required this.mealType,
    required this.macros,
  });

  /// The record's own id in Health Connect: the meal and the member, so a
  /// later write replaces it and never adds a second.
  final String id;
  final String name;

  /// The day the meal was planned on: what decides whether it is still in
  /// the window [diffHealth] may take things back from.
  final DateTime day;

  /// When it was eaten.
  final DateTime at;
  final HealthMealType mealType;

  /// This member's share. Fibre only when stated.
  final Macros macros;

  /// Everything that, changed, means the record must be written again.
  String get contentKey => [
    isoDateOf(day),
    name,
    at.toUtc().toIso8601String(),
    mealType.name,
    // The figures exactly as they are: this key only detects a change.
    macros.kcal,
    macros.protein,
    macros.carb,
    macros.fat,
    macros.fiber ?? '',
  ].join('|');

  @override
  String toString() => 'HealthMeal($id, $name, $at)';
}

/// The record id for [memberId]'s share of the meal [entryId].
String healthMealId(String entryId, String memberId) =>
    'ansi:$entryId:$memberId';

/// What [memberId] ate in [week]: every meal to send, and the titles of those
/// that cannot be (their macros do not resolve).
///
/// A ticked planned meal is sent at its tick's time; a substitute at the
/// meal's day and the time it was said (`defaultEatenAt`'s rule, so a late one
/// keeps its day).
({List<HealthMeal> meals, List<String> notSent}) healthMealsIn(
  WeekPlan week, {
  required String memberId,
  required Map<String, Member> membersById,
  required RecipeMacroSummary? Function(String recipeId) summaryFor,
}) {
  final meals = <HealthMeal>[];
  final notSent = <String>[];

  void add(
    PlanEntry eaten, {
    required PlanEntry planned,
    required DateTime at,
  }) {
    final share = sumPlannedMacros(
      [eaten],
      summaryFor: summaryFor,
      lensMemberId: memberId,
      membersById: membersById,
      eatenOnly: true,
    );
    final title = eaten.title ?? deletedTargetLabel(eaten);
    final total = share.total;
    if (total == null || share.excluded.isNotEmpty) {
      notSent.add(title);
      return;
    }
    meals.add(
      HealthMeal(
        id: healthMealId(planned.id, memberId),
        name: title,
        day: planned.dateIn(week.weekStart),
        at: at,
        mealType: mealTypeOf(planned.mealSlot),
        macros: total,
      ),
    );
  }

  for (final entry in week.entries) {
    final day = entry.dateIn(week.weekStart);
    final ticked = entry.eatenAt[memberId];
    if (ticked != null && entry.eatenBy.contains(memberId)) {
      add(entry, planned: entry, at: ticked);
    }
    final had = entry.had[memberId];
    if (had != null) {
      add(
        had,
        planned: entry,
        at: entry.hadAt(memberId, mealDay: day)!,
      );
    }
  }
  return (meals: meals, notSent: notSent);
}

/// The planned day (`YYYY-MM-DD`) a sent record's content key names.
String sentDayOf(String contentKey) => contentKey.split('|').first;

/// What to write and what to take back, given what should be in Health
/// Connect ([wanted]) and what this phone last sent (`id → contentKey`).
///
/// Only meals planned on or after [windowStart] are looked at: an older one
/// has simply left the window, and stays in Health Connect as it was. `keep`
/// is the log to remember afterwards.
({List<HealthMeal> write, List<String> delete, Map<String, String> keep})
diffHealth(
  List<HealthMeal> wanted,
  Map<String, String> sent, {
  required DateTime windowStart,
}) {
  // Calendar dates, compared as ISO strings: a local day and a week start
  // stored as a UTC date must not drift apart by an offset.
  final from = isoDateOf(windowStart);
  bool inWindow(String key) => sentDayOf(key).compareTo(from) >= 0;

  final ids = {for (final m in wanted) m.id};
  return (
    write: [
      for (final m in wanted)
        if (sent[m.id] != m.contentKey) m,
    ],
    delete: [
      for (final e in sent.entries)
        if (!ids.contains(e.key) && inWindow(e.value)) e.key,
    ],
    keep: {for (final m in wanted) m.id: m.contentKey},
  );
}
