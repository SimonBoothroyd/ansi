/// Navigation config (go_router). Routes register as features land.
///
/// A two-stage auth gate wraps everything (step 7):
/// - No Supabase session → `/sign-in`.
/// - Signed in but the [SessionController] isn't [SessionReady] yet (still
///   onboarding/connecting, or failed — the connecting screen shows the error)
///   → `/connecting`. This is what keeps a repo-reading screen from building
///   before the household exists.
/// - Fully ready → the app.
///
/// A deep link that hits a gate is preserved in a `?from=` query parameter and
/// restored once the session is ready.
///
/// The redirect re-runs on Supabase auth changes AND on [SessionController]
/// state changes (the `refresh` notifier).
library;

import 'package:flutter/widgets.dart';
import 'package:go_router/go_router.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../features/account/presentation/account_view.dart';
import '../../features/auth/presentation/connecting_view.dart';
import '../../features/auth/presentation/sign_in_view.dart';
import '../../features/books/presentation/book_page_view.dart';
import '../../features/books/presentation/library_view.dart';
import '../../features/cook_plan/presentation/cook_view.dart';
import '../../features/import/presentation/import_view.dart';
import '../../features/ingredients/presentation/ingredient_detail_view.dart';
import '../../features/ingredients/presentation/ingredient_list_view.dart';
import '../../features/planning/presentation/week_variant_editor.dart';
import '../../features/planning/presentation/week_view.dart';
import '../../features/recipes/presentation/recipe_editor_view.dart';
import '../../features/recipes/presentation/recipe_view.dart';
import '../../features/shopping/presentation/shopping_view.dart';
import '../../shared/ansi_layout.dart';
import '../../shared/ansi_tab_shell.dart';
import '../sync/session.dart';

part 'app_router.g.dart';

/// A full-screen page, in the app's measure.
///
/// Every route below the shell builds through this, so the wrap that centres a
/// page on a wide window is written once here instead of at the top of fifteen
/// screens — and a screen cannot forget it. The shell's four tabs are wrapped
/// by the shell itself (`shared/ansi_tab_shell.dart`), which is why the
/// branches keep the plain [GoRoute].
///
/// [usesWidth] is the deliberate opt-out, for a page whose honest form at
/// [AnsiLayout.expanded] is wider than one column — the book page's section
/// index beside its recipes. It changes nothing below that band: on a phone and
/// a portrait tablet the page is centred in the measure like every other. The
/// opt-out lives here rather than in the page, so the measure still has exactly
/// two appliers and a screen still never wraps itself.
GoRoute _page({
  required String path,
  required String name,
  required Widget Function(GoRouterState state) builder,
  bool usesWidth = false,
}) => GoRoute(
  path: path,
  name: name,
  builder: (context, state) =>
      usesWidth && AnsiLayout.of(context) == AnsiLayout.expanded
      ? builder(state)
      : AnsiMeasure(child: builder(state)),
);

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
      final ready = ref.read(sessionControllerProvider) is SessionReady;
      final loc = state.matchedLocation;
      final atGate = loc == '/sign-in' || loc == '/connecting';
      // The location to return to after the gates: carried through them via
      // `?from=`, captured when a non-gate location first gets redirected.
      final from = state.uri.queryParameters['from'];
      final dest = atGate ? from : (loc == '/' ? null : state.uri.toString());
      String gate(String path) => dest == null
          ? path
          : Uri(path: path, queryParameters: {'from': dest}).toString();
      if (!signedIn) return loc == '/sign-in' ? null : gate('/sign-in');
      if (!ready) return loc == '/connecting' ? null : gate('/connecting');
      if (atGate) return from ?? '/';
      return null;
    },
    routes: [
      _page(
        path: '/sign-in',
        name: 'sign-in',
        builder: (state) => const SignInView(),
      ),
      _page(
        path: '/connecting',
        name: 'connecting',
        builder: (state) => const ConnectingView(),
      ),
      // The four tabs are branches of one shell, so switching a tab changes an
      // index inside a single unchanged root page: the bar never moves, and
      // each tab keeps its own Navigator and its own state (board: Navigation
      // v2, D1/D7). Not `.indexedStack` — that convenience constructor
      // hard-wires its container and leaves no hook for the cross-fade.
      StatefulShellRoute(
        builder: (context, state, shell) => AnsiTabShell(shell: shell),
        navigatorContainerBuilder: crossFadeBranchContainer,
        branches: [
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: '/',
                name: 'library',
                builder: (context, state) => const LibraryView(),
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: '/week',
                name: 'week',
                builder: (context, state) => const WeekView(),
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: '/cook',
                name: 'cook',
                builder: (context, state) => const CookView(),
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: '/shop',
                name: 'shop',
                builder: (context, state) => const ShoppingView(),
              ),
            ],
          ),
        ],
      ),
      // Everything below stays a top-level sibling of the shell: pushed on the
      // root Navigator, so it covers the bar and keeps the platform's own push
      // transition and back gesture (D2).
      _page(
        path: '/import',
        name: 'import',
        builder: (state) => ImportView(
          initialBookId: state.uri.queryParameters['book'],
          initialSectionId: state.uri.queryParameters['section'],
        ),
      ),
      // One book on a page of its own. Pushed like the rest, so it covers the
      // bar and back returns to the Library — and deep-linkable, which is the
      // point of a book having a URL at all. It is the one page that USES the
      // width: at `expanded` its sections are an index beside the recipes,
      // so it opts out of the measure there (see [_page]).
      _page(
        path: '/books/:id',
        name: 'book',
        usesWidth: true,
        builder: (state) => BookPageView(bookId: state.pathParameters['id']!),
      ),
      // `/account` (the household, this device, the session) and
      // `/ingredients` (the vocabulary manager) are pushed like `/import`,
      // never a fifth tab: the four tabs are the loop, and neither an account
      // nor a vocabulary is a phase of it.
      _page(
        path: '/account',
        name: 'account',
        builder: (state) => const AccountView(),
      ),
      _page(
        path: '/ingredients',
        name: 'ingredients',
        builder: (state) => const IngredientListView(),
      ),
      // `/ingredients/new` — the ONE door to making an ingredient. It is the
      // same form, with no row behind it yet: nothing is written until Save, so
      // backing out leaves nothing. `?name=` prefills it, which is what a
      // picker hands over so the words already typed into its search become the
      // row without retyping.
      //
      // Declared BEFORE `/ingredients/:id` so `new` is a route and not an id.
      _page(
        path: '/ingredients/new',
        name: 'ingredient-new',
        builder: (state) =>
            IngredientDetailView(name: state.uri.queryParameters['name'] ?? ''),
      ),
      // `?edit=1` opens the editing posture instead of the fact sheet — what a
      // door that exists to CHANGE a field hands over (a recipe's macro fix
      // marker, the import review's piece-weight door, the manager's stub
      // band). Everything else lands on the row as it reads.
      _page(
        path: '/ingredients/:id',
        name: 'ingredient',
        builder: (state) => IngredientDetailView(
          ingredientId: state.pathParameters['id'],
          edit: state.uri.queryParameters[kEditPostureQueryParam] == '1',
        ),
      ),
      // `?title=` prefills the draft — what the Library's "nothing matches"
      // state hands over, so a search for a recipe you were about to write
      // becomes the recipe. `?book=&section=` file it — what a section's `＋`
      // hands over, so the recipe lands on the shelf that was tapped instead of
      // in the default book. `?handback=1` is the line picker's door: Save
      // pops the recipe back to the line that is waiting on it.
      _page(
        path: '/recipes/new',
        name: 'recipe-new',
        builder: (state) => RecipeEditorView(
          initialTitle: state.uri.queryParameters['title'],
          initialBookId: state.uri.queryParameters['book'],
          initialSectionId: state.uri.queryParameters['section'],
          handsBackTarget:
              state.uri.queryParameters[kHandBackQueryParam] == '1',
        ),
      ),
      // `?week=YYYY-MM-DD` says the page was opened FROM a week that plans
      // this recipe — the Week's dish row and the Cook card's title both carry
      // it. Read exactly as `/recipes/:id/edit` reads it below. It changes
      // nothing about the page itself; it is what lets the page offer the
      // week door beside its own Edit, and the page re-checks it against the
      // week before it does.
      _page(
        path: '/recipes/:id',
        name: 'recipe',
        builder: (state) => RecipeView(
          recipeId: state.pathParameters['id']!,
          weekKey: state.uri.queryParameters['week'],
        ),
      ),
      // `?week=YYYY-MM-DD` opens the editor in WEEK MODE — the same list,
      // saving a diff against the recipe instead of the recipe (exec plan
      // 0043). It is a query param rather than a route because the mode is a
      // fact about what Save writes, exactly as `?title=` is a fact about what
      // the draft starts from.
      _page(
        path: '/recipes/:id/edit',
        name: 'recipe-edit',
        builder: (state) {
          final week = state.uri.queryParameters['week'];
          final id = state.pathParameters['id'];
          return week == null || id == null
              ? RecipeEditorView(recipeId: id)
              : WeekVariantEditorView(recipeId: id, weekKey: week);
        },
      ),
    ],
  );
}
