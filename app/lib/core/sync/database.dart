/// The app's local PowerSync database.
///
/// [openMiseDatabase] runs once in `bootstrap.dart`; the open database is
/// injected into [powerSyncDatabase] via a `ProviderScope` override. Two views
/// onto it:
/// - [powerSyncDatabase] is the concrete [PowerSyncDatabase] — the session
///   controller needs it to call `.connect()` / `.disconnectAndClear()` as auth
///   changes (step 7).
/// - [database] is the same object as the narrower [SqliteConnection] query
///   surface repositories depend on. Tests override [database] directly with an
///   in-memory connection (they never touch [powerSyncDatabase]).
library;

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:powersync/powersync.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:sqlite_async/sqlite_async.dart';

import 'schema.dart';

part 'database.g.dart';

/// Opens (and initialises) the local PowerSync database. No `.connect()` — data
/// stays on-device until the step-7 connector lands.
Future<PowerSyncDatabase> openMiseDatabase() async {
  // On web there is no filesystem: PowerSync takes a bare name and persists via
  // OPFS/IndexedDB. On native we place the file under the app support dir.
  final String dbPath;
  if (kIsWeb) {
    dbPath = 'mise.db';
  } else {
    final dir = await getApplicationSupportDirectory();
    dbPath = p.join(dir.path, 'mise.db');
  }
  final db = PowerSyncDatabase(schema: schema, path: dbPath);
  await db.initialize();
  return db;
}

/// The open [PowerSyncDatabase]. Has no default — `bootstrap.dart` overrides it
/// with the result of [openMiseDatabase]. Repo tests don't use it.
@Riverpod(keepAlive: true)
PowerSyncDatabase powerSyncDatabase(Ref ref) =>
    throw UnimplementedError('powerSyncDatabase provider must be overridden');

/// The open database, as the common [SqliteConnection] type so repositories and
/// their tests depend on the query surface, not on PowerSync specifically.
///
/// Derives from [powerSyncDatabase] in the app; a test overrides *this*
/// provider directly with an in-memory connection.
@Riverpod(keepAlive: true)
SqliteConnection database(Ref ref) => ref.watch(powerSyncDatabaseProvider);
