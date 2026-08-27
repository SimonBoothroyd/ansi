/// Navigation config (go_router). Routes register as features land.
///
/// A two-stage auth gate wraps everything (step 7):
/// - No Supabase session → `/sign-in`.
/// - Signed in but the [SessionController] hasn't finished onboarding +
///   connecting PowerSync (so `currentHouseholdId` isn't resolved yet) →
///   `/connecting`. This is what keeps a repo-reading screen from building
///   before the household exists.
/// - Fully ready → the app.
///
/// The redirect re-runs on Supabase auth changes AND on [SessionController]
/// state changes (the `refresh` notifier).
library;

import 'package:flutter/foundation.dart';
import 'package:go_router/go_router.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../features/auth/presentation/connecting_view.dart';
import '../../features/auth/presentation/sign_in_view.dart';
import '../../features/books/presentation/library_view.dart';
import '../../features/cook_plan/presentation/cook_view.dart';
import '../../features/planning/presentation/week_view.dart';
import '../../features/recipes/presentation/recipe_editor_view.dart';
import '../../features/recipes/presentation/recipe_view.dart';
import '../../features/shopping/presentation/shopping_view.dart';
import '../sync/session.dart';

part 'app_router.g.dart';

/// The app's routes. `/recipes/new` is declared before `/recipes/:id` so the
/// literal wins over the param.
@Riverpod(keepAlive: true)
GoRouter router(Ref ref) {
  // Fires the redirect on either auth changes or session-readiness changes.
  final refresh = ValueNotifier<int>(0);
  final sub = Supabase.instance.client.auth.onAuthStateChange.listen(
    (_) => refresh.value++,
  );
  ref
    ..onDispose(sub.cancel)
    ..onDispose(refresh.dispose)
    ..listen(sessionControllerProvider, (_, _) => refresh.value++);

  return GoRouter(
    initialLocation: '/',
    refreshListenable: refresh,
    redirect: (context, state) {
      final signedIn = Supabase.instance.client.auth.currentSession != null;
      final ready = ref.read(sessionControllerProvider) != null;
      final loc = state.matchedLocation;
      if (!signedIn) return loc == '/sign-in' ? null : '/sign-in';
      if (!ready) return loc == '/connecting' ? null : '/connecting';
      if (loc == '/sign-in' || loc == '/connecting') return '/';
      return null;
    },
    routes: [
      GoRoute(
        path: '/sign-in',
        name: 'sign-in',
        builder: (context, state) => const SignInView(),
      ),
      GoRoute(
        path: '/connecting',
        name: 'connecting',
        builder: (context, state) => const ConnectingView(),
      ),
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
        path: '/cook',
        name: 'cook',
        builder: (context, state) => const CookView(),
      ),
      GoRoute(
        path: '/shop',
        name: 'shop',
        builder: (context, state) => const ShoppingView(),
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
}
