/// The app's local PowerSync database.
///
/// Step 2 is offline-only: we open the database and read/write locally, but
/// never call `.connect()`, so nothing syncs (see the step-2 exec plan). The
/// backend connector is step 7 — the only line it adds is `db.connect(...)`.
///
/// [openMiseDatabase] runs once in `bootstrap.dart`; its result is injected
/// into the [database] provider via a `ProviderScope` override so repositories
/// can watch reactive queries off it. Tests override [database] with an
/// in-memory connection instead.
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

/// The open database, as the common [SqliteConnection] type so repositories and
/// their tests depend on the query surface, not on PowerSync specifically.
///
/// Has no default — `bootstrap.dart` (app) or a test overrides it.
@Riverpod(keepAlive: true)
SqliteConnection database(Ref ref) =>
    throw UnimplementedError('database provider must be overridden');
