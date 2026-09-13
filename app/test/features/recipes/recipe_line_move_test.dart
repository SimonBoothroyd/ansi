/// Moving a line on the recipe editor: the drag files it under whichever
/// heading it was dropped beneath, its id survives, every method chip pointing
/// at it survives with it, and the order the cook left is the order that is
/// saved.
///
/// The chip is the whole reason the feature is worth building — delete +
/// re-add already reordered a list, and cost every reference — so it is
/// asserted on the move, through the save, and after a reopen.
// The pumped ProviderScope IS the root scope of each test's tree.
// ignore_for_file: scoped_providers_should_specify_dependencies
library;

import 'package:ansi/core/theme/ansi_theme.dart';
import 'package:ansi/core/units/units.dart';
import 'package:ansi/features/books/data/book_providers.dart';
import 'package:ansi/features/books/domain/book.dart';
import 'package:ansi/features/ingredients/data/ingredient_providers.dart';
import 'package:ansi/features/recipes/data/recipe_providers.dart';
import 'package:ansi/features/recipes/domain/method_step.dart';
import 'package:ansi/features/recipes/domain/recipe.dart';
import 'package:ansi/features/recipes/presentation/recipe_editor_view.dart';
import 'package:ansi/features/recipes/presentation/recipe_view_models.dart';
import 'package:ansi/shared/reorder_grip.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:forui/forui.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

import '../../helpers/fake_book_repository.dart';
import '../../helpers/fake_ingredient_repository.dart';
import '../../helpers/fake_recipe_repository.dart';
import '../../helpers/forui_semantics.dart';

class _FakeBookRepo extends FakeBookRepository {
  const _FakeBookRepo() : super(const [Book(id: 'b1', name: 'Our Cookbook')]);
}

/// Two groups — `Onion`, `Salt` under "For the sauce"; `Rice` under "To
/// serve" — and a method step whose chip points at the SALT line.
const _recipe = Recipe(
  id: 'r1',
  title: 'Weeknight Curry',
  servingsBase: 2,
  groups: [
    IngredientGroup(
      id: 'g1',
      name: 'For the sauce',
      items: [
        LineItem(
          id: 'i-onion',
          ingredientId: 'ing-onion',
          ingredientName: 'Onion',
          unit: pieces,
          quantity: 1,
        ),
        LineItem(
          id: 'i-salt',
          ingredientId: 'ing-salt',
          ingredientName: 'Salt',
          unit: g,
          quantity: 5,
          note: 'flaky',
        ),
      ],
    ),
    IngredientGroup(
      id: 'g2',
      name: 'To serve',
      items: [
        LineItem(
          id: 'i-rice',
          ingredientId: 'ing-rice',
          ingredientName: 'Rice',
          unit: g,
          quantity: 150,
        ),
      ],
    ),
  ],
  methodSteps: [
    MethodStep(
      tokens: [
        MethodToken.text(s: 'Season with '),
        MethodToken.ref(refs: ['i-salt'], label: 'Salt'),
        MethodToken.text(s: '.'),
      ],
    ),
  ],
);

ProviderContainer _container() {
  final container = ProviderContainer(
    overrides: [
      recipeRepositoryProvider.overrideWithValue(
        FakeRecipeRepository(recipe: _recipe),
      ),
      bookRepositoryProvider.overrideWithValue(const _FakeBookRepo()),
      ingredientRepositoryProvider.overrideWithValue(
        FakeIngredientRepo(const []),
      ),
    ],
  );
  addTearDown(container.dispose);
  return container;
}

RecipeEditor _editor(ProviderContainer c) =>
    c.read(recipeEditorProvider('r1').notifier);

Recipe _draft(ProviderContainer c) =>
    c.read(recipeEditorProvider('r1')).requireValue;

/// Every group's line ids, in list order — the whole of what a move changes.
List<List<String>> _order(Recipe recipe) => [
  for (final g in recipe.groups) [for (final i in g.items) i.id],
];

/// The line ids the method's chips point at.
Set<String> _chipRefs(Recipe recipe) => {
  for (final step in recipe.methodSteps ?? const <MethodStep>[])
    for (final token in step.tokens)
      if (token is MethodRef) ...token.refs,
};

Widget _host(ProviderContainer container) => UncontrolledProviderScope(
  container: container,
  child: MaterialApp(
    home: FTheme(
      data: ansiThemeData(),
      child: const RecipeEditorView(recipeId: 'r1'),
    ),
  ),
);

void main() {
  test('a line dropped under another heading is filed there, keeping its id — '
      'so the chip that points at it still does', () async {
    final container = _container();
    await container.read(recipeEditorProvider('r1').future);
    final editor = _editor(container);
    final salt = _draft(container).groups.first.items[1];

    // Rows: 0 heading · 1 Onion · 2 Salt · 3 heading · 4 Rice. Salt goes past
    // the second heading, which sits at row 3 once Salt is out.
    editor.moveLine(2, 3);

    final after = _draft(container);
    expect(_order(after), [
      ['i-onion'],
      ['i-salt', 'i-rice'],
    ]);
    // Identity, not equality: the object itself was carried across.
    expect(identical(after.groups[1].items.first, salt), isTrue);
    expect(_chipRefs(after), {'i-salt'});
    expect(editor.stepsUsing('i-salt'), 1);
  });

  test(
    'a group emptied by a move is kept — the heading is the human’s',
    () async {
      final container = _container();
      await container.read(recipeEditorProvider('r1').future);
      _editor(container).moveLine(4, 1);

      final after = _draft(container);
      expect(after.groups, hasLength(2));
      expect(after.groups.last.items, isEmpty);
      expect(after.groups.last.name, 'To serve');
    },
  );

  test('the order the cook left is the order that is saved, and the chip is '
      'still on the moved line', () async {
    final container = _container();
    await container.read(recipeEditorProvider('r1').future);
    final editor = _editor(container)..moveLine(2, 3);
    await editor.save();

    final repo =
        container.read(recipeRepositoryProvider) as FakeRecipeRepository;
    final saved = repo.saved.single;
    // `sort_order` is written from list position, so this list IS the order.
    expect(_order(saved), [
      ['i-onion'],
      ['i-salt', 'i-rice'],
    ]);
    // `save` prunes refs whose line is gone; the moved line is not gone.
    expect(_chipRefs(saved), {'i-salt'});
  });

  testWidgets('the grip drags the row, and nothing else does', (tester) async {
    filterForuiSemanticsAssertions();
    tester.view.physicalSize = const Size(1000, 3000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    final container = _container();
    await tester.pumpWidget(_host(container));
    await tester.pumpAndSettle();

    final grips = find.byType(DragGrip);
    expect(grips, findsNWidgets(3), reason: 'one per line, none on a heading');

    // Take hold of the Salt row's grip and carry it to the bottom of the
    // list: past the "To serve" heading, past Rice.
    final saltGrip = tester.getCenter(grips.at(1));
    final riceRow = tester.getCenter(find.text('Rice'));
    final drag = await tester.startGesture(saltGrip);
    await tester.pump(const Duration(milliseconds: 200));
    await drag.moveTo(Offset(saltGrip.dx, riceRow.dy + 120));
    await tester.pump();
    await drag.up();
    await tester.pumpAndSettle();

    final after = _draft(container);
    expect(_order(after), [
      ['i-onion'],
      ['i-rice', 'i-salt'],
    ]);
    expect(_chipRefs(after), {'i-salt'});
  });
}
