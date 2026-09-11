/// Week mode on screen: what it draws, what it deliberately does not, the tag
/// each kind of change wears, the footer that states its count, and the door
/// that opens the whole thing.
library;

import 'dart:async';

import 'package:ansi/core/units/units.dart';
import 'package:ansi/features/ingredients/data/ingredient_providers.dart';
import 'package:ansi/features/planning/data/planning_providers.dart';
import 'package:ansi/features/planning/domain/planning.dart';
import 'package:ansi/features/planning/presentation/copy_last_week.dart';
import 'package:ansi/features/planning/presentation/meal_editor_sheet.dart';
import 'package:ansi/features/planning/presentation/week_variant_editor.dart';
import 'package:ansi/features/planning/presentation/week_view.dart';
import 'package:ansi/features/planning/presentation/week_widgets.dart';
import 'package:ansi/features/recipes/data/recipe_providers.dart';
import 'package:ansi/features/recipes/domain/line_override.dart';
import 'package:ansi/features/recipes/domain/recipe.dart';
import 'package:ansi/features/recipes/presentation/recipe_header_form.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:hooks_riverpod/misc.dart' show Override;

import '../../helpers/fake_ingredient_repository.dart';
import '../../helpers/fake_measure_repository.dart';
import '../../helpers/fake_planning_repository.dart';
import '../../helpers/fake_recipe_repository.dart';
import '../../helpers/fake_week_variant_repository.dart';
import '../../helpers/pump_app.dart';

const _weekKey = '2026-09-14';
final _monday = DateTime.utc(2026, 9, 14);

/// A week nothing has been copied into — the notice's silent case.
final _copyWeek = _monday;

const _recipe = Recipe(
  id: 'r1',
  title: 'Slow-Cooker Beef Ragù',
  servingsBase: 4,
  steps: ['Brown the meat.', 'Simmer.'],
  groups: [
    IngredientGroup(
      id: 'g1',
      name: 'for the ragù',
      items: [
        LineItem(
          id: 'l1',
          ingredientId: 'i-sausage',
          ingredientName: 'Pork sausage',
          unit: g,
          quantity: 400,
          note: 'casings removed',
        ),
        LineItem(
          id: 'l2',
          ingredientId: 'i-wine',
          ingredientName: 'Red wine',
          unit: ml,
          quantity: 250,
        ),
        LineItem(
          id: 'l3',
          ingredientId: 'i-parmesan',
          ingredientName: 'Parmesan, grated',
          unit: g,
          quantity: 30,
          optional: true,
        ),
      ],
    ),
  ],
);

/// The week that plans the recipe on Tuesday and Saturday.
WeekPlan _week() => WeekPlan(
  id: 'wp1',
  weekStart: _monday,
  entries: const [
    PlanEntry(
      id: 'e1',
      dayOfWeek: 1,
      mealSlot: 'Dinner',
      recipeId: 'r1',
      recipeTitle: 'Slow-Cooker Beef Ragù',
      eaterIds: ['m1'],
    ),
    PlanEntry(
      id: 'e2',
      dayOfWeek: 5,
      mealSlot: 'Dinner',
      recipeId: 'r1',
      recipeTitle: 'Slow-Cooker Beef Ragù',
      eaterIds: ['m1'],
    ),
  ],
);

class _Planner extends FakePlanningRepository {
  _Planner() : super(const [Member(id: 'm1', displayName: 'Ada')]);

  @override
  Stream<WeekPlan?> watchWeek(DateTime weekStart) => Stream.value(_week());
}

List<Override> _overrides(FakeWeekVariantRepository variants) => [
  recipeRepositoryProvider.overrideWithValue(
    FakeRecipeRepository(recipe: _recipe),
  ),
  planningRepositoryProvider.overrideWithValue(_Planner()),
  weekVariantRepositoryProvider.overrideWithValue(variants),
  ingredientRepositoryProvider.overrideWithValue(
    const ReadOnlyIngredientRepo(),
  ),
  measureRepositoryProvider.overrideWithValue(FakeMeasureRepo()),
];

/// Week mode under a REAL router: its Save pops, and a pop with no router
/// throws rather than being observed.
Future<void> _pumpEditor(
  WidgetTester tester, {
  FakeWeekVariantRepository? variants,
}) async {
  late GoRouter router;
  await tester.pumpWidget(
    routedHost(
      initial: '/week',
      overrides: _overrides(variants ?? FakeWeekVariantRepository()),
      expose: (r) => router = r,
      routes: {
        '/week': (_, _) => const Text('the week'),
        '/recipes/r1/edit': (_, _) =>
            const WeekVariantEditorView(recipeId: 'r1', weekKey: _weekKey),
      },
    ),
  );
  // Pushed rather than landed on, so Save's pop has the screen it came from
  // underneath it — which is where a Save that stored something goes.
  unawaited(router.push('/recipes/r1/edit'));
  await tester.pumpAndSettle();
}

/// Every `Text` on screen, joined — the cheapest way to assert about copy that
/// is split across spans.
String _allText(WidgetTester tester) => tester
    .widgetList<Text>(find.byType(Text))
    .map((t) => t.data ?? t.textSpan?.toPlainText() ?? '')
    .join('\n');

void main() {
  group('week mode draws the list and nothing else', () {
    testWidgets(
      'the band says whose lines these are, and which days cook them',
      (tester) async {
        await _pumpEditor(tester);
        final text = _allText(tester);
        expect(text, contains('THIS WEEK ONLY'));
        expect(text, contains('Slow-Cooker Beef Ragù'));
        expect(text, contains('Tue and Sat'));
        expect(text, contains('The recipe is not changed.'));
      },
    );

    testWidgets("the recipe's own facts are stated once, and not editable", (
      tester,
    ) async {
      await _pumpEditor(tester);
      expect(find.byType(RecipeHeaderForm), findsNothing);
      expect(
        _allText(tester),
        contains('from the recipe · not edited here: serves 4 · 2 steps'),
      );
    });

    testWidgets('no method step is drawn — a chip would point at a line id an '
        'added line has not got', (tester) async {
      await _pumpEditor(tester);
      expect(find.text('Brown the meat.'), findsNothing);
      expect(find.text('Simmer.'), findsNothing);
    });

    testWidgets('every recipe line is on the list, the optional one included', (
      tester,
    ) async {
      await _pumpEditor(tester);
      final text = _allText(tester);
      expect(text, contains('Pork sausage'));
      expect(text, contains('casings removed'));
      expect(text, contains('Red wine'));
      expect(text, contains('Parmesan, grated'));
    });

    testWidgets('an untouched list offers no way back — there is nothing to '
        'go back from', (tester) async {
      await _pumpEditor(tester);
      expect(find.textContaining('Back to the recipe'), findsNothing);
    });
  });

  group('the tags and the footer', () {
    testWidgets("a swap quotes the recipe back, in the app's own name", (
      tester,
    ) async {
      await _pumpEditor(
        tester,
        variants: FakeWeekVariantRepository(
          overrides: const {
            'r1': [
              LineOverride(
                id: 'ov1',
                action: LineOverrideAction.replace,
                recipeLineItemId: 'l1',
                ingredientId: 'i-mince',
                ingredientName: 'Beef mince, 5%',
                quantity: 400,
                unit: g,
              ),
            ],
          },
        ),
      );
      final text = _allText(tester);
      expect(text, contains('Beef mince, 5%'));
      expect(text, contains('this week · was 400 g Pork sausage'));
      expect(text, contains('↺ reset'));
    });

    testWidgets('an exclusion stays on the list, struck, and says so', (
      tester,
    ) async {
      await _pumpEditor(
        tester,
        variants: FakeWeekVariantRepository(
          overrides: const {
            'r1': [
              LineOverride(
                id: 'ov1',
                action: LineOverrideAction.exclude,
                recipeLineItemId: 'l2',
              ),
            ],
          },
        ),
      );
      expect(_allText(tester), contains('Red wine'));
      expect(_allText(tester), contains('this week · left out'));
    });

    testWidgets('an optional line ticked in reads as included', (tester) async {
      await _pumpEditor(
        tester,
        variants: FakeWeekVariantRepository(
          overrides: const {
            'r1': [
              LineOverride(
                id: 'ov1',
                action: LineOverrideAction.include,
                recipeLineItemId: 'l3',
              ),
            ],
          },
        ),
      );
      expect(_allText(tester), contains('this week · included'));
    });

    testWidgets('an added line offers remove, not reset — there is nothing to '
        'go back to', (tester) async {
      await _pumpEditor(
        tester,
        variants: FakeWeekVariantRepository(
          overrides: const {
            'r1': [
              LineOverride(
                id: 'ov-basil',
                action: LineOverrideAction.add,
                ingredientId: 'i-basil',
                ingredientName: 'Basil',
                quantity: 1,
                unit: pieces,
              ),
            ],
          },
        ),
      );
      final text = _allText(tester);
      expect(text, contains('Basil'));
      expect(text, contains('this week · added'));
      expect(text, contains('✕ remove'));
      expect(text, isNot(contains('↺ reset')));
    });

    testWidgets('the footer states the count it would drop', (tester) async {
      await _pumpEditor(
        tester,
        variants: FakeWeekVariantRepository(
          overrides: const {
            'r1': [
              LineOverride(
                id: 'ov1',
                action: LineOverrideAction.exclude,
                recipeLineItemId: 'l2',
              ),
              LineOverride(
                id: 'ov2',
                action: LineOverrideAction.include,
                recipeLineItemId: 'l3',
              ),
            ],
          },
        ),
      );
      expect(find.text('Back to the recipe · drops 2 changes'), findsOneWidget);
    });

    testWidgets(
      'back to the recipe clears the draft; Save stores the clearing',
      (tester) async {
        final variants = FakeWeekVariantRepository(
          overrides: const {
            'r1': [
              LineOverride(
                id: 'ov1',
                action: LineOverrideAction.exclude,
                recipeLineItemId: 'l2',
              ),
            ],
          },
        );
        await _pumpEditor(tester, variants: variants);
        await tester.tap(find.text('Back to the recipe · drops 1 change'));
        await tester.pumpAndSettle();
        expect(_allText(tester), isNot(contains('this week · left out')));
        expect(
          variants.saved,
          isEmpty,
          reason: 'nothing is written until Save',
        );

        await tester.tap(find.text('Save'));
        await tester.pumpAndSettle();
        expect(variants.saved.single.set, isEmpty);
        expect(variants.saved.single.recipeId, 'r1');
        expect(find.text('the week'), findsOneWidget);
      },
    );

    testWidgets('a per-line reset takes no confirm', (tester) async {
      final variants = FakeWeekVariantRepository(
        overrides: const {
          'r1': [
            LineOverride(
              id: 'ov1',
              action: LineOverrideAction.exclude,
              recipeLineItemId: 'l2',
            ),
          ],
        },
      );
      await _pumpEditor(tester, variants: variants);
      await tester.tap(find.text('↺ reset'));
      await tester.pumpAndSettle();
      expect(_allText(tester), isNot(contains('this week · left out')));
    });
  });

  group('the door', () {
    testWidgets('states its own scope, because the sheet is per meal', (
      tester,
    ) async {
      await tester.pumpAnsiApp(
        _DoorHost(entry: _week().entries.first),
        overrides: _overrides(FakeWeekVariantRepository()),
      );
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      final text = _allText(tester);
      expect(text, contains('As the recipe has them'));
      expect(
        text,
        contains('a change covers every day this week — Tue and Sat'),
      );
      expect(text, contains('edit for this week'));
    });

    testWidgets('once there is a variant, the row states its count', (
      tester,
    ) async {
      await tester.pumpAnsiApp(
        _DoorHost(entry: _week().entries.first),
        overrides: _overrides(
          FakeWeekVariantRepository(
            overrides: const {
              'r1': [
                LineOverride(
                  id: 'ov1',
                  action: LineOverrideAction.exclude,
                  recipeLineItemId: 'l2',
                ),
              ],
            },
          ),
        ),
      );
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      final text = _allText(tester);
      expect(text, contains('Edited for this week'));
      expect(text, contains('1 change · Tue and Sat'));
    });
  });
  group('the dish row', () {
    /// Seven day cards do not fit a phone viewport, and the second planned day
    /// is the whole point here — so the surface is made tall enough to hold
    /// the week rather than the assertion being weakened to one row.
    void tallSurface(WidgetTester tester) {
      tester.view.physicalSize = const Size(900, 4000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
    }

    testWidgets('every planned day of a varied recipe says so', (tester) async {
      tallSurface(tester);
      await tester.pumpAnsiApp(
        const WeekView(),
        overrides: _overrides(
          FakeWeekVariantRepository(
            overrides: const {
              'r1': [
                LineOverride(
                  id: 'ov1',
                  action: LineOverrideAction.exclude,
                  recipeLineItemId: 'l2',
                ),
              ],
            },
          ),
        ),
      );
      await tester.pumpAndSettle();
      // Tuesday and Saturday both plan it, and both read the one variant.
      expect(find.byType(EditedForThisWeekMark), findsNWidgets(2));
    });

    testWidgets('a recipe nobody varied wears no mark', (tester) async {
      tallSurface(tester);
      await tester.pumpAnsiApp(
        const WeekView(),
        overrides: _overrides(FakeWeekVariantRepository()),
      );
      await tester.pumpAndSettle();
      expect(find.byType(EditedForThisWeekMark), findsNothing);
    });
  });
  group('copy last week', () {
    test('says what it left behind, naming each recipe and its count', () {
      expect(
        variantsLeftBehindLine(const [
          (recipeTitle: 'Slow-Cooker Beef Ragù', changes: 5),
        ]),
        startsWith(
          "One recipe's this-week changes were left behind — "
          'Slow-Cooker Beef Ragù (5 changes).',
        ),
      );
    });

    test('and counts the recipes when there is more than one', () {
      expect(
        variantsLeftBehindLine(const [
          (recipeTitle: 'Ragù', changes: 5),
          (recipeTitle: 'Curry', changes: 1),
        ]),
        startsWith(
          "2 recipes' this-week changes were left behind — "
          'Ragù (5 changes), Curry (1 change).',
        ),
      );
    });

    testWidgets('a copy that left nothing behind says nothing', (tester) async {
      await tester.pumpAnsiApp(
        CopyLastWeekNotice(weekStart: _copyWeek),
        overrides: _overrides(FakeWeekVariantRepository()),
      );
      await tester.pumpAndSettle();
      expect(find.byType(Text), findsNothing);
    });
  });
}

/// The meal editor sheet, opened on [entry] — the row under test lives at its
/// foot, so the whole sheet is pumped rather than the row alone.
class _DoorHost extends StatelessWidget {
  const _DoorHost({required this.entry});

  final PlanEntry entry;

  @override
  Widget build(BuildContext context) => Builder(
    builder: (context) => GestureDetector(
      onTap: () => showMealEditorSheet(context, entry: entry),
      child: const Text('open'),
    ),
  );
}
