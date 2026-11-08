/// The Leftovers page: its two shelves, a row's moves, *Clear all*, *Add a
/// leftover*, and the Week's door with its dot.
library;

import 'package:ansi/core/week_shape.dart';
import 'package:ansi/features/account/data/household_providers.dart';
import 'package:ansi/features/cook_plan/data/cook_plan_providers.dart';
import 'package:ansi/features/cook_plan/domain/leftovers.dart';
import 'package:ansi/features/cook_plan/presentation/leftovers_view.dart';
import 'package:ansi/features/planning/presentation/week_view_models.dart';
import 'package:ansi/features/recipes/data/recipe_providers.dart';
import 'package:ansi/features/recipes/domain/recipe.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:forui/forui.dart';

import '../../helpers/fake_leftover_repository.dart';
import '../../helpers/fake_recipe_repository.dart';
import '../../helpers/forui_semantics.dart';
import '../../helpers/pump_app.dart';

/// A Wednesday; the week began on Monday 9 Nov.
final _today = DateTime(2026, 11, 11);

const _recipes = [
  RecipeSummary(
    id: 'hh',
    title: 'Hamburger Helper',
    servingsBase: 4,
    freezable: true,
  ),
  RecipeSummary(id: 'cc', title: 'Chickpea Curry', servingsBase: 4),
  RecipeSummary(
    id: 'ss',
    title: 'Squash Soup',
    servingsBase: 4,
    freezable: true,
  ),
  RecipeSummary(
    id: 'bb',
    title: 'Black Bean Chili',
    servingsBase: 4,
    freezable: true,
  ),
];

final _helper = Leftover(
  batch: 'b1',
  place: LeftoverPlace.fridge,
  recipeId: 'hh',
  title: 'Hamburger Helper',
  since: DateTime(2026, 11, 9),
  goodUntil: DateTime(2026, 11, 15),
  portions: 3,
);
final _curry = Leftover(
  id: 'c',
  place: LeftoverPlace.fridge,
  recipeId: 'cc',
  title: 'Chickpea Curry',
  since: DateTime(2026, 11, 10),
  goodUntil: DateTime(2026, 11, 16),
  portions: 1.75,
);
final _soup = Leftover(
  id: 's',
  place: LeftoverPlace.fridge,
  recipeId: 'ss',
  title: 'Squash Soup',
  since: DateTime(2026, 11, 4),
  goodUntil: DateTime(2026, 11, 8),
  portions: 2,
);
final _chili = Leftover(
  id: 'f1',
  place: LeftoverPlace.freezer,
  recipeId: 'bb',
  title: 'Black Bean Chili',
  since: DateTime(2026, 10, 28),
  goodUntil: null,
  portions: 2,
);
final _bolognese = Leftover(
  id: 'f2',
  place: LeftoverPlace.freezer,
  title: 'Lentil Bolognese',
  since: DateTime(2026, 11, 7),
  goodUntil: null,
  portions: 2,
  planned: 2,
);

Future<FakeLeftoverRepository> _pump(
  WidgetTester tester, {
  List<Leftover>? rows,
}) async {
  final repo = FakeLeftoverRepository(
    rows ?? [_helper, _curry, _soup, _chili, _bolognese],
  );
  await tester.pumpAnsiApp(
    const LeftoversView(),
    overrides: [
      leftoverRepositoryProvider.overrideWithValue(repo),
      recipeRepositoryProvider.overrideWithValue(
        FakeRecipeRepository(summaries: _recipes),
      ),
      clockProvider.overrideWithValue(
        () => _today.add(const Duration(hours: 9)),
      ),
      weekShapeProvider.overrideWithValue(WeekShape.monday),
    ],
  );
  await tester.pumpAndSettle();
  return repo;
}

void main() {
  testWidgets('two shelves, each row its count and its date', (tester) async {
    await _pump(tester);
    expect(find.text('FRIDGE'), findsOneWidget);
    expect(find.text('FREEZER'), findsOneWidget);
    expect(find.text('Hamburger Helper'), findsOneWidget);
    expect(find.text('until Sun'), findsOneWidget);
    expect(find.text('1¾'), findsOneWidget);
    expect(find.text('until Mon'), findsOneWidget);
    expect(find.text('2 · past its date'), findsOneWidget);
    expect(find.text('2 wk'), findsOneWidget);
    expect(find.text('2 · 2 planned'), findsOneWidget);
    expect(find.text('4 days'), findsOneWidget);
    // Nothing is open until a row is tapped.
    expect(find.text('Freeze'), findsNothing);
  });

  testWidgets('a tapped row opens its stepper, Freeze and Gone', (
    tester,
  ) async {
    final repo = await _pump(tester);
    await tester.tap(find.text('Hamburger Helper'));
    await tester.pumpAndSettle();
    expect(find.text('Freeze'), findsOneWidget);

    await tester.tap(find.byIcon(FLucideIcons.plus).last);
    await tester.pumpAndSettle();
    await tester.tap(find.byIcon(FLucideIcons.minus));
    await tester.pumpAndSettle();
    expect(repo.portionWrites, [(_helper, 4.0), (_helper, 2.0)]);

    await tester.tap(find.text('Freeze'));
    await tester.pumpAndSettle();
    expect(repo.freezes, [(_helper, _today)]);
  });

  testWidgets('a part portion steps to the whole on either side', (
    tester,
  ) async {
    final repo = await _pump(tester);
    await tester.tap(find.text('Chickpea Curry'));
    await tester.pumpAndSettle();
    // Not freezable, so it cannot be moved there.
    expect(find.text('Freeze'), findsNothing);
    await tester.tap(find.byIcon(FLucideIcons.minus));
    await tester.tap(find.byIcon(FLucideIcons.plus).last);
    await tester.pumpAndSettle();
    expect(repo.portionWrites, [(_curry, 1.0), (_curry, 2.0)]);

    // The open row's, above the past-its-date soup's.
    await tester.tap(find.text('Gone').first);
    await tester.pumpAndSettle();
    expect(repo.gone, [
      [_curry],
    ]);
  });

  testWidgets('past its date: Froze it dates it at its fridge day', (
    tester,
  ) async {
    final repo = await _pump(tester);
    await tester.tap(find.text('Froze it'));
    await tester.pumpAndSettle();
    expect(repo.freezes, [(_soup, DateTime(2026, 11, 8))]);
  });

  testWidgets('Clear all marks every past-its-date fridge row gone', (
    tester,
  ) async {
    final repo = await _pump(tester);
    await tester.tap(find.text('Clear all'));
    await tester.pumpAndSettle();
    expect(repo.gone, [
      [_soup],
    ]);
  });

  testWidgets('no row past its date, no Clear all', (tester) async {
    await _pump(tester, rows: [_helper, _chili]);
    expect(find.text('Clear all'), findsNothing);
    expect(find.text('Froze it'), findsNothing);
  });

  testWidgets('Add a leftover: a recipe, the freezer, three, last week', (
    tester,
  ) async {
    filterForuiSemanticsAssertions();
    final repo = await _pump(tester, rows: const []);
    expect(find.text('empty'), findsNWidgets(2));
    await tester.tap(find.bySemanticsLabel('Add a leftover'));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(EditableText), 'chili');
    await tester.pumpAndSettle();
    await tester.tap(find.text('Black Bean Chili'));
    await tester.tap(find.text('Freezer'));
    await tester.tap(find.byIcon(FLucideIcons.plus).last);
    await tester.tap(find.text('Last week'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Add'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Add'));
    await tester.pumpAndSettle();

    expect(repo.added, [
      (
        place: LeftoverPlace.freezer,
        portions: 3.0,
        since: DateTime(2026, 11, 4),
        recipeId: 'bb',
        label: null,
      ),
    ]);
    expect(find.text('Add a leftover'), findsNothing);
  });

  testWidgets('Add a leftover in the household’s own words', (tester) async {
    filterForuiSemanticsAssertions();
    final repo = await _pump(tester, rows: const []);
    await tester.tap(find.bySemanticsLabel('Add a leftover'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(EditableText), 'Soup from Mum');
    await tester.pumpAndSettle();
    await tester.tap(find.text('“Soup from Mum”'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Add'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Add'));
    await tester.pumpAndSettle();
    expect(repo.added.single.label, 'Soup from Mum');
    expect(repo.added.single.place, LeftoverPlace.fridge);
    expect(repo.added.single.since, _today);
  });

  group('the door on the Week', () {
    Future<void> door(WidgetTester tester, List<Leftover> rows) async {
      await tester.pumpAnsiApp(
        const FScaffold(
          header: FHeader.nested(
            title: Text('Week'),
            suffixes: [LeftoversDoor()],
          ),
          child: SizedBox.shrink(),
        ),
        overrides: [
          leftoverRepositoryProvider.overrideWithValue(
            FakeLeftoverRepository(rows),
          ),
          clockProvider.overrideWithValue(() => _today),
          weekShapeProvider.overrideWithValue(WeekShape.monday),
        ],
      );
      await tester.pumpAndSettle();
    }

    testWidgets('a fridge, dotted while a row is past its date', (
      tester,
    ) async {
      await door(tester, [_helper, _soup]);
      expect(find.byIcon(FLucideIcons.refrigerator), findsOneWidget);
      expect(find.byKey(kLeftoversDueDotKey), findsOneWidget);
    });

    testWidgets('no dot while every row is good', (tester) async {
      await door(tester, [_helper, _chili]);
      expect(find.byIcon(FLucideIcons.refrigerator), findsOneWidget);
      expect(find.byKey(kLeftoversDueDotKey), findsNothing);
    });
  });
}
