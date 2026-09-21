import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'app.dart';
import 'core/config/env.dart';
import 'core/observability/crash_sink.dart';
import 'core/sync/database.dart';
import 'shared/ansi_toast.dart';

/// Boots the app inside a guarded zone with a single [ProviderScope] root.
///
/// Initialises Supabase, opens the local PowerSync database and injects it
/// into the provider graph. It does not connect; the session controller does
/// on sign-in. The config guard runs outside the zone, whose handler would
/// swallow it. What the zone catches goes to a [CrashSink].
void bootstrap() {
  Env.assertDefinesUsable();
  // Built inside the zone (it needs the widget tree) and read from outside it,
  // so the handler below is wired before anything can throw.
  CrashSink sink = const NoopCrashSink();
  runZonedGuarded(
    () async {
      WidgetsFlutterBinding.ensureInitialized();
      await Supabase.initialize(
        url: Env.supabaseUrl,
        // The local stack issues a legacy anon JWT.
        // ignore: deprecated_member_use
        anonKey: Env.supabaseAnonKey,
      );
      final db = await openAnsiDatabase();
      sink = ToastCrashSink(() => ansiToastAnchor.currentContext);
      runApp(
        ProviderScope(
          overrides: [
            powerSyncDatabaseProvider.overrideWithValue(db),
            crashSinkProvider.overrideWithValue(sink),
          ],
          child: const AnsiApp(),
        ),
      );
    },
    // See core/observability/crash_sink.dart.
    (error, stack) => sink.report(error, stack),
  );
}
