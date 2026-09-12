/// ONE ingredient-line layout, on every surface: `[amount] [name] [note]` on a
/// single row, the amount in its own fixed column so every identity
/// left-aligns.
///
/// The recipe page is the reference — it is the screen a cook reads — and the
/// editor prints the same row rather than stacking identity over amount. This
/// suite asserts the two geometrically: same column width, same gap, and the
/// amount beside the name rather than above it.
// The pumped ProviderScope IS the root scope of each test's tree.
// ignore_for_file: scoped_providers_should_specify_dependencies
library;

import 'package:ansi/core/theme/ansi_theme.dart';
import 'package:ansi/core/units/units.dart';
import 'package:ansi/features/books/data/book_providers.dart';
import 'package:ansi/features/books/domain/book.dart';
import 'package:ansi/features/ingredients/data/ingredient_providers.dart';
import 'package:ansi/features/recipes/data/recipe_providers.dart';
import 'package:ansi/features/recipes/domain/line_display.dart';
import 'package:ansi/features/recipes/domain/method_step.dart';
import 'package:ansi/features/recipes/domain/recipe.dart';
import 'package:ansi/features/recipes/presentation/ingredient_line.dart';
import 'package:ansi/features/recipes/presentation/recipe_editor_view.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:forui/forui.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:hooks_riverpod/misc.dart' show Override;

import '../../helpers/fake_book_repository.dart';
import '../../helpers/fake_ingredient_repository.dart';
import '../../helpers/fake_recipe_repository.dart';
import '../../helpers/forui_semantics.dart';

class _FakeBookRepo extends FakeBookRepository {
  const _FakeBookRepo() : super(const [Book(id: 'b1', name: 'Our Cookbook')]);
}

const _salt = LineItem(
  id: 'i-salt',
  ingredientId: 'ing-salt',
  ingredientName: 'Salt',
  unit: g,
  quantity: 5,
  note: 'flaky',
);

const _recipe = Recipe(
  id: 'r1',
  title: 'Weeknight Curry',
  servingsBase: 2,
  groups: [
    IngredientGroup(
      id: 'g1',
      items: [
        LineItem(
          id: 'i-onion',
          ingredientId: 'ing-onion',
          ingredientName: 'Onion',
          unit: pieces,
          quantity: 1,
        ),
        _salt,
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

Widget _host(Widget child, {List<Override> overrides = const []}) =>
    ProviderScope(
      overrides: overrides,
      child: MaterialApp(
        home: FTheme(data: ansiThemeData(), child: child),
      ),
    );

/// The two rectangles share a horizontal band — the definition of "on one
/// line", and what a stacked layout fails.
void _expectSameRow(Rect amount, Rect name) {
  expect(
    amount.bottom > name.top && name.bottom > amount.top,
    isTrue,
    reason: 'the amount ($amount) is beside the name ($name), not above it',
  );
  expect(amount.right, lessThanOrEqualTo(name.left));
}

void main() {
  testWidgets('the recipe page prints the amount in its own column, then the '
      'identity', (tester) async {
    filterForuiSemanticsAssertions();
    await tester.pumpWidget(
      _host(
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: RecipeIngredientLine(uses: LineUses(uses: const [_salt])),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final amount = tester.getRect(find.text('5 g'));
    final name = tester.getRect(find.textContaining('Salt'));
    _expectSameRow(amount, name);
    expect(name.left - amount.left, kLineAmountWidth + 12);
  });

  testWidgets('the note follows the name after two spaces — no separator '
      'between a thing and its own modifier', (tester) async {
    filterForuiSemanticsAssertions();
    await tester.pumpWidget(
      _host(
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: RecipeIngredientLine(uses: LineUses(uses: const [_salt])),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Salt  flaky', findRichText: true), findsOneWidget);
    expect(find.textContaining('·', findRichText: true), findsNothing);
  });

  testWidgets('the editor prints the same row — amount cell, identity, note — '
      'on one line', (tester) async {
    filterForuiSemanticsAssertions();
    tester.view.physicalSize = const Size(1200, 3000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      _host(
        const RecipeEditorView(recipeId: 'r1'),
        overrides: [
          recipeRepositoryProvider.overrideWithValue(
            FakeRecipeRepository(recipe: _recipe),
          ),
          bookRepositoryProvider.overrideWithValue(const _FakeBookRepo()),
          ingredientRepositoryProvider.overrideWithValue(
            FakeIngredientRepo(const []),
          ),
        ],
      ),
    );
    await tester.pumpAndSettle();

    final amount = tester.getRect(find.text('5 g'));
    final name = tester.getRect(find.textContaining('Salt').first);
    _expectSameRow(amount, name);
    // The same grid the recipe page uses, measured from the amount cell's own
    // left edge — the grip sits before it, outside the three-part line.
    expect(name.left - amount.left, kLineAmountWidth + 12);
    // The note is the modifier on that same line, not a row of its own.
    expect(find.textContaining('flaky'), findsOneWidget);
  });

  testWidgets('“used in N steps” is a second muted line under the name, and '
      'only when there is one', (tester) async {
    filterForuiSemanticsAssertions();
    tester.view.physicalSize = const Size(1200, 3000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      _host(
        const RecipeEditorView(recipeId: 'r1'),
        overrides: [
          recipeRepositoryProvider.overrideWithValue(
            FakeRecipeRepository(recipe: _recipe),
          ),
          bookRepositoryProvider.overrideWithValue(const _FakeBookRepo()),
          ingredientRepositoryProvider.overrideWithValue(
            FakeIngredientRepo(const []),
          ),
        ],
      ),
    );
    await tester.pumpAndSettle();

    // One chip, on Salt — so exactly one line says so, and it says it under
    // the name rather than beside the amount.
    final used = find.text('used in 1 step');
    expect(used, findsOneWidget);
    final name = tester.getRect(find.textContaining('Salt').first);
    expect(tester.getRect(used).top, greaterThanOrEqualTo(name.bottom - 1));
    expect(tester.getRect(used).left, greaterThanOrEqualTo(name.left));
    expect(find.textContaining('used in'), findsOneWidget);
  });
}
