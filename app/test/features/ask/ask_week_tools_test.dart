import 'dart:convert';

import 'package:ansi/core/units/units.dart';
import 'package:ansi/core/week_shape.dart';
import 'package:ansi/features/ask/domain/ask_proposal.dart';
import 'package:ansi/features/ask/domain/ask_screen.dart';
import 'package:ansi/features/ask/domain/ask_thread.dart';
import 'package:ansi/features/ask/domain/ask_tool_runner.dart';
import 'package:ansi/features/ask/domain/ask_week_tools.dart';
import 'package:ansi/features/cook_plan/domain/cook_plan.dart';
import 'package:ansi/features/planning/domain/plan_change.dart';
import 'package:ansi/features/planning/domain/planning.dart';
import 'package:ansi/features/recipes/domain/line_override.dart';
import 'package:ansi/features/shopping/domain/shopping.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/fake_ask.dart';

final _thisWeek = DateTime.utc(2026, 10, 19);

const _simon = Member(id: 'm1', displayName: 'Simon');
const _emma = Member(id: 'm2', displayName: 'Emma', portionFactor: 0.75);

final _week = WeekPlan(
  id: 'w1',
  weekStart: _thisWeek,
  entries: const [
    PlanEntry(
      id: 'e1',
      dayOfWeek: 2,
      mealSlot: 'Dinner',
      recipeId: 'r1',
      recipeTitle: 'Ragù',
      eaterIds: ['m1', 'm2'],
    ),
    PlanEntry(
      id: 'e2',
      dayOfWeek: 2,
      mealSlot: 'Lunch',
      label: 'Office',
      eaterIds: ['m1'],
    ),
  ],
);

Map<String, Object?> _json(String s) => jsonDecode(s) as Map<String, Object?>;

void main() {
  group('who "I" is', () {
    test('the member named as the account is', () {
      expect(askMe(const [_simon, _emma], fullName: 'Emma'), 'm2');
      expect(askMe(const [_simon, _emma], email: 'simon@example.com'), 'm1');
    });
    test('nobody, when the name answers to no one or to two', () {
      expect(askMe(const [_simon, _emma], fullName: 'Sam'), isNull);
      expect(
        askMe(const [
          _simon,
          Member(id: 'm3', displayName: 'simon'),
        ], fullName: 'Simon'),
        isNull,
      );
      expect(askMe(const [_simon]), isNull);
    });
  });

  test('`week` dates every day and counts portions through the factors', () {
    final json = _json(
      weekResult(
        _week,
        weekStart: _thisWeek,
        shape: WeekShape.monday,
        members: const [_simon, _emma],
        me: 'm1',
        day: DateTime.utc(2026, 10, 21),
      ),
    );
    final day = (json['days']! as List).single as Map;
    expect(day['date'], '2026-10-21');
    expect(day['day'], 'Wednesday');
    final meals = day['meals']! as List;
    // Ordered by slot: lunch, then dinner.
    expect((meals.first as Map)['kind'], 'out');
    final dinner = meals.last as Map;
    expect(dinner['name'], 'Ragù');
    expect(dinner['eaters'], ['Simon', 'Emma']);
    expect(dinner['portions'], '1¾ portions');
    expect(json['members'], [
      {'id': 'm1', 'name': 'Simon', 'you': true},
      {'id': 'm2', 'name': 'Emma'},
    ]);
  });

  test('`week` for one recipe counts its meals and names them', () {
    final json = _json(
      weekResult(
        _week,
        weekStart: _thisWeek,
        shape: WeekShape.monday,
        members: const [_simon, _emma],
        me: null,
        onlyRecipe: 'r1',
      ),
    );
    expect(json['times_planned'], 1);
    expect(json['planned_on'], ['Wed 21 Oct Dinner']);
    final meals = [
      for (final d in json['days']! as List) ...(d as Map)['meals']! as List,
    ];
    // The meal out the same day is not this recipe's.
    expect(meals, hasLength(1));
  });

  test('`week` on a Sunday household starts on Sunday', () {
    final json = _json(
      weekResult(
        null,
        weekStart: DateTime.utc(2026, 10, 18),
        shape: WeekShape.sunday,
        members: const [],
        me: null,
      ),
    );
    final first = (json['days']! as List).first as Map;
    expect(first['date'], '2026-10-18');
    expect(first['day'], 'Sunday');
  });

  test('`cook_sessions` names each batch by its cook day', () {
    const plan = CookPlan(
      recipes: [
        RecipeCookPlan(
          recipeId: 'r1',
          title: 'Ragù',
          servingsBase: 4,
          sessions: [
            CookSession(
              recipeId: 'r1',
              recipeTitle: 'Ragù',
              servingsBase: 4,
              cookDay: 6,
              covers: [
                CoveredMeal(dayOfWeek: 6, mealSlot: 'Dinner', portions: 2),
              ],
            ),
          ],
        ),
      ],
    );
    final json = _json(
      cookSessionsResult(
        plan,
        weekStart: _thisWeek,
        shape: WeekShape.monday,
        day: DateTime.utc(2026, 10, 25),
      ),
    );
    final s = (json['sessions']! as List).single as Map;
    expect(s['cook_on'], 'Sun 25 Oct');
    expect(s['portions'], '2 portions');
    expect(s['eaten'], ['Sun 25 Oct Dinner']);
  });

  group('`shopping`', () {
    final list = ShoppingList(
      groups: [
        ShoppingGroup(
          label: 'Pantry',
          items: [
            ShoppingItem(
              name: 'Tamari',
              ingredientId: 'i1',
              totals: [Quantity(3, tbsp)],
              contributions: const [
                ShoppingContribution(
                  source: ContributionSource.cookSession,
                  label: 'Ragù · cook Wed',
                ),
              ],
            ),
            const ShoppingItem(name: 'Rice', ingredientId: 'i2', checked: true),
          ],
        ),
      ],
    );
    String total(ShoppingItem i) => i.totals.isEmpty ? '—' : '3 tbsp';

    test('"do we need tamari?" names the meals that ask for it', () {
      final json = _json(
        shoppingResult(
          list,
          weekStart: _thisWeek,
          total: total,
          ingredient: 'tamari',
        ),
      );
      final row = (json['rows']! as List).single as Map;
      expect(row['amount'], '3 tbsp');
      expect(row['for'], ['Ragù · cook Wed']);
    });

    test('"what\'s left to buy?" is the open rows by aisle', () {
      final json = _json(
        shoppingResult(list, weekStart: _thisWeek, total: total),
      );
      final aisle = (json['left_to_buy']! as List).single as Map;
      expect(aisle['aisle'], 'Pantry');
      expect(
        [for (final r in aisle['rows']! as List) (r as Map)['name']],
        ['Tamari'],
      );
      expect(json['ticked'], 1);
    });
  });

  group('the runner', () {
    AskToolRunner runner(FakeAskHousehold household, AskScreen screen) =>
        AskToolRunner(
          screen: () => screen,
          loadRecipe: (_) async => null,
          listRecipes: () async => [(id: 'r1', title: 'Ragù')],
          weekOf: (_, _) async =>
              (overrides: const <LineOverride>[], portions: null),
          setServings: (_, _) {},
          startTimer:
              (
                _, {
                required step,
                required ordinal,
                required low,
                required high,
              }) {},
          openRecipe: (_) {},
          household: household.household,
        );

    AskToolCall call(String name, Map<String, Object?> input) =>
        AskToolCall(id: 't1', name: name, input: input);

    test('a week with no date is the one on screen', () async {
      final household = FakeAskHousehold(
        weeks: {_thisWeek: _week},
        members: const [_simon, _emma],
      );
      final out = await runner(
        household,
        AskWeekScreen(tab: AskWeekTab.week, weekStart: _thisWeek),
      ).run(call('week', {'week_of': null, 'date': null, 'slot': null}));
      expect(out.isError, isFalse);
      expect(_json(out.content)['week_of'], '2026-10-19');
    });

    test('a proposal waits on the card, and a confirmed one is listed as '
        'done', () async {
      final household = FakeAskHousehold(
        weeks: {_thisWeek: _week},
        members: const [_simon, _emma],
        decide: (_) => AskDecision.confirmed,
      );
      final out = await runner(household, const AskNoScreen()).run(
        call('propose_plan_changes', {
          'changes': [
            {
              'op': 'move',
              'entry_id': 'e1',
              'date': '2026-10-22',
              'slot': null,
              'recipe_id': null,
              'ingredient_id': null,
              'out_label': null,
              'eaters': null,
              'quantity': null,
              'unit': null,
            },
          ],
        }),
      );
      // The meal was found in this week, read for the proposal.
      final card = household.cards.single as AskPlanProposal;
      expect(card.changes.single, isA<PlanMove>());
      expect(_json(out.content)['outcome'], 'confirmed');
      expect(out.done, 'Plan 1 change');
    });

    test('a cancelled card writes nothing and lists nothing', () async {
      final household = FakeAskHousehold(members: const [_simon]);
      final out = await runner(household, const AskNoScreen()).run(
        call('propose_top_up', {
          'week_of': null,
          'ingredient_id': null,
          'quantity': null,
          'unit': null,
          'item': 'paper towels',
        }),
      );
      expect(_json(out.content)['outcome'], 'cancelled');
      expect(out.done, isNull);
      // This week, as the date is today's.
      expect((household.cards.single as AskTopUpProposal).weekStart, _thisWeek);
    });

    test('a bad change is an error before any card is drawn', () async {
      final household = FakeAskHousehold(members: const [_simon]);
      final out = await runner(
        household,
        const AskNoScreen(),
      ).run(call('propose_plan_changes', {'changes': <Object?>[]}));
      expect(out.isError, isTrue);
      expect(household.cards, isEmpty);
    });
  });

  group('figures default to the person asking', () {
    AskToolRunner runner(FakeAskHousehold household, AskScreen screen) =>
        AskToolRunner(
          screen: () => screen,
          loadRecipe: (_) async => null,
          listRecipes: () async => const [],
          weekOf: (_, _) async =>
              (overrides: const <LineOverride>[], portions: null),
          setServings: (_, _) {},
          startTimer:
              (
                _, {
                required step,
                required ordinal,
                required low,
                required high,
              }) {},
          openRecipe: (_) {},
          household: household.household,
        );

    AskToolCall call(String name, Map<String, Object?> input) =>
        AskToolCall(id: 't1', name: name, input: input);

    test("a day with no one named is the signed-in member's", () async {
      final household = FakeAskHousehold(
        members: const [_simon, _emma],
        me: 'm1',
      );
      await runner(
        household,
        const AskNoScreen(),
      ).run(call('nutrition', {'date': '2026-10-21'}));
      final scope = household.figures.single as AskPlanFigures;
      expect(scope.memberId, 'm1');
      expect(scope.forWhom, 'Simon');
      expect(scope.weekStart, _thisWeek);
    });

    test('"we" is everyone; a name wins; nobody known is said so', () async {
      final household = FakeAskHousehold(members: const [_simon, _emma]);
      final r = runner(household, const AskNoScreen());
      await r.run(call('cost', {'member_id': 'everyone'}));
      await r.run(call('nutrition', {'member_id': 'm2'}));
      await r.run(call('nutrition', <String, Object?>{}));
      final scopes = household.figures.cast<AskPlanFigures>();
      expect(scopes[0].memberId, isNull);
      expect(scopes[0].forWhom, 'everyone');
      expect(scopes[1].forWhom, 'Emma');
      expect(scopes[2].forWhom, startsWith('everyone (who is asking'));
      final bad = await r.run(call('nutrition', {'member_id': 'Simon'}));
      expect(bad.isError, isTrue);
    });

    test('a recipe on screen defaults to the stepper and its week', () async {
      final household = FakeAskHousehold();
      await runner(
        household,
        const AskRecipeScreen(
          recipeId: 'r1',
          title: 'Ragù',
          servings: 6,
          servingsBase: 4,
          weekKey: '2026-10-21',
        ),
      ).run(call('cost', {'recipe_id': 'r1'}));
      final scope = household.figures.single as AskRecipeFigures;
      expect(scope.servings, 6);
      expect(scope.weekStart, _thisWeek);
    });

    test("the trip is the Shop's estimate for the week", () async {
      final household = FakeAskHousehold();
      final out = await runner(
        household,
        AskWeekScreen(tab: AskWeekTab.shop, weekStart: _thisWeek),
      ).run(call('cost', {'trip': true}));
      expect(out.content, 'cost');
      expect((household.figures.single as AskTripFigures).weekStart, _thisWeek);
    });
  });
}
