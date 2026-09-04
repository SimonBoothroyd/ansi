/// Where Save leaves you, over a real router: editing returns you to where
/// you opened the editor; creating lands you on the thing you made.
///
/// The bug this pins (plan 0025 #1): Save replaced the editor for BOTH cases,
/// so editing an existing recipe left `[opener, recipe, recipe]` on the stack
/// and the first back showed the same page again.
library;

import 'dart:async';

import 'package:ansi/core/theme/ansi_theme.dart';
import 'package:ansi/features/books/data/book_providers.dart';
import 'package:ansi/features/ingredients/data/ingredient_providers.dart';
import 'package:ansi/features/recipes/data/recipe_providers.dart';
import 'package:ansi/features/recipes/presentation/recipe_editor_view.dart';
import 'package:ansi/features/recipes/presentation/recipe_view.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:forui/forui.dart';
import 'package:go_router/go_router.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

import '../../helpers/editor_harness.dart';
import '../../helpers/forui_semantics.dart';

/// The app's real shape around the editor: an opener, the recipe page and
/// both editor routes pushed on the same navigator (navigation.md §3).
GoRouter _router() {
  final router = GoRouter(
    initialLocation: '/',
    routes: [
      GoRoute(
        path: '/',
        builder: (_, _) => const FScaffold(child: Text('the library')),
      ),
      GoRoute(
        path: '/recipes/new',
        builder: (_, _) => const RecipeEditorView(),
      ),
      GoRoute(
        path: '/recipes/:id',
        builder: (_, state) =>
            RecipeView(recipeId: state.pathParameters['id']!),
        routes: [
          GoRoute(
            path: 'edit',
            builder: (_, state) =>
                RecipeEditorView(recipeId: state.pathParameters['id']),
          ),
        ],
      ),
    ],
  );
  addTearDown(router.dispose);
  return router;
}

Future<FakeRecipeRepo> _pumpApp(WidgetTester tester, GoRouter router) async {
  filterForuiSemanticsAssertions();
  tallSurface(tester);
  final repo = FakeRecipeRepo(importedRecipe);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        recipeRepositoryProvider.overrideWithValue(repo),
        ingredientRepositoryProvider.overrideWithValue(
          const FakeIngredientRepo(),
        ),
        bookRepositoryProvider.overrideWithValue(FakeBookRepo()),
      ],
      child: MaterialApp.router(
        routerConfig: router,
        builder: (_, child) => FTheme(
          data: ansiThemeData(),
          child: FToaster(child: child ?? const SizedBox()),
        ),
      ),
    ),
  );
  await _pumpUntil(tester, find.text('the library'));
  return repo;
}

/// Pumps frames until [finder] matches, then long enough for the route
/// transition to land. `pumpAndSettle` never returns on the recipe page (it
/// carries perpetual animations), and a widget is findable while its page is
/// still sliding in.
Future<void> _pumpUntil(WidgetTester tester, Finder finder) async {
  for (var i = 0; i < 60; i++) {
    await tester.pump(const Duration(milliseconds: 50));
    if (finder.evaluate().isNotEmpty) {
      for (var settle = 0; settle < 10; settle++) {
        await tester.pump(const Duration(milliseconds: 50));
      }
      return;
    }
  }
  fail('never found $finder');
}

/// A push's future completes when the route is POPPED, so it is never awaited
/// here — that would block the test before a frame could be pumped.
Future<void> _push(
  WidgetTester tester,
  GoRouter router,
  String location,
  Finder landed,
) async {
  unawaited(router.push(location));
  await _pumpUntil(tester, landed);
}

int _depth(GoRouter router) =>
    router.routerDelegate.currentConfiguration.matches.length;

void main() {
  testWidgets(
    'saving an existing recipe pops back onto its page, and one back returns '
    'to the opener',
    (tester) async {
      final router = _router();
      final repo = await _pumpApp(tester, router);

      await _push(tester, router, '/recipes/1', find.text('Sausage Sliders'));
      await _push(tester, router, '/recipes/1/edit', find.text('Edit recipe'));
      expect(_depth(router), 3);

      await tester.tap(find.text('Save'));
      await _pumpUntil(tester, find.text('Sausage Sliders'));

      expect(repo.saved, hasLength(1));
      // Popped, not replaced: the page beneath is the one recipe page there
      // is, so the stack is [opener, recipe] — not [opener, recipe, recipe].
      expect(router.state.uri.toString(), '/recipes/1');
      expect(_depth(router), 2);
      expect(find.text('Edit recipe'), findsNothing);

      router.pop();
      await _pumpUntil(tester, find.text('the library'));
      expect(router.state.uri.toString(), '/');
      expect(_depth(router), 1);
    },
  );

  testWidgets(
    'saving a new recipe lands on it, and one back returns to the opener',
    (tester) async {
      final router = _router();
      final repo = await _pumpApp(tester, router);

      await _push(tester, router, '/recipes/new', find.text('New recipe'));
      await tester.enterText(find.byType(EditableText).first, 'Curry');
      await tester.pump();

      await tester.tap(find.text('Save'));
      await _pumpUntil(tester, find.text('Sausage Sliders'));

      // Replaced, not stacked and not flattened: the recipe just made is on
      // top and the opener is still under it.
      final newId = repo.saved.single.id;
      expect(router.state.uri.toString(), '/recipes/$newId');
      expect(_depth(router), 2);
      expect(find.text('New recipe'), findsNothing);

      router.pop();
      await _pumpUntil(tester, find.text('the library'));
      expect(router.state.uri.toString(), '/');
      expect(_depth(router), 1);
    },
  );
}
