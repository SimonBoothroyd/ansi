/// What Ansi's week, cook and shop tools answer. Pure Dart.
///
/// The same rule as `ask_tools.dart`: every date, weekday and count the model
/// may repeat is written here — dates through the household's [WeekShape],
/// portions through `formatPortions`, list totals by the Shop screen's own
/// formatter (injected, as it lives with the screen). The model never works
/// out which date "Thursday" is.
library;

import 'dart:convert';

import '../../../core/search/search_rank.dart';
import '../../../core/units/portions.dart';
import '../../../core/week_shape.dart';
import '../../cook_plan/domain/cook_plan.dart';
import '../../ingredients/domain/allowed_units.dart';
import '../../ingredients/domain/ingredient.dart';
import '../../planning/domain/planning.dart';
import '../../shopping/domain/shopping.dart';
import 'ask_proposal.dart';
import 'ask_tools.dart';

/// The member this phone is signed in as: the one whose name onboarding took
/// from the account's own name, or from its email before the `@`. Null when
/// no member, or more than one, answers to it — then Ansi asks who "I" is.
String? askMe(List<Member> members, {String? fullName, String? email}) {
  final said = {
    if (fullName != null && fullName.trim().isNotEmpty)
      fullName.trim().toLowerCase(),
    if (email != null && email.contains('@'))
      email.split('@').first.trim().toLowerCase(),
  };
  if (said.isEmpty) return null;
  final hits = [
    for (final m in members)
      if (said.contains(m.displayName.trim().toLowerCase())) m.id,
  ];
  return hits.length == 1 ? hits.single : null;
}

/// The household, as every week result names it.
List<Map<String, Object?>> askMembers(List<Member> members, String? me) => [
  for (final m in members)
    {'id': m.id, 'name': m.displayName, if (m.id == me) 'you': true},
];

/// `week`: the meals of the week beginning [weekStart], each day dated.
/// [day] narrows to one date in it, [slot] to one slot.
String weekResult(
  WeekPlan? plan, {
  required DateTime weekStart,
  required WeekShape shape,
  required List<Member> members,
  required String? me,
  DateTime? day,
  String? slot,
}) {
  final byId = {for (final m in members) m.id: m};
  final wanted = slot?.trim().toLowerCase();
  final days = [
    for (var offset = 0; offset < 7; offset++)
      if (day == null || shape.dateFor(weekStart, offset) == day)
        {
          'date': isoDateOf(shape.dateFor(weekStart, offset)),
          'day': shape.labelFull(offset),
          'meals': [
            for (final e in plan?.entriesForDay(offset) ?? const <PlanEntry>[])
              if (wanted == null ||
                  wanted.isEmpty ||
                  e.mealSlot.toLowerCase() == wanted)
                {
                  'id': e.id,
                  'slot': e.mealSlot,
                  'kind': e.kind.name,
                  'name': e.title ?? deletedTargetLabel(e),
                  if (e.kind == PlanEntryKind.recipe) 'recipe_id': e.recipeId,
                  'eaters': [
                    for (final id in e.eaterIds)
                      byId[id]?.displayName ?? 'someone',
                  ],
                  'eater_ids': e.eaterIds,
                  'portions': formatPortions(demandPortions(e, byId)),
                },
          ],
        },
  ];
  return jsonEncode({
    'week_of': isoDateOf(weekStart),
    'days': days,
    'members': askMembers(members, me),
  });
}

/// `cook_sessions`: the derived batches of the week beginning [weekStart],
/// on their cook days; [day] narrows to the batches cooked that date.
String cookSessionsResult(
  CookPlan plan, {
  required DateTime weekStart,
  required WeekShape shape,
  DateTime? day,
}) {
  String dated(int offset) =>
      askDayLabel(shape, shape.dateFor(weekStart, offset));
  final sessions = [
    for (final r in plan.recipes)
      for (final s in r.sessions) s,
  ]..sort((a, b) => a.cookDay.compareTo(b.cookDay));
  return jsonEncode({
    'week_of': isoDateOf(weekStart),
    'sessions': [
      for (final s in sessions)
        if (day == null || shape.dateFor(weekStart, s.cookDay) == day)
          {
            'cook_on': dated(s.cookDay),
            'recipe': s.recipeTitle,
            'recipe_id': s.recipeId,
            if (s.isComponent)
              'batches': formatFraction(s.batchesToCook!)
            else
              'portions': formatPortions(s.totalPortions),
            if (s.isComponent)
              'for': s.demandedBy
            else
              'eaten': [
                for (final m in s.covers) '${dated(m.dayOfWeek)} ${m.mealSlot}',
              ],
            if (s.hasFreezerRescue)
              'frozen_for': [for (final d in s.frozenDays) dated(d)],
          },
    ],
    if (plan.gaps.isNotEmpty)
      'cannot_work_out': [for (final g in plan.gaps) g.title],
  });
}

/// `shopping`: the list for the week beginning [weekStart]. With
/// [ingredient], the rows whose name it hits, each with the meals that ask
/// for it; otherwise what is left to buy by aisle and how much is ticked.
/// [total] is the Shop screen's own total for a row.
String shoppingResult(
  ShoppingList list, {
  required DateTime weekStart,
  required String Function(ShoppingItem item) total,
  String? ingredient,
}) {
  final query = ingredient?.trim() ?? '';
  Map<String, Object?> row(ShoppingItem i, {bool why = false}) => {
    'name': i.name,
    'amount': total(i),
    if (i.checked) 'ticked': true,
    if (why)
      'for': [
        for (final c in i.contributions)
          if (c.source == ContributionSource.manual)
            'added by hand'
          else
            c.label,
      ],
  };
  if (query.isNotEmpty) {
    final hits = [
      for (final g in list.groups)
        for (final i in g.items)
          if (recipeTitleHit(i.name, query) != null) i,
    ];
    return jsonEncode({
      'week_of': isoDateOf(weekStart),
      'asked': query,
      'rows': [for (final i in hits) row(i, why: true)],
      if (hits.isEmpty) 'note': 'nothing on the list is called "$query"',
    });
  }
  return jsonEncode({
    'week_of': isoDateOf(weekStart),
    'left_to_buy': [
      for (final g in list.openGroups)
        {
          'aisle': g.label,
          'rows': [for (final i in g.items) row(i)],
        },
    ],
    'ticked': list.basket.length,
  });
}

/// `find_ingredient`: up to [kAskFindLimit] of the household's ingredients
/// for [query], best first, each with the units an amount may use.
String findIngredientResult(
  ({List<Ingredient> rows, bool guessed}) found,
  String query,
) => jsonEncode({
  'query': query,
  'matches': [
    for (final i in found.rows.take(kAskFindLimit))
      {
        'id': i.id,
        'name': i.canonicalName,
        'units': [for (final u in allowedUnitsFor(i)) u.id],
      },
  ],
  if (found.guessed) 'note': 'no exact spelling; these are guesses',
  if (found.rows.isEmpty) 'note': 'no ingredient matches',
});
