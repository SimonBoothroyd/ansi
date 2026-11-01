/// What a cooked batch has left, and until when (plan 0059). Pure Dart.
///
/// A batch — one meal [CookSession] — counts as **cooked** once anybody ticked
/// any meal it covers; the household ticks reliably, so a batch nobody ticked
/// was never cooked and its ingredients are spare food instead (never a
/// leftover, never asked about). A cooked batch's **leftover** is the portions
/// of its meals already behind us that nobody ate, less what a question on Cook
/// has accounted for and less the meals planned from it since. It is good
/// until its **use-by**: the cook day plus the recipe's fridge life, never
/// before the batch's own last meal.
library;

import 'package:meta/meta.dart';

import 'cook_plan.dart';

/// One cooked batch's leftover, on one day.
@immutable
class BatchLeftover {
  const BatchLeftover({
    required this.key,
    required this.recipeId,
    required this.title,
    required this.cookDate,
    required this.useBy,
    required this.portions,
  });

  /// The batch's key: its first covered meal ([CookSession.leftoverKey]), the
  /// same key `batch_leftover` and `plan_entry.leftover_of` name.
  final String key;

  final String recipeId;
  final String title;

  /// The day the batch was cooked.
  final DateTime cookDate;

  /// The last day it is good, inclusive.
  final DateTime useBy;

  /// The portions still left: never zero or less.
  final double portions;

  /// Whether a meal on [day] can still be planned from it: on or after the
  /// cook, and on or before the use-by.
  bool isGoodOn(DateTime day) {
    final d = _dateOnly(day);
    return !d.isBefore(cookDate) && !d.isAfter(useBy);
  }

  /// Whether its use-by is behind [today]: Cook asks what became of it.
  bool isDueOn(DateTime today) => _dateOnly(today).isAfter(useBy);

  @override
  bool operator ==(Object other) =>
      other is BatchLeftover &&
      other.key == key &&
      other.recipeId == recipeId &&
      other.title == title &&
      other.cookDate == cookDate &&
      other.useBy == useBy &&
      other.portions == portions;

  @override
  int get hashCode =>
      Object.hash(key, recipeId, title, cookDate, useBy, portions);

  @override
  String toString() =>
      'BatchLeftover($title, $portions left, good until $useBy)';
}

/// Whether anybody ticked any meal [session] covers: proof it was cooked.
bool wasCooked(CookSession session) =>
    session.covers.any((m) => m.eatenPortions > 1e-9);

/// The date [day] (0..6) of the week beginning [weekStart] names.
DateTime dateOfDay(DateTime weekStart, int day) =>
    DateTime(weekStart.year, weekStart.month, weekStart.day + day);

/// [session]'s use-by in the week beginning [weekStart]: its cook day plus its
/// fridge life, but never before its own last meal (a freezer share can reach
/// past the fridge window). An unknown fridge life is the last meal's day, so
/// such a batch is asked about as soon as its days are over and never offered.
DateTime useByOf(CookSession session, DateTime weekStart) {
  final last = dateOfDay(weekStart, session.lastCoveredDay);
  final keeps = session.keepsForDays;
  if (keeps == null) return last;
  final fridge = dateOfDay(weekStart, session.cookDay + keeps);
  return fridge.isAfter(last) ? fridge : last;
}

/// The cooked batches of [plan] — the week beginning [weekStart] — that still
/// have portions left on [today].
///
/// Only meals on a day before [today] can have been left: today's and later
/// ones are still to be eaten. [answers] are Cook's answers, keyed by batch;
/// only what was binned or eaten comes off (a `kept` answer from before plan
/// 0059 is read as unanswered). [plannedFrom] is the demand of the meals
/// planned from each batch since, keyed the same way.
List<BatchLeftover> batchLeftovers(
  CookPlan plan, {
  required DateTime weekStart,
  required DateTime today,
  Map<String, LeftoverAnswer> answers = const {},
  Map<String, double> plannedFrom = const {},
}) {
  final day = _dateOnly(today);
  return [
    for (final recipe in plan.recipes)
      for (final session in recipe.mealSessions)
        if (_leftoverOf(
              session,
              weekStart: weekStart,
              today: day,
              answers: answers,
              plannedFrom: plannedFrom,
            )
            case final left?)
          left,
  ];
}

BatchLeftover? _leftoverOf(
  CookSession session, {
  required DateTime weekStart,
  required DateTime today,
  required Map<String, LeftoverAnswer> answers,
  required Map<String, double> plannedFrom,
}) {
  final key = session.leftoverKey;
  if (key == null || !wasCooked(session)) return null;
  final uneaten = session.covers
      .where((m) => dateOfDay(weekStart, m.dayOfWeek).isBefore(today))
      .fold<double>(0, (sum, m) => sum + (m.portions - m.eatenPortions));
  final answer = answers[key];
  final accounted =
      (answer?.binned ?? 0) + (answer?.eaten ?? 0) + (plannedFrom[key] ?? 0);
  final left = uneaten - accounted;
  if (left <= 1e-9) return null;
  return BatchLeftover(
    key: key,
    recipeId: session.recipeId,
    title: session.recipeTitle,
    cookDate: dateOfDay(weekStart, session.cookDay),
    useBy: useByOf(session, weekStart),
    portions: left,
  );
}

DateTime _dateOnly(DateTime d) => DateTime(d.year, d.month, d.day);
