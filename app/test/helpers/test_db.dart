/// A real [PowerSyncDatabase] for repository tests, on the host VM.
///
/// Repositories talk to PowerSync's *local* tables, which are SQLite VIEWS over
/// `ps_data__*` with INSTEAD OF triggers. A view rejects `INSERT … ON CONFLICT`
/// outright — a statement a hand-rolled `CREATE TABLE` test database accepts
/// happily, which is how the step-2 UPSERT bug shipped green. Opening the real
/// schema here means a repo test fails for the same reason the phone does, and
/// it can't drift from `schema.dart` either.
///
/// On-device the PowerSync SQLite core extension is linked in by
/// `powersync_flutter_libs`; on the host it must be dlopen'd from a downloaded
/// binary — `make powersync-core` (run by `make test-app`) puts it in `app/`.
library;

import 'dart:convert';
import 'dart:ffi';
import 'dart:io';

import 'package:ansi/core/sync/schema.dart';
import 'package:powersync/powersync.dart';
import 'package:sqlite3/open.dart';
import 'package:sqlite3/sqlite3.dart' show SqliteExtension, sqlite3;

/// Where `scripts/fetch_powersync_core.sh` leaves the extension, relative to
/// the package root (`flutter test`'s working directory).
String _extensionPath() {
  final name = Platform.isMacOS ? 'libpowersync.dylib' : 'libpowersync.so';
  final file = File(name).absolute;
  if (!file.existsSync()) {
    throw StateError(
      'PowerSync core extension not found at ${file.path}. '
      'Run `make powersync-core` (or `make test-app`, which does).',
    );
  }
  return file.path;
}

/// macOS ships SQLite built with `OMIT_LOAD_EXTENSION`, so the system library
/// cannot register the PowerSync extension at all. Point sqlite3 at Homebrew's
/// build instead (on Linux the distro library supports extensions).
String? _sqliteOverridePath() {
  if (!Platform.isMacOS) return null;
  const candidates = [
    '/opt/homebrew/opt/sqlite/lib/libsqlite3.dylib',
    '/usr/local/opt/sqlite/lib/libsqlite3.dylib',
  ];
  for (final path in candidates) {
    if (File(path).existsSync()) return path;
  }
  throw StateError(
    'No extension-capable SQLite found in $candidates — macOS system SQLite '
    'cannot load extensions. Run `brew install sqlite`.',
  );
}

/// Loads the extension from an explicit path instead of the default lookup,
/// which relies on the library being on the dynamic linker's search path.
///
/// Both hooks run inside sqlite_async's database isolate, before that isolate
/// has touched sqlite3 — the only point where the library can still be swapped.
class _TestOpenFactory extends PowerSyncOpenFactory {
  _TestOpenFactory({
    required super.path,
    required this.extensionPath,
    required this.sqlitePath,
  });

  final String extensionPath;
  final String? sqlitePath;

  @override
  void enableExtension() {
    final sqlitePath = this.sqlitePath;
    if (sqlitePath != null) {
      open.overrideForAll(() => DynamicLibrary.open(sqlitePath));
    }
    sqlite3.ensureExtensionLoaded(
      SqliteExtension.inLibrary(
        DynamicLibrary.open(extensionPath),
        'sqlite3_powersync_init',
      ),
    );
  }
}

/// Opens a fresh database in a temp dir with the app's real [schema]. Never
/// connects, so nothing reaches the network. Call [closeTestDb] to dispose.
Future<(PowerSyncDatabase, Directory)> openTestDb() async {
  final dir = Directory.systemTemp.createTempSync('ansi_test');
  final db = PowerSyncDatabase.withFactory(
    _TestOpenFactory(
      path: '${dir.path}/test.db',
      extensionPath: _extensionPath(),
      sqlitePath: _sqliteOverridePath(),
    ),
    schema: schema,
  );
  await db.initialize();
  return (db, dir);
}

Future<void> closeTestDb(PowerSyncDatabase db, Directory dir) async {
  await db.close();
  dir.deleteSync(recursive: true);
}

/// Marks every pending local write as uploaded (via the sanctioned crud API),
/// so a test can then assert on exactly the ops a later action queues.
Future<void> drainCrudQueue(PowerSyncDatabase db) async {
  while (true) {
    final tx = await db.getNextCrudTransaction();
    if (tx == null) return;
    await tx.complete();
  }
}

/// The pending upload queue (`ps_crud`), oldest first, each op decoded to its
/// JSON form: `{op: PUT|PATCH|DELETE, type: <table>, id: <row>, data: {...}}`.
Future<List<Map<String, dynamic>>> queuedCrudOps(PowerSyncDatabase db) async {
  final rows = await db.getAll('SELECT data FROM ps_crud ORDER BY id');
  return [
    for (final r in rows)
      jsonDecode(r['data'] as String) as Map<String, dynamic>,
  ];
}
