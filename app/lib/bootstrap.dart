import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'app.dart';
import 'core/config/env.dart';
import 'core/sync/database.dart';

/// Boots the app inside a guarded zone with a single [ProviderScope] root.
///
/// Initialises Supabase (auth + the client the connector uploads through),
/// opens the local PowerSync database, and injects it into the provider graph.
/// It does NOT connect or seed here — the session controller connects PowerSync
/// once a user signs in (step 7), and the vocab / members / default book now
/// arrive from the server rather than a local seeder.
///
/// The config guard runs *outside* the guarded zone deliberately: inside, the
/// zone's error handler would swallow it into a `debugPrint` and the app would
/// sit on a blank screen — the exact quiet failure the guard exists to end.
void bootstrap() {
  Env.assertDefinesUsable();
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
      final db = await openMiseDatabase();
      runApp(
        ProviderScope(
          overrides: [powerSyncDatabaseProvider.overrideWithValue(db)],
          child: const MiseApp(),
        ),
      );
    },
    (error, stack) {
      // TODO(observability): route to real error reporting.
      debugPrint('Uncaught: $error\n$stack');
    },
  );
}
