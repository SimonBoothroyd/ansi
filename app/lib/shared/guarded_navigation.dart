/// Tap-guarded navigation: the form every `onTap`/`onPress` uses.
///
/// A double tap on a bare `context.push` stacks two pages. These forms skip
/// a target equal to the router's current top location ([GoRouter.state],
/// updated synchronously by a push). Only the same location is deduped.
/// `test/shared/guarded_navigation_test.dart` bans the bare calls.
library;

import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:go_router/go_router.dart';

extension GuardedNavigation on BuildContext {
  /// Pushes [location] unless the router is already showing it. A flow that
  /// continues after the page uses [pushOnceFor].
  void pushOnce(String location) {
    final router = GoRouter.of(this);
    if (_isTop(router, location)) return;
    unawaited(router.push<void>(location));
  }

  /// Pushes [location] and resolves with what the pushed page pops; resolves
  /// null at once when the router is already showing it.
  ///
  /// Safe from inside a sheet: the page lands above the sheet and popping it
  /// returns to the sheet, still open.
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

  /// Rewrites the current page's query so the address bar names its view
  /// state (`/week?day=YYYY-MM-DD`). Not navigation: no rebuild, no
  /// transition.
  ///
  /// `replace` reuses the page key; [Router.neglect] makes it report
  /// `replace: true`, so no history entry is added. A bare `replace` adds one
  /// per call. A no-op when the location already matches.
  void restateOnce(String location) {
    final router = GoRouter.of(this);
    if (_isTop(router, location)) return;
    Router.neglect(this, () => router.replace<void>(location));
  }

  /// The path of the page on top, without the query; null with no router
  /// above this context (a screen pumped alone in a test).
  ///
  /// All four tab branches stay mounted under a pushed page, and only the
  /// one on top may call [restateOnce].
  String? get topLocationPath => GoRouter.maybeOf(this)?.state.uri.path;
}

bool _isTop(GoRouter router, String location) =>
    router.state.uri.toString() == location;
