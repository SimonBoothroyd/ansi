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
/// Initialises Supabase (auth + the client the connector uploads through),
/// opens the local PowerSync database, and injects it into the provider graph.
/// It does NOT connect or seed here — the session controller connects PowerSync
/// once a user signs in (step 7), and the vocab / members / default book now
/// arrive from the server rather than a local seeder.
///
/// The config guard runs *outside* the guarded zone deliberately: inside, the
/// zone's error handler would swallow it and the app would sit on a blank
/// screen — the exact quiet failure the guard exists to end.
///
/// Everything the zone DOES catch now goes to a [CrashSink] rather than to a
/// console no phone has (`core/observability/crash_sink.dart`).
void bootstrap() {
  Env.assertDefinesUsable();
  // Built inside the zone (it needs the widget tree that only exists there) and
  // read from outside it, so the handler below is wired before anything can
  // throw and upgrades itself the moment there is a screen to speak into.
  CrashSink sink = const NoopCrashSink();
  runZonedGuarded(
    () async {
      WidgetsFlutterBinding.ensureInitialized();
      await Supabase.initialize(
        url: Env.supabaseUrl,
        // The local stack issues a legacy anon JWT; anonKey stays valid even as
        // the SDK migrates callers toward publishableKey.
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
    // The seam is core/observability/crash_sink.dart — swapping in a reporting
    // service is one more implementation and one provider override here.
    (error, stack) => sink.report(error, stack),
  );
}
