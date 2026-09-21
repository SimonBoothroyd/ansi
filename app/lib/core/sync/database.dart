/// The app's local PowerSync database.
///
/// [openAnsiDatabase] runs once in `bootstrap.dart` and is injected into
/// [powerSyncDatabase], the concrete type the session controller connects and
/// clears. [database] is the same object as the [SqliteConnection] query
/// surface repositories use; tests override it with an in-memory connection.
library;

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:powersync/powersync.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:sqlite_async/sqlite_async.dart';

import 'schema.dart';

part 'database.g.dart';

/// Opens and initialises the local PowerSync database. It does not connect;
/// the session controller does, once the household is resolved.
Future<PowerSyncDatabase> openAnsiDatabase() async {
  // The web has no filesystem: PowerSync takes a bare name and persists via
  // OPFS/IndexedDB. Native places the file under the app support dir.
  final String dbPath;
  if (kIsWeb) {
    dbPath = 'ansi.db';
  } else {
    final dir = await getApplicationSupportDirectory();
    dbPath = p.join(dir.path, 'ansi.db');
  }
  final db = PowerSyncDatabase(schema: schema, path: dbPath);
  await db.initialize();
  return db;
}

/// The open [PowerSyncDatabase]. No default: `bootstrap.dart` overrides it
/// with the result of [openAnsiDatabase].
@Riverpod(keepAlive: true)
PowerSyncDatabase powerSyncDatabase(Ref ref) =>
    throw UnimplementedError('powerSyncDatabase provider must be overridden');

/// The open database as a [SqliteConnection], so repositories and their tests
/// depend on the query surface only. A test overrides this provider directly.
@Riverpod(keepAlive: true)
SqliteConnection database(Ref ref) => ref.watch(powerSyncDatabaseProvider);
