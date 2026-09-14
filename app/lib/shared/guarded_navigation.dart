/// Tap-guarded navigation — the form every `onTap`/`onPress` should use.
///
/// A bare `context.push('/recipes/7')` fired from a tap target opens a page per
/// tap. On a phone the same row is easy to hit twice before the first
/// transition has painted, and go_router obliges: two identical recipe pages
/// stack up and the user has to press back once per tap.
///
/// [GuardedNavigation.pushOnce] and [GuardedNavigation.goOnce] are the tap-safe
/// forms. They compare the target against the router's current TOP location and
/// do nothing when the two match. go_router writes a push into
/// `routerDelegate.currentConfiguration` synchronously (before the transition
/// animates), so the second of two taps in the same frame already sees the
/// first one's page on top and is dropped.
///
/// ## Contract
/// The dedupe is deliberately narrow: SAME location only. A tap that leads
/// somewhere else is never swallowed, so no caller has to reason about how long
/// a route transition takes, and no navigation can go missing because an
/// unrelated one was in flight. Opening the page you are already looking at is
/// not a use case here — every call site is a row, a menu item or a nav tab.
///
/// Comparison is against [GoRouter.state], whose `uri` is the location of the
/// last route pushed or gone to, with path parameters already substituted
/// (`/recipes/7`, not `/recipes/:id`).
///
/// [GuardedNavigation.pushOnceFor] is the one push that hands the pushed page's
/// pop value back. It exists for a flow that genuinely continues after the page
/// — a picker that has just created an ingredient pushes the flesh-out form,
/// waits for back, and only then resolves — and it keeps the same top-location
/// guard, so a double tap still opens one form.
///
/// [GuardedNavigation.restateOnce] is the odd one out and is not navigation at
/// all: it rewrites the CURRENT page's query so the address bar names the view
/// state on screen (`/week?day=…`), with no history entry and no rebuild of the
/// page. It is here because it is the fourth member of the same family and
/// because the structural test below bans the bare `context.replace` it wraps.
///
/// A structural test (`test/shared/guarded_navigation_test.dart`) fails the
/// build if a view under `lib/features/**/presentation` or `lib/shared` calls
/// bare `context.push` again.
library;

import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:go_router/go_router.dart';

extension GuardedNavigation on BuildContext {
  /// Pushes [location] unless the router is already showing it.
  ///
  /// The push itself is fire-and-forget, and stays void on purpose: a tap
  /// site that only opens a page has nothing to wait for, and an awaited push
  /// there would hold the handler open across a whole page visit for no
  /// reader's benefit. A flow that really does continue after the page uses
  /// [pushOnceFor].
  void pushOnce(String location) {
    final router = GoRouter.of(this);
    if (_isTop(router, location)) return;
    unawaited(router.push<void>(location));
  }

  /// Pushes [location] and resolves with what the pushed page pops — unless
  /// the router is already showing it, in which case nothing is pushed and
  /// this resolves null at once. The first of two taps is the one awaiting
  /// the real pop; the second has nothing to wait for.
  ///
  /// Safe to call from inside a sheet on the root navigator: the page lands
  /// above the sheet, and popping it returns to the sheet, still open — the
  /// contract test pins this, because the whole create → flesh out → resolve
  /// chain stands on it.
  Future<T?> pushOnceFor<T extends Object?>(String location) {
    final router = GoRouter.of(this);
    if (_isTop(router, location)) return Future<T?>.value();
    return router.push<T>(location);
  }

  /// Navigates to [location], replacing the stack, unless the router is already
  /// showing it.
  void goOnce(String location) {
    final router = GoRouter.of(this);
    if (_isTop(router, location)) return;
    router.go(location);
  }

  /// Restates the page you are already on, so the address bar names the view
  /// state on it — `/week?day=YYYY-MM-DD`. **Not navigation:** the page does
  /// not change, no transition runs, and the screen keeps its state.
  ///
  /// It goes through `replace` inside [Router.neglect], and that pair is what
  /// makes those three things true. `replace` reuses the page key, so the
  /// screen is not rebuilt from scratch and the branch keeps its own navigator;
  /// [Router.neglect] reports the new location with `replace: true`, so the
  /// browser history gets **no new entry** — back leaves the week rather than
  /// walking backwards through every day the reader looked at. (go_router's
  /// `replace` on its own still reports `replace: false`, i.e. one history
  /// entry per day: that is the trap this wraps.)
  ///
  /// A no-op when the location already says this, so a rebuild cannot churn.
  void restateOnce(String location) {
    final router = GoRouter.of(this);
    if (_isTop(router, location)) return;
    Router.neglect(this, () => router.replace<void>(location));
  }

  /// The PATH of the page currently on top, with no query — the page the
  /// address bar names. Null when there is no router above this context.
  ///
  /// What an offstage screen asks before it restates anything: all four tab
  /// branches stay mounted and rebuild while a pushed page is on top, and only
  /// the one on top may name the location ([restateOnce]).
  ///
  /// Nullable because a screen pumped on its own — which is how most of this
  /// suite tests one — has no router at all, and a screen that names the
  /// location when there is one must still BUILD when there is not.
  String? get topLocationPath => GoRouter.maybeOf(this)?.state.uri.path;
}

bool _isTop(GoRouter router, String location) =>
    router.state.uri.toString() == location;
