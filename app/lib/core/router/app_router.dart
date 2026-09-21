/// Navigation config (go_router).
///
/// A two-stage gate wraps every route: no Supabase session → `/sign-in`;
/// signed in but [SessionController] not yet [SessionReady] → `/connecting`.
/// A gated deep link is carried in `?from=` and restored once ready. See
/// `docs/design-docs/navigation.md`.
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
import '../../features/receipts/presentation/receipt_ledger_view.dart';
import '../../features/receipts/presentation/receipt_scan_view.dart';
import '../../features/recipes/presentation/recipe_editor_view.dart';
import '../../features/recipes/presentation/recipe_view.dart';
import '../../features/shopping/presentation/shopping_view.dart';
import '../../shared/ansi_layout.dart';
import '../../shared/ansi_tab_shell.dart';
import '../../shared/ansi_wide_shell.dart';
import '../sync/session.dart';

part 'app_router.g.dart';

/// The shell navigator: holds the tab shell and every page pushed over it.
///
/// `shared/ansi_modals.dart` opens sheets and dialogs on it, not on the root:
/// a root modal would sit above the pages, so a form pushed from a picker
/// would land underneath that picker.
final ansiShellNavigatorKey = GlobalKey<NavigatorState>(
  debugLabel: 'ansi shell',
);

/// A full-screen page wrapped in its [AnsiPane], so a route states its width
/// and a screen never measures itself.
///
/// [fullWidth] gives the page the whole content pane once the chrome is beside
/// the content. [measure] caps the page wider than one column;
/// [measureOf] is the same cap chosen from the route's query.
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

/// `/ingredients` and `/ingredients/:id`, built as one page.
///
/// On a desk a pick restates one location as the other. Two builders would
/// put [IngredientListView] at two depths, so the first pick would rebuild it
/// and lose its scroll, search and posture. `?edit=1` is the form, in the
/// measure, at every width.
class _IngredientPage extends StatelessWidget {
  const _IngredientPage({this.id, this.edit = false});

  /// Null on `/ingredients`.
  final String? id;
  final bool edit;

  @override
  Widget build(BuildContext context) {
    if (id == null) return const IngredientListView();
    final detail = IngredientDetailView(ingredientId: id, edit: edit);
    if (!AnsiShell.of(context).beside) return detail;
    return edit
        ? AnsiMeasure(child: detail)
        : IngredientListView(selectedId: id);
  }
}

/// Makes the browser's address bar follow pushed pages.
///
/// go_router ignores `push`/`replace` when reporting the URL unless
/// `GoRouter.optionURLReflectsImperativeAPIs` is set, so a refresh on a pushed
/// page would land on its tab root. The flag is safe here because every pushed
/// route resolves from a cold start (pinned by `ansi_back_test.dart`).
void ansiUrlFollowsEveryPush() {
  GoRouter.optionURLReflectsImperativeAPIs = true;
}

/// The auth gate as a pure function of the location and the session facts.
///
/// Returns the location to redirect to, or null to let [state] through. A
/// non-gate location other than `/` is carried through both gates in `?from=`
/// (query included) and restored once the session is ready.
String? ansiGate(
  GoRouterState state, {
  required bool signedIn,
  required bool ready,
}) {
  final loc = state.matchedLocation;
  final atGate = loc == '/sign-in' || loc == '/connecting';
  // Where to return after the gates.
  final from = state.uri.queryParameters['from'];
  final dest = atGate ? from : (loc == '/' ? null : state.uri.toString());
  String gate(String path) => dest == null
      ? path
      : Uri(path: path, queryParameters: {'from': dest}).toString();
  if (!signedIn) return loc == '/sign-in' ? null : gate('/sign-in');
  if (!ready) return loc == '/connecting' ? null : gate('/connecting');
  if (atGate) return from ?? '/';
  return null;
}

/// The app's routes. `/recipes/new` is declared before `/recipes/:id` so the
/// literal wins over the param.
@Riverpod(keepAlive: true)
GoRouter router(Ref ref) {
  ansiUrlFollowsEveryPush();
  // Re-runs the redirect on auth and on session-readiness changes.
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
    redirect: (context, state) => ansiGate(
      state,
      signedIn: Supabase.instance.client.auth.currentSession != null,
      ready: ref.read(sessionControllerProvider) is SessionReady,
    ),
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
      // One shell around the tab shell and every pushed page. On wide it
      // draws the sidebar outside this navigator, so a push never animates
      // the chrome. Modals open on its key ([ansiShellNavigatorKey]).
      ShellRoute(
        navigatorKey: ansiShellNavigatorKey,
        builder: (context, state, child) => AnsiWideShell(child: child),
        routes: [
          // Not `.indexedStack`: that constructor leaves no hook for the
          // cross-fade. All four roots take the pane and cap themselves.
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
              // The week tabs keep the week on screen in `?week=`
              // (`YYYY-MM-DD`), and the Week also its day, so a refresh
              // keeps both ([WeekInTheLocation]).
              StatefulShellBranch(
                routes: [
                  _branch(
                    path: '/week',
                    name: 'week',
                    fullWidth: true,
                    builder: (state) => WeekView(
                      weekKey: state.uri.queryParameters['week'],
                      dayKey: state.uri.queryParameters['day'],
                    ),
                  ),
                ],
              ),
              StatefulShellBranch(
                routes: [
                  _branch(
                    path: '/cook',
                    name: 'cook',
                    fullWidth: true,
                    builder: (state) =>
                        CookView(weekKey: state.uri.queryParameters['week']),
                  ),
                ],
              ),
              StatefulShellBranch(
                routes: [
                  _branch(
                    path: '/shop',
                    name: 'shop',
                    fullWidth: true,
                    builder: (state) => ShoppingView(
                      weekKey: state.uri.queryParameters['week'],
                    ),
                  ),
                ],
              ),
            ],
          ),
          // Siblings of the tab shell, pushed on the shell Navigator: they
          // cover the bar and keep the platform transition and back gesture.
          _page(
            path: '/import',
            name: 'import',
            // Three columns from expanded up ([WideReviewBody]).
            fullWidth: true,
            builder: (state) => ImportView(
              initialBookId: state.uri.queryParameters['book'],
              initialSectionId: state.uri.queryParameters['section'],
            ),
          ),
          // `/receipts/review` is declared before `/receipts/:id` so `review`
          // is not read as an id. The scan is one route: nothing is written
          // until Save.
          _page(
            path: '/receipts',
            name: 'receipts',
            builder: (state) => const ReceiptLedgerView(),
          ),
          _page(
            path: '/receipts/review',
            name: 'receipt-scan',
            builder: (state) => const ReceiptScanView(),
          ),
          _page(
            path: '/receipts/:id',
            name: 'receipt',
            builder: (state) =>
                StoredReceiptView(receiptId: state.pathParameters['id']!),
          ),
          // One book. Its sections are an index beside the recipes once the
          // chrome is beside the content, so it takes the pane.
          _page(
            path: '/books/:id',
            name: 'book',
            fullWidth: true,
            builder: (state) =>
                BookPageView(bookId: state.pathParameters['id']!),
          ),
          // `/account` and `/ingredients` are pushed pages, not tabs.
          _page(
            path: '/account',
            name: 'account',
            builder: (state) => const AccountView(),
          ),
          // The manager and a row draw their own columns on wide.
          _page(
            path: '/ingredients',
            name: 'ingredients',
            fullWidth: true,
            builder: (state) => const _IngredientPage(),
          ),
          // The one door to making an ingredient; `?name=` prefills it.
          // Declared before `/ingredients/:id` so `new` is not read as an id.
          _page(
            path: '/ingredients/new',
            name: 'ingredient-new',
            builder: (state) => IngredientDetailView(
              name: state.uri.queryParameters['name'] ?? '',
            ),
          ),
          // `?edit=1` opens the form instead of the fact sheet
          // ([_IngredientPage]).
          _page(
            path: '/ingredients/:id',
            name: 'ingredient',
            fullWidth: true,
            builder: (state) => _IngredientPage(
              id: state.pathParameters['id'],
              edit: state.uri.queryParameters[kEditPostureQueryParam] == '1',
            ),
          ),
          // `?title=` prefills the draft, `?book=&section=` file it, and
          // `?handback=1` pops the saved recipe back to the waiting line.
          _page(
            path: '/recipes/new',
            name: 'recipe-new',
            // Two columns, at the recipe page's cap.
            measure: ansiWideMeasureWidth,
            builder: (state) => RecipeEditorView(
              initialTitle: state.uri.queryParameters['title'],
              initialBookId: state.uri.queryParameters['book'],
              initialSectionId: state.uri.queryParameters['section'],
              handsBackTarget:
                  state.uri.queryParameters[kHandBackQueryParam] == '1',
            ),
          ),
          // `?week=YYYY-MM-DD`: opened from a week that plans this recipe, so
          // the page offers the week door. The page re-checks it.
          _page(
            path: '/recipes/:id',
            name: 'recipe',
            // Ingredients and Method side by side: capped, never stretched.
            measure: ansiWideMeasureWidth,
            builder: (state) => RecipeView(
              recipeId: state.pathParameters['id']!,
              weekKey: state.uri.queryParameters['week'],
            ),
          ),
          // `?week=YYYY-MM-DD` opens the editor in week mode: Save writes a
          // diff against the recipe instead of the recipe.
          _page(
            path: '/recipes/:id/edit',
            name: 'recipe-edit',
            // Two columns, except week mode, which has no method column.
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
