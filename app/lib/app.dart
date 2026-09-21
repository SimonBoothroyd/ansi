import 'package:flutter/material.dart';
import 'package:forui/forui.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

import 'core/router/app_router.dart';
import 'core/sync/session.dart';
import 'core/theme/ansi_theme.dart';
import 'shared/ansi_scroll.dart';
import 'shared/ansi_toast.dart';

/// Root widget. `MaterialApp.router` hosts go_router; every visible component
/// below it is Forui, wrapped once in [FTheme] with the Ansi theme.
class AnsiApp extends ConsumerWidget {
  const AnsiApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Keeps the session controller alive: it listens to auth changes and
    // connects/disconnects PowerSync.
    ref.watch(sessionControllerProvider);
    final theme = ansiThemeData();
    return MaterialApp.router(
      title: 'Ansi',
      debugShowCheckedModeBanner: false,
      theme: ansiHostTheme(),
      routerConfig: ref.watch(routerProvider),
      // One scrollbar for every list (`shared/ansi_scroll.dart`); the wide
      // panes' right gutter is measured against its thickness.
      scrollBehavior: const AnsiScrollBehavior(),
      // One [FToaster] for the whole app: `showFToast` walks up for it.
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
