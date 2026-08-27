import 'package:flutter/material.dart';
import 'package:forui/forui.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

import 'core/router/app_router.dart';
import 'core/sync/session.dart';
import 'core/theme/mise_theme.dart';

/// Root widget. `MaterialApp.router` hosts go_router (Flutter needs a
/// `WidgetsApp` for routing, overlays and localizations); every visible
/// component below it is Forui, wrapped once in [FTheme] with the Mise theme.
class MiseApp extends ConsumerWidget {
  const MiseApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Keep the session controller alive for the app's lifetime: it listens to
    // auth changes and connects/disconnects PowerSync (step 7).
    ref.watch(sessionControllerProvider);
    final theme = miseThemeData();
    return MaterialApp.router(
      title: 'Mise',
      debugShowCheckedModeBanner: false,
      theme: miseHostTheme(),
      routerConfig: ref.watch(routerProvider),
      builder: (context, child) => FTheme(data: theme, child: child!),
    );
  }
}
