import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'app.dart';

/// Boots the app inside a guarded zone with a single [ProviderScope] root.
///
// TODO(step-7): initialise the PowerSync database + Supabase client here and
/// pass overrides into [ProviderScope]. See `lib/core/sync/`.
void bootstrap() {
  runZonedGuarded(
    () {
      WidgetsFlutterBinding.ensureInitialized();
      // TODO(step-7): await sync/database init before runApp.
      runApp(const ProviderScope(child: MiseApp()));
    },
    (error, stack) {
      // TODO(observability): route to real error reporting.
      debugPrint('Uncaught: $error\n$stack');
    },
  );
}
