import 'package:ansi/core/units/units.dart';
import 'package:ansi/core/week_shape.dart';
import 'package:ansi/features/ask/domain/ask_proposal.dart';
import 'package:ansi/features/ask/domain/ask_tools.dart';
import 'package:ansi/features/ingredients/domain/ingredient.dart';
import 'package:ansi/features/planning/domain/plan_change.dart';
import 'package:ansi/features/planning/domain/planning.dart';
import 'package:flutter_test/flutter_test.dart';

/// Mon 19 Oct 2026 and the week after it.
final _thisWeek = DateTime.utc(2026, 10, 19);
final _nextWeek = DateTime.utc(2026, 10, 26);

const _simon = Member(id: 'm1', displayName: 'Simon');
const _emma = Member(id: 'm2', displayName: 'Emma');

PlanEntry _dinner(String id, int day, String recipe, {List<String>? eaters}) =>
    PlanEntry(
      id: id,
      dayOfWeek: day,
      mealSlot: 'Dinner',
      recipeId: 'r-$recipe',
      recipeTitle: recipe,
      eaterIds: eaters ?? ['m1', 'm2'],
    );

const _yoghurt = Ingredient(
  id: 'i1',
  canonicalName: 'Yoghurt',
  defaultUnit: g,
  status: IngredientStatus.complete,
  densityGPerMl: 1.03,
  allowedUnits: [g, cup],
);

AskPlanContext _context({Map<DateTime, WeekPlan?> weeks = const {}}) =>
    AskPlanContext(
      shape: WeekShape.monday,
      weeks: weeks,
      members: const [_simon, _emma],
      recipeTitles: const {'r-hh': 'Hamburger Helper', 'r-curry': 'Curry'},
      ingredients: const {'i1': _yoghurt},
    );

AskRawChange _change({
  required String op,
  String? entryId,
  String? date,
  String? slot,
  String? recipeId,
  String? ingredientId,
  String? outLabel,
  List<String>? eaters,
  num? quantity,
  String? unit,
}) => {
  'op': op,
  'entry_id': entryId,
  'date': date,
  'slot': slot,
  'recipe_id': recipeId,
  'ingredient_id': ingredientId,
  'out_label': outLabel,
  'eaters': eaters,
  'quantity': quantity,
  'unit': unit,
};

void main() {
  test('"set all dinners next week to Hamburger Helper": one row a day, '
      'replacing what was there', () {
    final next = WeekPlan(
      id: 'w2',
      weekStart: _nextWeek,
      entries: [_dinner('e1', 0, 'Ragù'), _dinner('e2', 3, 'Curry')],
    );
    final proposal = buildPlanProposal([
      _change(op: 'remove', entryId: 'e1'),
      _change(op: 'remove', entryId: 'e2'),
      for (var d = 26; d <= 27; d++)
        _change(
          op: 'add',
          date: '2026-10-$d',
          slot: 'dinner',
          recipeId: 'r-hh',
        ),
      _change(op: 'add', date: '2026-10-29', slot: 'Dinner', recipeId: 'r-hh'),
    ], _context(weeks: {_nextWeek: next}));

    expect(proposal.title, 'Plan 5 changes');
    expect(
      [for (final r in proposal.rows) '${r.when} | ${r.what} | ${r.note}'],
      [
        'Mon 26 Oct · Dinner | Hamburger Helper | replaces Ragù',
        'Tue 27 Oct · Dinner | Hamburger Helper | new',
        'Thu 29 Oct · Dinner | Hamburger Helper | replaces Curry',
      ],
    );
    final add = proposal.changes.whereType<PlanAdd>().first;
    // The slot takes the default's own spelling; eaters default to everyone.
    expect(add.mealSlot, 'Dinner');
    expect(add.eaterIds, ['m1', 'm2']);
    expect(add.weekStart, _nextWeek);
  });

  test('"move Tuesday\'s curry to Thursday" is one row', () {
    final week = WeekPlan(
      id: 'w1',
      weekStart: _thisWeek,
      entries: [_dinner('e1', 1, 'Curry')],
    );
    final proposal = buildPlanProposal([
      _change(op: 'move', entryId: 'e1', date: '2026-10-22'),
    ], _context(weeks: {_thisWeek: week}));
    expect(proposal.rows.single.when, 'Tue 20 Oct · Dinner');
    expect(proposal.rows.single.note, 'moves to Thu 22 Oct · Dinner');
    final move = proposal.changes.single as PlanMove;
    expect(move.dayOfWeek, 3);
    expect(move.mealSlot, 'Dinner');
  });

  test('"I\'m eating out Friday": the eaters change, and a meal left with no '
      'one is removed', () {
    final week = WeekPlan(
      id: 'w1',
      weekStart: _thisWeek,
      entries: [
        _dinner('e1', 4, 'Curry'),
        _dinner('e2', 4, 'Ragù', eaters: ['m1']),
      ],
    );
    final proposal = buildPlanProposal([
      _change(op: 'set_eaters', entryId: 'e1', eaters: ['m2']),
      _change(op: 'set_eaters', entryId: 'e2', eaters: []),
    ], _context(weeks: {_thisWeek: week}));
    expect(
      [for (final r in proposal.rows) r.note],
      ['eaten by Emma (was Simon, Emma)', 'no one left eating it — removed'],
    );
    expect(proposal.changes[1], isA<PlanRemove>());
  });

  test('yoghurt for breakfast states its amount, or says it has none', () {
    final proposal = buildPlanProposal([
      _change(
        op: 'add',
        date: '2026-10-19',
        slot: 'Breakfast',
        ingredientId: 'i1',
        eaters: ['m1'],
        quantity: 170,
        unit: 'g',
      ),
      _change(
        op: 'add',
        date: '2026-10-20',
        slot: 'Breakfast',
        ingredientId: 'i1',
      ),
    ], _context());
    expect(proposal.rows.first.note, 'new · 170 g each · for Simon');
    expect(proposal.rows.last.note, 'new · no amount — set it on the Week');
    final target =
        (proposal.changes.last as PlanAdd).target as PlanIngredientTarget;
    expect(target.quantity, isNull);
  });

  test('a meal eaten out is its words', () {
    final proposal = buildPlanProposal([
      _change(op: 'add', date: '2026-10-23', slot: 'Lunch', outLabel: 'Office'),
    ], _context());
    expect(proposal.rows.single.what, 'Office (eaten out)');
  });

  group('refused, in words the model can act on', () {
    void refuses(List<AskRawChange> changes, String words) => expect(
      () => buildPlanProposal(changes, _context()),
      throwsA(
        isA<AskToolError>().having(
          (e) => e.message,
          'message',
          contains(words),
        ),
      ),
    );

    test('a meal the weeks read do not hold', () {
      refuses([_change(op: 'remove', entryId: 'nope')], 'read the week');
    });
    test('two targets at once', () {
      refuses([
        _change(
          op: 'add',
          date: '2026-10-19',
          slot: 'Dinner',
          recipeId: 'r-hh',
          outLabel: 'x',
        ),
      ], 'exactly one');
    });
    test("a recipe that is not the household's", () {
      refuses([
        _change(op: 'add', date: '2026-10-19', slot: 'Dinner', recipeId: 'r?'),
      ], 'no recipe');
    });
    test('a unit the ingredient does not allow', () {
      refuses([
        _change(
          op: 'add',
          date: '2026-10-19',
          slot: 'Breakfast',
          ingredientId: 'i1',
          quantity: 2,
          unit: 'tbsp',
        ),
      ], 'measured in g, cup');
    });
    test('a date that is not one', () {
      refuses([
        _change(op: 'add', date: 'Friday', slot: 'Dinner', recipeId: 'r-hh'),
      ], 'YYYY-MM-DD');
    });
    test('an eater who is not a member', () {
      refuses([
        _change(
          op: 'add',
          date: '2026-10-19',
          slot: 'Dinner',
          recipeId: 'r-hh',
          eaters: ['Simon'],
        ),
      ], 'not a member id');
    });
  });

  test('a top-up needs an amount; a free-text item does not', () {
    expect(
      () => buildTopUpProposal(
        weekStart: _thisWeek,
        shape: WeekShape.monday,
        ingredient: _yoghurt,
      ),
      throwsA(isA<AskToolError>()),
    );
    final topUp = buildTopUpProposal(
      weekStart: _thisWeek,
      shape: WeekShape.monday,
      ingredient: _yoghurt,
      quantity: 2,
      unit: 'cup',
    );
    expect(topUp.rows.single.note, '+ 2 cup');
    expect(topUp.title, 'Add to the list for the week of Mon 19 Oct');
    final item = buildTopUpProposal(
      weekStart: _thisWeek,
      shape: WeekShape.monday,
      item: ' paper towels ',
    );
    expect(item.item, 'paper towels');
  });

  test('copy last week lists every meal at its new date', () {
    final last = WeekPlan(
      id: 'w0',
      weekStart: DateTime.utc(2026, 10, 12),
      entries: [_dinner('e1', 2, 'Curry')],
    );
    final copy = buildCopyWeekProposal(
      shape: WeekShape.monday,
      weekStart: _thisWeek,
      source: last,
      target: null,
    );
    expect(copy.title, 'Copy 1 meal from the week of 12 Oct');
    expect(copy.rows.single.when, 'Wed 21 Oct · Dinner');
    expect(
      () => buildCopyWeekProposal(
        shape: WeekShape.monday,
        weekStart: _thisWeek,
        source: null,
        target: null,
      ),
      throwsA(isA<AskToolError>()),
    );
  });
}
