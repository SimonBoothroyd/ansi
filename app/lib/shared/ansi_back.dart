/// The back rule for a pushed page, in one function.
///
/// Every page pushed over the tab shell draws its own back control — on a phone
/// because the bar is gone, on a wide window because the sidebar beside it is
/// neutral. That control has one job and two cases, and the second case is easy
/// to forget:
///
/// * There **is** something under the page — the usual arrival, a push from a
///   row, a menu item or a door. Pop it.
/// * There is **nothing** under the page. `context.pop()` then throws
///   `GoError('There is nothing to pop')`, which inside a pointer handler is
///   reported to `FlutterError.onError` and swallowed: the chevron *does
///   nothing*, in every build, and on the web there is not even a system back
///   gesture to fall back on. Go to the page's home branch instead.
///
/// Two arrivals land a pushed page with an empty stack, and both are ordinary:
///
/// * a **cold deep link** — a URL pasted into a browser, a shared link, a
///   restored `?from=` after the sign-in gate (`navigation.md` §6);
/// * a **`go`**, which replaces the whole match list rather than stacking a
///   page on it. That is what the wide sidebar's Account footer door did until
///   it was made to push like the Library header's door, and it is why the
///   owner's account chevron was dead on a 1440 window.
///
/// Held by `test/shared/ansi_back_test.dart` — the contract, the two arrivals
/// per pushed route, and a structural test that fails the build if a pushed
/// view's back action pops on its own again.
library;

import 'package:flutter/widgets.dart';
import 'package:go_router/go_router.dart';

import 'guarded_navigation.dart';

/// Leaves a pushed page: pops what is under it, or goes [home] when nothing is.
///
/// [home] is where the page belongs when nothing can pop — the branch root for
/// a page reached from the loop (`/`), the manager for a page that is one row
/// of it (`/ingredients`), the thing being edited for an editor, and the
/// **referring tab** where the page knows it: a recipe opened with `?week=` was
/// opened from the Week, so that is where it goes back to. It is never a guess
/// about history; it is the page saying what it is a detail of.
///
/// [result] is what the pop carries, for the pages whose caller is waiting on
/// one — `/ingredients/new` pops with the row it made. It is dropped in the
/// [home] case, which is correct: a stack with nothing under this page has
/// nobody waiting either.
///
/// The fallback goes through [GuardedNavigation.goOnce], so a chevron hit twice
/// before the transition paints navigates once.
void ansiBack(BuildContext context, {String home = '/', Object? result}) {
  if (context.canPop()) {
    context.pop(result);
    return;
  }
  context.goOnce(home);
}
