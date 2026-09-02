import 'package:flutter/material.dart';
import 'package:forui/forui.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

import 'core/router/app_router.dart';
import 'core/sync/session.dart';
import 'core/theme/ansi_theme.dart';

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
      // One [FToaster] for the whole app, beside the theme: `showFToast` walks
      // up for it, so every toast the app raises — from any route, sheet or
      // dialog — lands in this one stack instead of a per-screen overlay.
      builder: (context, child) => FTheme(
        data: theme,
        child: FToaster(child: child!),
      ),
    );
  }
}
