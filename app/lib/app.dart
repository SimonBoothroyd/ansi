import 'package:flutter/material.dart';
import 'package:forui/forui.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

import 'core/router/app_router.dart';
import 'core/sync/session.dart';
import 'core/theme/ansi_theme.dart';
import 'shared/ansi_scroll.dart';
import 'shared/ansi_toast.dart';

/// Root widget. `MaterialApp.router` hosts go_router (Flutter needs a
/// `WidgetsApp` for routing, overlays and localizations); every visible
/// component below it is Forui, wrapped once in [FTheme] with the Ansi theme.
class AnsiApp extends ConsumerWidget {
  const AnsiApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Keep the session controller alive for the app's lifetime: it listens to
    // auth changes and connects/disconnects PowerSync (step 7).
    ref.watch(sessionControllerProvider);
    final theme = ansiThemeData();
    return MaterialApp.router(
      title: 'Ansi',
      debugShowCheckedModeBanner: false,
      theme: ansiHostTheme(),
      routerConfig: ref.watch(routerProvider),
      // The app's own scrollbar, for every list in it: a stated thickness, a
      // stated margin in from the pane's edge, and drawn only where a mouse is
      // doing the pointing (`shared/ansi_scroll.dart`). Here rather than per
      // screen because a scrollbar that differs by pane is two scrollbars, and
      // because the wide panes' right gutter is measured against this number.
      scrollBehavior: const AnsiScrollBehavior(),
      // One [FToaster] for the whole app, beside the theme: `showFToast` walks
      // up for it, so every toast the app raises — from any route, sheet or
      // dialog — lands in this one stack instead of a per-screen overlay.
      builder: (context, child) => FTheme(
        data: theme,
        child: FToaster(
          // The anchor the zone handler toasts through: it runs outside the
          // widget tree and has no context of its own.
          child: KeyedSubtree(key: ansiToastAnchor, child: child!),
        ),
      ),
    );
  }
}
