// The pumped ProviderScope IS the root scope of each test's tree (the same
// pattern connecting_view_test documents).
// ignore_for_file: scoped_providers_should_specify_dependencies

import 'package:ansi/core/theme/ansi_theme.dart';
import 'package:ansi/core/units/macros.dart';
import 'package:ansi/core/units/units.dart';
import 'package:ansi/core/week_shape.dart';
import 'package:ansi/features/account/data/household_providers.dart';
import 'package:ansi/features/books/data/book_providers.dart';
import 'package:ansi/features/books/domain/book.dart';
import 'package:ansi/features/cook_plan/data/cook_plan_providers.dart';
import 'package:ansi/features/cook_plan/domain/leftovers.dart';
import 'package:ansi/features/ingredients/data/ingredient_providers.dart';
import 'package:ansi/features/ingredients/domain/ingredient.dart';
import 'package:ansi/features/ingredients/domain/ingredient_repository.dart';
import 'package:ansi/features/planning/data/planning_providers.dart';
import 'package:ansi/features/planning/domain/planning.dart';
import 'package:ansi/features/planning/domain/use_up.dart';
import 'package:ansi/features/planning/domain/use_up_repository.dart';
import 'package:ansi/features/planning/presentation/recipe_picker_sheet.dart';
import 'package:ansi/features/planning/presentation/use_up_block.dart';
import 'package:ansi/features/planning/presentation/week_view_models.dart';
import 'package:ansi/features/recipes/data/recipe_providers.dart';
import 'package:ansi/features/recipes/domain/recipe.dart';
import 'package:ansi/features/recipes/domain/recipe_macros.dart';
import 'package:ansi/shared/incomplete_macros.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:forui/forui.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

import '../../helpers/fake_book_repository.dart';
import '../../helpers/fake_cook_plan_repository.dart';
import '../../helpers/fake_ingredient_repository.dart';
import '../../helpers/fake_leftover_repository.dart';
import '../../helpers/fake_planning_repository.dart';
import '../../helpers/fake_recipe_repository.dart';
import '../../helpers/forui_semantics.dart';

/// The picker's read models, canned: two recipes — a favorite with complete
/// per-serving macros planned 3 days ago, and an unplanned one whose macros
/// are honestly incomplete (one stub line).
const _curry = RecipeSummary(
  id: 'r1',
  title: 'Weeknight Chicken Curry',
  servingsBase: 4,
  keepsForDays: 4,
  freezable: true,
  favorite: true,
  macros: RecipeMacroSummary(
    perServing: Macros(kcal: 520.2, protein: 31.4, carb: 40, fat: 18),
  ),
);
const _salad = RecipeSummary(
  id: 'r2',
  title: 'Halloumi Salad',
  servingsBase: 2,
  macros: RecipeMacroSummary(stubLines: 1),
);
const _bare = RecipeSummary(
  id: 'r3',
  title: 'Bare Idea',
  servingsBase: 4,
  macros: RecipeMacroSummary(noLines: true),
);

/// The rows print recency, so the planner remembers when `r1` was last eaten.
class _FakePlanningRepo extends FakePlanningRepository {
  _FakePlanningRepo([this.week])
    : super(const [
        Member(id: 'm1', displayName: 'Ada'),
        Member(id: 'm2', displayName: 'Jun'),
      ]);

  /// The week on screen, whatever week is asked for.
  final WeekPlan? week;

  @override
  Stream<WeekPlan?> watchWeek(DateTime weekStart) => Stream.value(week);

  @override
  Stream<Map<String, DateTime>> watchLastPlanned() =>
      Stream.value({'r1': DateTime.now().subtract(const Duration(days: 3))});
}

class _FakeBookRepo extends FakeBookRepository {
  const _FakeBookRepo() : super(const [Book(id: 'b1', name: 'Our Cookbook')]);
}

/// Last week's spare food, canned.
class _FakeUseUp implements UseUpRepository {
  const _FakeUseUp(this.facts);

  final UseUpFacts facts;

  @override
  Future<UseUpFacts> lastWeekFor(
    DateTime weekStart, {
    required DateTime today,
  }) async => facts;
}

/// The one door's second corpus (step 8.14 / C-D1): the household vocabulary,
/// searched by the same call the editor's line picker makes.
const _bar = Ingredient(
  id: 'i1',
  canonicalName: 'Protein bar',
  defaultUnit: g,
  status: IngredientStatus.complete,
  macros: Macros(kcal: 350, protein: 33, carb: 30, fat: 11),
);

class _FakeVocab extends ReadOnlyIngredientRepo {
  const _FakeVocab();

  @override
  Future<IngredientMatches> search(String query, {int limit = 30}) async =>
      query.toLowerCase().startsWith('prot')
      ? (rows: <Ingredient>[_bar], guessed: false)
      : (rows: const <Ingredient>[], guessed: false);
}

/// A host whose button opens the picker sheet for Wednesday dinner. With
/// [weekStart] it plans into that week, where the fridge and freezer
/// [leftovers] and a clock at [now] decide what *Leftovers* offers.
Widget _host({
  List<RecipeSummary> recipes = const [_curry, _salad],
  void Function(PickedMeal?)? onPicked,
  bool instead = false,
  DateTime? weekStart,
  List<Leftover> leftovers = const [],
  List<Leftover> pots = const [],
  DateTime? now,
  UseUpFacts spare = (spare: const [], recipes: const []),
  WeekPlan? week,
}) => ProviderScope(
  overrides: [
    useUpRepositoryProvider.overrideWithValue(_FakeUseUp(spare)),
    cookPlanRepositoryProvider.overrideWithValue(FakeCookPlanRepository()),
    leftoverRepositoryProvider.overrideWithValue(
      FakeLeftoverRepository(leftovers, const {}, pots),
    ),
    weekShapeProvider.overrideWithValue(WeekShape.monday),
    if (now != null) clockProvider.overrideWithValue(() => now),
    recipeRepositoryProvider.overrideWithValue(
      FakeRecipeRepository(summaries: recipes),
    ),
    planningRepositoryProvider.overrideWithValue(_FakePlanningRepo(week)),
    bookRepositoryProvider.overrideWithValue(const _FakeBookRepo()),
    ingredientRepositoryProvider.overrideWithValue(const _FakeVocab()),
  ],
  child: MaterialApp(
    home: FTheme(
      data: ansiThemeData(),
      child: FScaffold(
        child: Builder(
          builder: (context) => Center(
            child: GestureDetector(
              onTap: () async {
                final picked = await showRecipePickerSheet(
                  context,
                  dayOfWeek: 2,
                  slot: 'Dinner',
                  instead: instead,
                  weekStart: weekStart,
                );
                onPicked?.call(picked);
              },
              child: const Text('open'),
            ),
          ),
        ),
      ),
    ),
  ),
);

Future<void> _open(
  WidgetTester tester, {
  List<RecipeSummary> recipes = const [_curry, _salad],
}) async {
  await tester.pumpWidget(_host(recipes: recipes));
  await tester.tap(find.text('open'));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('Already this week names every day the dish is planned', (
    tester,
  ) async {
    PlanEntry curry(String id, int day) => PlanEntry(
      id: id,
      dayOfWeek: day,
      mealSlot: 'Dinner',
      recipeId: 'r1',
      recipeTitle: 'Weeknight Chicken Curry',
      eaterIds: const ['m1'],
    );
    await tester.pumpWidget(
      _host(
        week: WeekPlan(
          id: 'w',
          weekStart: DateTime(2026, 8, 24),
          entries: [curry('sat', 5), curry('fri', 4), curry('sat2', 5)],
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    expect(find.text('Already this week'), findsOneWidget);
    expect(find.text('Fri + Sat'), findsOneWidget);
  });

  testWidgets('rows are information-honest: recency, macros, incomplete', (
    tester,
  ) async {
    await _open(tester);

    expect(find.text('Add a meal'), findsOneWidget);
    expect(find.textContaining('Wednesday, Dinner'), findsOneWidget);
    // The complete recipe: per-serving macros + recency; honest rounding.
    expect(find.textContaining('serves 4 · ~520 kcal · 31P'), findsOneWidget);
    expect(find.text('3d ago'), findsOneWidget);
    // The incomplete one: the badge and the reason — never zeros.
    expect(find.text('incomplete'), findsOneWidget);
    expect(find.textContaining(incompleteNote(_salad.macros!)), findsOneWidget);
    expect(find.textContaining('~0 kcal'), findsNothing);
    // The eating footer names the household.
    expect(find.textContaining('Eating: '), findsOneWidget);
    expect(find.textContaining('Ada & Jun'), findsOneWidget);
  });

  testWidgets('the picker row prints the bare-count reason in the shared words '
      '— the same sentence the panel and the confirm sheet '
      'render', (tester) async {
    const potatoes = RecipeSummary(
      id: 'r4',
      title: 'Roast Potatoes',
      servingsBase: 2,
      macros: RecipeMacroSummary(countLinesWithoutMeasure: 2),
    );
    await _open(tester, recipes: const [potatoes]);

    expect(find.text('incomplete'), findsOneWidget);
    expect(
      find.textContaining(incompleteNote(potatoes.macros!)),
      findsOneWidget,
    );
    expect(find.textContaining('unconvertible'), findsNothing);
  });

  testWidgets('a line-less recipe reads "no ingredients yet", never ~0 kcal', (
    tester,
  ) async {
    await _open(tester, recipes: const [_bare]);

    expect(find.text('incomplete'), findsOneWidget);
    expect(find.textContaining(incompleteNote(_bare.macros!)), findsOneWidget);
    expect(find.textContaining('kcal'), findsNothing);
  });

  testWidgets('Recent orders by last-planned, created order as fallback', (
    tester,
  ) async {
    // Incoming list order is created_at DESC (salad newer), but the rows
    // display last-planned recency — so the planned curry must lead, and
    // the never-planned salad follows in its created position (M11).
    await _open(tester, recipes: const [_salad, _curry]);

    final curryY = tester.getTopLeft(find.text('Weeknight Chicken Curry')).dy;
    final saladY = tester.getTopLeft(find.text('Halloumi Salad')).dy;
    expect(curryY, lessThan(saladY));
  });

  testWidgets('search matches word boundaries via the shared normalizer', (
    tester,
  ) async {
    filterForuiSemanticsAssertions();

    await _open(tester);

    await tester.enterText(find.byType(EditableText).first, 'chicken');
    await tester.pumpAndSettle();
    expect(find.text('Weeknight Chicken Curry'), findsOneWidget);
    expect(find.text('Halloumi Salad'), findsNothing);

    // Mid-word fragments never match (deterministic search, ADR-0004).
    await tester.enterText(find.byType(EditableText).first, 'hick');
    await tester.pumpAndSettle();
    expect(find.text('Weeknight Chicken Curry'), findsNothing);
  });

  testWidgets('the Favorites tab shows only starred recipes', (tester) async {
    await _open(tester);

    expect(find.text('Halloumi Salad'), findsOneWidget);
    await tester.tap(find.text('Favorites'));
    await tester.pumpAndSettle();
    expect(find.text('Weeknight Chicken Curry'), findsOneWidget);
    expect(find.text('Halloumi Salad'), findsNothing);
  });

  testWidgets('an empty Favorites tab explains the affordance', (tester) async {
    await _open(tester, recipes: const [_salad]); // nothing starred
    await tester.tap(find.text('Favorites'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Star a recipe'), findsOneWidget);
  });

  // --- A bare shelf and a search that missed are different answers ----------
  //
  // The picker has a third answer for typed words (a meal eaten out), so an
  // empty list under a query is no longer "you own no recipes" — it is "these
  // words hit nothing here". The two states must not share a sentence.

  group('an empty list', () {
    testWidgets('points at the door that fills the shelf when NOTHING is '
        'typed', (tester) async {
      await _open(tester, recipes: const []);

      expect(find.text('No recipes yet'), findsOneWidget);
    });

    testWidgets('says the words back when a query matched no recipe', (
      tester,
    ) async {
      filterForuiSemanticsAssertions();

      await _open(tester);
      await tester.enterText(find.byType(EditableText).first, 'office lunch');
      await tester.pumpAndSettle();

      expect(
        find.text('Nothing in the Library matches “office lunch”.'),
        findsOneWidget,
      );
      // The empty-LIBRARY line is a different claim, and a false one here.
      expect(find.textContaining('No recipes yet'), findsNothing);
      // It states a fact and offers nothing: the third answer is the footer's.
      expect(find.text(noteItLabel('office lunch')), findsOneWidget);
    });

    testWidgets('names the tab it emptied, because Favorites is not the '
        'Library', (tester) async {
      filterForuiSemanticsAssertions();

      await _open(tester);
      await tester.tap(find.text('Favorites'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(EditableText).first, 'office lunch');
      await tester.pumpAndSettle();

      expect(
        find.text('Nothing in your favorites matches “office lunch”.'),
        findsOneWidget,
      );
      expect(find.textContaining('Star a recipe'), findsNothing);
    });

    testWidgets('trims the words it quotes', (tester) async {
      filterForuiSemanticsAssertions();

      await _open(tester);
      await tester.enterText(
        find.byType(EditableText).first,
        '  office lunch  ',
      );
      await tester.pumpAndSettle();

      expect(
        find.text('Nothing in the Library matches “office lunch”.'),
        findsOneWidget,
      );
    });
  });

  // --- One door, two kinds of thing (step 8.14 / C-D1) ----------------------

  group('the ingredients section', () {
    testWidgets('is absent until something is typed — an empty query is the '
        'shipped browse surface', (tester) async {
      await _open(tester);
      expect(find.text('FOODS'), findsNothing);
      expect(find.text('Protein bar'), findsNothing);
    });

    testWidgets('appears under the recipe rows when the query hits the '
        'vocabulary', (tester) async {
      filterForuiSemanticsAssertions();

      await _open(tester);
      await tester.enterText(find.byType(EditableText).first, 'prot');
      await tester.pumpAndSettle();

      expect(find.text('FOODS'), findsOneWidget);
      expect(find.text('Protein bar'), findsOneWidget);
      // Still one door: there is no second ＋ for ingredients.
      expect(find.textContaining('new recipe'), findsOneWidget);
    });

    testWidgets('picking one resolves the picker to an INGREDIENT, not a '
        'recipe', (tester) async {
      filterForuiSemanticsAssertions();

      PickedMeal? picked;
      await tester.pumpWidget(_host(onPicked: (p) => picked = p));
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(EditableText).first, 'prot');
      await tester.pumpAndSettle();
      await tester.tap(find.text('Protein bar'));
      await tester.pumpAndSettle();

      expect(picked, isA<PickedIngredientMeal>());
      expect((picked! as PickedIngredientMeal).ingredient.id, 'i1');
    });
  });

  // --- The third answer: a meal eaten out ----------------------------------

  group("the picker's third answer", () {
    testWidgets('is absent on the browse surface, and absent while the words '
        'still hit something', (tester) async {
      filterForuiSemanticsAssertions();

      await _open(tester);
      expect(find.textContaining('note “'), findsNothing);

      // A recipe hit is an answer.
      await tester.enterText(find.byType(EditableText).first, 'chicken');
      await tester.pumpAndSettle();
      expect(find.textContaining('note “'), findsNothing);

      // So is an ingredient hit, even where no recipe matched.
      await tester.enterText(find.byType(EditableText).first, 'prot');
      await tester.pumpAndSettle();
      expect(find.text('Protein bar'), findsOneWidget);
      expect(find.textContaining('note “'), findsNothing);
    });

    testWidgets('appears when the words hit nothing, and says what the app '
        'will not do with them', (tester) async {
      filterForuiSemanticsAssertions();

      await _open(tester);
      await tester.enterText(find.byType(EditableText).first, 'office lunch');
      await tester.pumpAndSettle();

      expect(find.text(noteItLabel('office lunch')), findsOneWidget);
      expect(find.textContaining('not cooked, not bought'), findsOneWidget);
      // Still ONE door: the new-recipe row is where it always was.
      expect(find.textContaining('new recipe'), findsOneWidget);
    });

    testWidgets('resolves to the WORDS, trimmed — nothing is minted', (
      tester,
    ) async {
      filterForuiSemanticsAssertions();

      PickedMeal? picked;
      await tester.pumpWidget(_host(onPicked: (p) => picked = p));
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byType(EditableText).first,
        '  Office lunch  ',
      );
      await tester.pumpAndSettle();
      await tester.tap(find.textContaining('note “'));
      await tester.pumpAndSettle();

      expect(picked, isA<PickedMealOut>());
      expect((picked! as PickedMealOut).label, 'Office lunch');
    });
  });

  group('what was had instead', () {
    testWidgets('can always be noted as typed, even when the words hit '
        'something, and offers no new recipe', (tester) async {
      filterForuiSemanticsAssertions();

      PickedMeal? picked;
      await tester.pumpWidget(
        _host(onPicked: (p) => picked = p, instead: true),
      );
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      expect(find.text('Had instead'), findsOneWidget);
      expect(find.textContaining('new recipe'), findsNothing);
      expect(find.textContaining('note “'), findsNothing);

      // "prot" hits the protein bar, and the words can still be noted.
      await tester.enterText(find.byType(EditableText).first, 'prot');
      await tester.pumpAndSettle();
      expect(find.text('Protein bar'), findsOneWidget);
      await tester.tap(find.text(noteItLabel('prot')));
      await tester.pumpAndSettle();

      expect(picked, isA<PickedMealOut>());
      expect((picked! as PickedMealOut).label, 'prot');
    });
  });

  group('Leftovers', () {
    // Planning Wednesday 4 November on Sunday 1 November: the fridge holds a
    // curry good until that Wednesday, a dal only good until Monday and a
    // stew good until Monday that freezes; the freezer a chili and a soup in
    // the household's own words.
    final curry = Leftover(
      id: 'e-curry',
      place: LeftoverPlace.fridge,
      recipeId: 'r1',
      title: 'Weeknight Chicken Curry',
      since: DateTime(2026, 10, 29),
      goodUntil: DateTime(2026, 11, 4),
      box: 1.75,
    );
    final dal = Leftover(
      id: 'e-dal',
      place: LeftoverPlace.fridge,
      recipeId: 'r9',
      title: 'Red Lentil Dal',
      since: DateTime(2026, 10, 27),
      goodUntil: DateTime(2026, 11, 2),
      box: 1,
    );
    final stew = Leftover(
      id: 'e-stew',
      place: LeftoverPlace.fridge,
      recipeId: 'r3',
      title: 'Beef Stew',
      since: DateTime(2026, 10, 30),
      goodUntil: DateTime(2026, 11, 2),
      freezable: true,
      freezerUntil: DateTime(2026, 11, 29),
      box: 2,
    );
    final chili = Leftover(
      id: 'f1',
      place: LeftoverPlace.freezer,
      recipeId: 'r2',
      title: 'Black Bean Chili',
      since: DateTime(2026, 10, 18),
      goodUntil: DateTime(2027, 1, 16),
      box: 2,
    );
    final soup = Leftover(
      id: 'f2',
      place: LeftoverPlace.freezer,
      title: 'Soup from Mum',
      since: DateTime(2026, 10, 20),
      goodUntil: null,
      box: 2,
    );

    Widget host({
      void Function(PickedMeal?)? onPicked,
      bool instead = false,
      List<Leftover>? leftovers,
      List<Leftover> pots = const [],
    }) => _host(
      onPicked: onPicked,
      instead: instead,
      weekStart: DateTime.utc(2026, 11, 2),
      leftovers: leftovers ?? [curry, dal, chili, stew, soup],
      pots: pots,
      now: DateTime(2026, 11, 1, 10),
    );

    testWidgets('offers a dish planned last week and not cooked yet by when '
        'it cooks, and picks it as a pot', (tester) async {
      filterForuiSemanticsAssertions();
      PickedMeal? picked;
      // Monday's ragù, planned in a week before (from Monday 26 October),
      // keeps a day and freezes: Wednesday reaches it from the freezer.
      final ragu = Leftover(
        id: 'mon-meal',
        place: LeftoverPlace.fridge,
        recipeId: 'r1',
        title: 'Beef Ragù',
        since: DateTime(2026, 11, 2),
        goodUntil: DateTime(2026, 11, 3),
        box: 0,
        freezable: true,
        freezerUntil: DateTime(2026, 12, 31),
        cooked: false,
        plannedIn: DateTime(2026, 10, 26),
      );
      await tester.pumpWidget(
        host(onPicked: (p) => picked = p, leftovers: const [], pots: [ragu]),
      );
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      expect(find.text('Beef Ragù'), findsOneWidget);
      expect(find.text('cooks Mon ·'), findsOneWidget);
      expect(find.text('freeze by Tue'), findsOneWidget);
      // Nothing to count yet, and not a leftover yet.
      expect(find.textContaining('left'), findsNothing);
      await tester.tap(find.text('Beef Ragù'));
      await tester.pumpAndSettle();
      final pot = (picked! as PickedLeftover).leftover;
      expect((pot.id, pot.cooked), ('mon-meal', false));
    });

    testWidgets('lists the fridge rows good for the day, then the freezer, '
        'and picks either as a leftover', (tester) async {
      filterForuiSemanticsAssertions();
      // Three rows offered: a phone's height, not the test's default.
      tester.view.physicalSize = const Size(400, 1000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      PickedMeal? picked;
      await tester.pumpWidget(host(onPicked: (p) => picked = p));
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();

      expect(find.text('Leftovers'), findsOneWidget);
      expect(find.text('FRIDGE'), findsOneWidget);
      expect(find.text('1¾ left · till Wed'), findsOneWidget);
      // Gone by Wednesday: not offered.
      expect(find.text('Red Lentil Dal'), findsNothing);
      expect(find.text('FREEZER'), findsOneWidget);
      expect(find.text('frozen'), findsNothing);
      expect(find.text('2 left · till Jan'), findsOneWidget);
      // Gone from the fridge by Wednesday, but it freezes: in by Monday.
      expect(find.text('freeze by Mon'), findsOneWidget);
      // The freezer's subhead and the freeze-by tag.
      expect(find.byIcon(FLucideIcons.snowflake), findsNWidgets(2));
      // Soonest to go off first.
      expect(
        tester.getTopLeft(find.text('Beef Stew')).dy,
        lessThan(tester.getTopLeft(find.text('Black Bean Chili')).dy),
      );
      // Words name no recipe, so no meal can be planned from them.
      expect(find.text('Soup from Mum'), findsNothing);
      expect(
        tester.getTopLeft(find.text('FRIDGE')).dy,
        lessThan(tester.getTopLeft(find.text('FREEZER')).dy),
      );

      await tester.tap(find.text('1¾ left · till Wed'));
      await tester.pumpAndSettle();
      expect(picked, isA<PickedLeftover>());
      final left = picked! as PickedLeftover;
      expect(left.leftover.id, 'e-curry');
      expect(left.recipe.id, 'r1');

      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('2 left · till Jan'));
      await tester.pumpAndSettle();
      expect((picked! as PickedLeftover).leftover.id, 'f1');
    });

    testWidgets('a long Leftovers block scrolls with the list, the recipes '
        "under it in reach, at a phone's size", (tester) async {
      filterForuiSemanticsAssertions();
      // An iPhone's logical size.
      tester.view.physicalSize = const Size(402, 874);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      PickedMeal? picked;
      await tester.pumpWidget(
        host(
          onPicked: (p) => picked = p,
          leftovers: [
            for (var i = 0; i < 8; i++)
              Leftover(
                id: 'e-$i',
                place: i.isEven ? LeftoverPlace.fridge : LeftoverPlace.freezer,
                recipeId: 'r1',
                title: 'Batch $i',
                since: DateTime(2026, 10, 31),
                goodUntil: DateTime(2026, 11, 20),
                box: 2,
              ),
          ],
        ),
      );
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();

      // Eight rows overflow nothing: the block is part of the scroll.
      expect(tester.takeException(), isNull);
      expect(find.text('Batch 0'), findsOneWidget);
      final recipe = find.text('Halloumi Salad');
      await tester.scrollUntilVisible(
        recipe,
        200,
        scrollable: find.byType(Scrollable).last,
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      await tester.tap(recipe);
      await tester.pumpAndSettle();
      expect((picked! as PickedRecipe).recipe.id, 'r2');
    });

    testWidgets('an empty shelf draws no subhead', (tester) async {
      filterForuiSemanticsAssertions();
      await tester.pumpWidget(host(leftovers: [chili]));
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      expect(find.text('FRIDGE'), findsNothing);
      expect(find.text('FREEZER'), findsOneWidget);
    });

    testWidgets('is never offered for what was had instead', (tester) async {
      filterForuiSemanticsAssertions();
      await tester.pumpWidget(host(instead: true));
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      expect(find.text('Leftovers'), findsNothing);
    });
  });

  group("Uses last week's shop", () {
    // 300 g of spinach and 150 g of tofu left; the curry uses both, the salad
    // only a little coriander-sized nothing.
    final spare = spareOf([
      (
        ingredientId: 'spinach',
        name: 'Spinach',
        category: 'produce',
        unit: g,
        pieceBasisAmount: null,
        need: 200,
        toBuy: 200,
        bought: 500,
        usedCooked: 200,
        centsPerUnit: 0.7,
      ),
      (
        ingredientId: 'tofu',
        name: 'Firm Tofu',
        category: 'proteins',
        unit: g,
        pieceBasisAmount: null,
        need: 250,
        toBuy: 250,
        bought: 400,
        usedCooked: 250,
        centsPerUnit: 1.6,
      ),
    ]);
    final facts = (
      spare: spare,
      recipes: [
        (
          recipeId: 'r1',
          title: 'Weeknight Chicken Curry',
          servingsBase: 4.0,
          perBatch: {'spinach': 600.0, 'tofu': 300.0},
        ),
        (
          recipeId: 'r2',
          title: 'Halloumi Salad',
          servingsBase: 2.0,
          perBatch: {'spinach': 10.0},
        ),
      ],
    );

    Widget host({void Function(PickedMeal?)? onPicked}) => _host(
      onPicked: onPicked,
      weekStart: DateTime.utc(2026, 11, 2),
      now: DateTime(2026, 11, 1, 10),
      spare: (spare: facts.spare, recipes: facts.recipes),
    );

    testWidgets('offers the recipes that use the most of it, naming what '
        'each uses, and a pick is the recipe', (tester) async {
      filterForuiSemanticsAssertions();
      PickedMeal? picked;
      await tester.pumpWidget(host(onPicked: (p) => picked = p));
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();

      expect(find.text('Leftovers'), findsOneWidget);
      // Two eaters at factor 1: half the curry's batch, all that is spare.
      expect(find.text('150 g firm tofu'), findsOneWidget);
      expect(find.text('300 g spinach'), findsOneWidget);
      // The salad's 10 g scores far under half the curry's: not offered.
      expect(find.text('10 g spinach'), findsNothing);

      await tester.tap(find.text('300 g spinach'));
      await tester.pumpAndSettle();
      expect(picked, isA<PickedRecipe>());
      expect((picked! as PickedRecipe).recipe.id, 'r1');
    });

    testWidgets("what's left shows the food and the cut", (tester) async {
      filterForuiSemanticsAssertions();
      await tester.pumpWidget(host());
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      await tester.tap(find.text("what's left ›"));
      await tester.pumpAndSettle();

      expect(find.text("What's left"), findsOneWidget);
      expect(find.text('500 g in · 200 g used'), findsOneWidget);
      expect(find.text('NOT SUGGESTED'), findsOneWidget);
      expect(find.text('10 g spinach'), findsOneWidget);
    });
  });

  test('spare food is said as a count where the row has a piece weight', () {
    expect(spareAmount(75, g, 150), '½');
    expect(spareAmount(300, g, null), '300 g');
    // Too little to say a quarter of: its weight.
    expect(spareAmount(10, g, 150), '10 g');
  });

  group('leftoverAfterLine', () {
    test('says what the meal leaves, refusing more than is left', () {
      expect(leftoverAfterLine(left: 1.75, demand: 0), isNull);
      expect(leftoverAfterLine(left: 1.75, demand: 1.75), (
        text: 'uses all of it',
        tooMuch: false,
      ));
      expect(leftoverAfterLine(left: 1.75, demand: 1), (
        text: '¾ still left after this',
        tooMuch: false,
      ));
      expect(leftoverAfterLine(left: 1, demand: 1.75), (
        text: 'only 1 portion left',
        tooMuch: true,
      ));
    });
  });
}
