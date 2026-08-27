/// Navigation config (go_router). Routes register as features land.
library;

import 'package:go_router/go_router.dart';

import '../../features/books/presentation/library_view.dart';
import '../../features/planning/presentation/week_view.dart';
import '../../features/recipes/presentation/recipe_editor_view.dart';
import '../../features/recipes/presentation/recipe_view.dart';

/// The app's routes. `/recipes/new` is declared before `/recipes/:id` so the
/// literal wins over the param.
final router = GoRouter(
  initialLocation: '/',
  routes: [
    GoRoute(
      path: '/',
      name: 'library',
      builder: (context, state) => const LibraryView(),
    ),
    GoRoute(
      path: '/week',
      name: 'week',
      builder: (context, state) => const WeekView(),
    ),
    GoRoute(
      path: '/recipes/new',
      name: 'recipe-new',
      builder: (context, state) => const RecipeEditorView(),
    ),
    GoRoute(
      path: '/recipes/:id',
      name: 'recipe',
      builder: (context, state) =>
          RecipeView(recipeId: state.pathParameters['id']!),
    ),
    GoRoute(
      path: '/recipes/:id/edit',
      name: 'recipe-edit',
      builder: (context, state) =>
          RecipeEditorView(recipeId: state.pathParameters['id']),
    ),
  ],
);
