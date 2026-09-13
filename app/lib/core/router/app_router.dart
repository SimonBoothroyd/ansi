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
import '../../shared/ansi_wide_shell.dart';
import '../sync/session.dart';

part 'app_router.g.dart';

/// The navigator that holds every page of the app proper — the tab shell and
/// each page pushed over it — inside the outer shell that draws the wide
/// chrome.
///
/// It is the app's **shell navigator**, and `shared/ansi_modals.dart` opens
/// every sheet and dialog on it. Above it sits only the root navigator, holding
/// the two gates and this one shell page. A modal up there would cover the
/// sidebar as well, but it would also sit above the *pages*: a picker that
/// pushes the flesh-out form over itself (the add-new chain) would have the
/// form land underneath the picker. One navigator for modals and for pushed
/// pages keeps that chain in one order.
final ansiShellNavigatorKey = GlobalKey<NavigatorState>(
  debugLabel: 'ansi shell',
);

/// A full-screen page, in its pane.
///
/// Every route builds through this, so the wrap that decides a page's width is
/// written once here instead of at the top of fifteen screens — and a screen
/// cannot forget it.
///
/// [fullWidth] is the opt-out for a view whose honest form uses the whole
/// content pane rather than the measure, once the chrome is beside the content
/// — the book page's section index beside its recipes, the manager's two panes.
/// It changes nothing below that band: while the bar is still under the content
/// the window *is* the pane, so the page is centred in the measure like every
/// other one.
///
/// [measure] is how wide the page is capped, for the page that keeps one wrap
/// but is not one column at its widest — `/recipes/:id`, whose Ingredients and
/// Method are read side by side. It takes [ansiWideMeasureWidth] rather than a
/// number, so the cap stays the layout file's business and never the router's.
///
/// [measureOf] is the same answer when it depends on the route's own query:
/// `/recipes/:id/edit` is the two-column editor, except with `?week=`, which is
/// one column at the measure and has no second column to make. The number is
/// still the layout file's; only which of its two the page takes is read here,
/// where the query already is.
///
/// Both are facts about the route, which is why they are stated here: a screen
/// does not measure itself ([AnsiPane]).
GoRoute _page({
  required String path,
  required String name,
  required Widget Function(GoRouterState state) builder,
  bool fullWidth = false,
  double Function(BuildContext context)? measure,
  double Function(BuildContext context) Function(GoRouterState state)?
  measureOf,
}) => GoRoute(
  path: path,
  name: name,
  builder: (context, state) => AnsiPane(
    fullWidth: fullWidth,
    measure: measure ?? measureOf?.call(state),
    child: builder(state),
  ),
);

/// A tab root: [_page]'s pane rules, except that while the bar is under the
/// content the tab shell's own single measure already covers it.
GoRoute _branch({
  required String path,
  required String name,
  required Widget Function(GoRouterState state) builder,
  bool fullWidth = false,
}) => GoRoute(
  path: path,
  name: name,
  builder: (context, state) => AnsiPane(
    fullWidth: fullWidth,
    insideShellMeasure: true,
    child: builder(state),
  ),
);

/// `/ingredients/:id` is two pages, decided by width.
///
/// Its READING posture is the fact sheet pushed over the list on a phone, and
/// the manager's two panes with that row lit once the chrome is beside the
/// content — a cold deep link included, so a shared URL opens what the person
/// who sent it was looking at. Its EDITING posture (`?edit=1`) is the form, in
/// the measure, at every width: a door that exists to change one field is not a
/// reason to redraw the page it was opened from.
///
/// Below that band there is nothing here to decide: the route is declared
/// `fullWidth`, so [AnsiPane] has already centred whatever this returns in the
/// measure. From it, the pane hands over the whole width and the form asks for
/// the measure back.
class _IngredientPage extends StatelessWidget {
  const _IngredientPage({required this.id, required this.edit});

  final String id;
  final bool edit;

  @override
  Widget build(BuildContext context) {
    final detail = IngredientDetailView(ingredientId: id, edit: edit);
    if (!AnsiShell.of(context).beside) return detail;
    return edit
        ? AnsiMeasure(child: detail)
        : IngredientListView(selectedId: id);
  }
}

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
      // One shell around the whole app: the tab shell AND every page pushed
      // over it. On a phone it draws nothing — the tabs own the bar and a
      // pushed page covers it. On wide it draws the sidebar, once and OUTSIDE
      // this navigator, which is what lets a push keep the chrome: the
      // sidebar takes no part in the transition, so it cannot slide, fade or
      // appear twice. Its own navigator key is also the one modals open on
      // (see [ansiShellNavigatorKey]).
      ShellRoute(
        navigatorKey: ansiShellNavigatorKey,
        builder: (context, state, child) => AnsiWideShell(child: child),
        routes: [
          // The four tabs are branches of one shell, so switching a tab changes
          // an index inside a single unchanged page: the bar never moves, and
          // each tab keeps its own Navigator and its own state. Not
          // `.indexedStack` — that convenience constructor hard-wires its
          // container and leaves no hook for the cross-fade.
          //
          // All four roots take the pane: the Library's shelf, the Week's day
          // pane and agenda, Cook's two-up and the Shop's list with its
          // provenance pane are each a pane's worth of design, and each caps
          // itself where its
          // own drawing says. It is the same opt-out a pushed page uses, so
          // there is one rule here and not two.
          StatefulShellRoute(
            builder: (context, state, shell) => AnsiTabShell(shell: shell),
            navigatorContainerBuilder: crossFadeBranchContainer,
            branches: [
              StatefulShellBranch(
                routes: [
                  _branch(
                    path: '/',
                    name: 'library',
                    fullWidth: true,
                    builder: (state) => const LibraryView(),
                  ),
                ],
              ),
              StatefulShellBranch(
                routes: [
                  _branch(
                    path: '/week',
                    name: 'week',
                    fullWidth: true,
                    builder: (state) => const WeekView(),
                  ),
                ],
              ),
              StatefulShellBranch(
                routes: [
                  _branch(
                    path: '/cook',
                    name: 'cook',
                    fullWidth: true,
                    builder: (state) => const CookView(),
                  ),
                ],
              ),
              StatefulShellBranch(
                routes: [
                  _branch(
                    path: '/shop',
                    name: 'shop',
                    fullWidth: true,
                    builder: (state) => const ShoppingView(),
                  ),
                ],
              ),
            ],
          ),
          // Everything below stays a sibling of the tab shell rather than a
          // child of a branch: pushed on the shell Navigator, so it covers the
          // bar and keeps the platform's own push transition and back gesture
          // (D2). On wide the outer shell keeps drawing the sidebar beside it,
          // with nothing lit.
          _page(
            path: '/import',
            name: 'import',
            // The review USES the width: from expanded up it is the source
            // page, the lines and one line's form as three columns, so it
            // takes the whole pane and caps itself where its own drawing says
            // (see [WideReviewBody]).
            fullWidth: true,
            builder: (state) => ImportView(
              initialBookId: state.uri.queryParameters['book'],
              initialSectionId: state.uri.queryParameters['section'],
            ),
          ),
          // One book on a page of its own. Pushed like the rest, so it covers
          // the bar and back returns to the Library — and deep-linkable, which
          // is the point of a book having a URL at all. It is a page that USES
          // the width: once the chrome is beside the content its sections are
          // an index beside the recipes, so it takes the whole pane there
          // (see [_page]).
          _page(
            path: '/books/:id',
            name: 'book',
            fullWidth: true,
            builder: (state) =>
                BookPageView(bookId: state.pathParameters['id']!),
          ),
          // `/account` (the household, this device, the session) and
          // `/ingredients` (the vocabulary manager) are pushed like `/import`,
          // never a fifth tab: the four tabs are the loop, and neither an
          // account nor a vocabulary is a phase of it.
          _page(
            path: '/account',
            name: 'account',
            builder: (state) => const AccountView(),
          ),
          // The manager and one row both draw their own columns once the chrome
          // is beside the content, so they take the pane there — and the pane
          // keeps centring them in the measure below it.
          _page(
            path: '/ingredients',
            name: 'ingredients',
            fullWidth: true,
            builder: (state) => const IngredientListView(),
          ),
          // `/ingredients/new` — the ONE door to making an ingredient. It is
          // the same form, with no row behind it yet: nothing is written until
          // Save, so backing out leaves nothing. `?name=` prefills it, which
          // is what a picker hands over so the words already typed into its
          // search become the row without retyping.
          //
          // Declared BEFORE `/ingredients/:id` so `new` is a route and not an
          // id.
          _page(
            path: '/ingredients/new',
            name: 'ingredient-new',
            builder: (state) => IngredientDetailView(
              name: state.uri.queryParameters['name'] ?? '',
            ),
          ),
          // `?edit=1` opens the editing posture instead of the fact sheet —
          // what a door that exists to CHANGE a field hands over (a recipe's
          // macro fix marker, the import review's piece-weight door, the
          // manager's stub band). Everything else lands on the row as it reads
          // ([_IngredientPage]).
          _page(
            path: '/ingredients/:id',
            name: 'ingredient',
            fullWidth: true,
            builder: (state) => _IngredientPage(
              id: state.pathParameters['id']!,
              edit: state.uri.queryParameters[kEditPostureQueryParam] == '1',
            ),
          ),
          // `?title=` prefills the draft — what the Library's "nothing matches"
          // state hands over, so a search for a recipe you were about to write
          // becomes the recipe. `?book=&section=` file it — what a section's
          // `＋` hands over, so the recipe lands on the shelf that was tapped
          // instead of in the default book. `?handback=1` is the line picker's
          // door: Save pops the recipe back to the line waiting on it.
          _page(
            path: '/recipes/new',
            name: 'recipe-new',
            // The editor's two columns, at the recipe page's own cap — a new
            // recipe is written in the same form an existing one is edited in.
            measure: ansiWideMeasureWidth,
            builder: (state) => RecipeEditorView(
              initialTitle: state.uri.queryParameters['title'],
              initialBookId: state.uri.queryParameters['book'],
              initialSectionId: state.uri.queryParameters['section'],
              handsBackTarget:
                  state.uri.queryParameters[kHandBackQueryParam] == '1',
            ),
          ),
          // `?week=YYYY-MM-DD` says the page was opened FROM a week that plans
          // this recipe — the Week's dish row and the Cook card's title both
          // carry it. Read exactly as `/recipes/:id/edit` reads it below. It
          // changes nothing about the page itself; it is what lets the page
          // offer the week door beside its own Edit, and the page re-checks it
          // against the week before it does.
          _page(
            path: '/recipes/:id',
            name: 'recipe',
            // The one page so far whose expanded form uses the width without
            // taking the pane: Ingredients and Method are two columns read
            // together, so it is capped wider than the measure and never
            // stretched.
            measure: ansiWideMeasureWidth,
            builder: (state) => RecipeView(
              recipeId: state.pathParameters['id']!,
              weekKey: state.uri.queryParameters['week'],
            ),
          ),
          // `?week=YYYY-MM-DD` opens the editor in WEEK MODE — the same list,
          // saving a diff against the recipe instead of the recipe (exec plan
          // 0043). It is a query param rather than a route because the mode
          // is a fact about what Save writes, exactly as `?title=` is a fact
          // about what the draft starts from.
          _page(
            path: '/recipes/:id/edit',
            name: 'recipe-edit',
            // The editor is the recipe page's own two columns — the lines and
            // the method, written side by side — so it takes the same cap.
            // Week mode inside the same path is not: it draws no header form
            // and no method, so there is no second column and its honest wide
            // form is one column at the measure.
            measureOf: (state) => state.uri.queryParameters['week'] == null
                ? ansiWideMeasureWidth
                : ansiMeasureWidth,
            builder: (state) {
              final week = state.uri.queryParameters['week'];
              final id = state.pathParameters['id'];
              return week == null || id == null
                  ? RecipeEditorView(recipeId: id)
                  : WeekVariantEditorView(recipeId: id, weekKey: week);
            },
          ),
        ],
      ),
    ],
  );
}
