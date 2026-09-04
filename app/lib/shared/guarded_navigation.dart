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
}

bool _isTop(GoRouter router, String location) =>
    router.state.uri.toString() == location;
