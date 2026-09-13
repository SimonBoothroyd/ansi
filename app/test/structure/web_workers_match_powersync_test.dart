/// The committed web binaries must be the ones this build's PowerSync wrote.
///
/// `web/` holds three files that are NOT source: two compiled workers and the
/// SQLite wasm, fetched once by `dart run powersync:setup_web`. Nothing
/// regenerates them — a `flutter pub upgrade` that moves `powersync_core`
/// leaves the old binaries sitting there, the build stays green, and the web
/// app talks to a sync worker from a different version. The failure that
/// causes is not a compile error; it is a device that syncs oddly, months
/// later, for no visible reason.
///
/// So this test reads the version the sync worker was compiled from — it
/// carries its own `powersync-dart-core/<version>` user-agent string — and
/// insists it is the version in `pubspec.lock`. When it fails, the fix is one
/// command, printed in the failure.
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// `dart run powersync:setup_web` writes exactly these into `web/`.
const _fetched = [
  'web/powersync_sync.worker.js',
  'web/powersync_db.worker.js',
  'web/sqlite3.wasm',
];

const _refresh =
    'Refresh them with:  cd app && dart run powersync:setup_web  '
    '(then commit web/).';

void main() {
  test('every fetched web binary is committed', () {
    for (final path in _fetched) {
      expect(
        File(path).existsSync(),
        isTrue,
        reason:
            '$path is missing — the web build cannot open a database '
            'without it. $_refresh',
      );
    }
  });

  test('the sync worker was compiled from the locked powersync_core', () {
    final locked = _lockedVersion('powersync_core');
    final worker = File('web/powersync_sync.worker.js').readAsStringSync();
    final stamped = RegExp(
      r'powersync-dart-core/(\d+\.\d+\.\d+[^\s"'
      r"'"
      r']*)',
    ).firstMatch(worker)?.group(1);

    expect(
      stamped,
      isNotNull,
      reason:
          'web/powersync_sync.worker.js carries no '
          'powersync-dart-core/<version> stamp. Either the worker is not a '
          'PowerSync build, or upstream stopped stamping it and this test '
          'needs a new way to read the version. $_refresh',
    );
    expect(
      stamped,
      locked,
      reason:
          'the committed sync worker is powersync_core $stamped, but '
          'pubspec.lock says $locked. A stale worker ships silently: the '
          'build is green and the browser syncs against a different '
          'protocol. $_refresh',
    );
  });
}

/// The version `pubspec.lock` pins [package] at.
///
/// Scanned rather than parsed: a lock file's entries are two-space-indented
/// blocks with the version last, and reading it this way keeps the test free
/// of a YAML dependency it would otherwise be the only user of.
String _lockedVersion(String package) {
  final lines = File('pubspec.lock').readAsLinesSync();
  final start = lines.indexOf('  $package:');
  expect(
    start,
    isNot(-1),
    reason:
        '$package is not in pubspec.lock — if PowerSync was removed, this '
        'test and the binaries in web/ should go with it.',
  );
  for (final line in lines.skip(start + 1)) {
    // The next entry started: this package has no version line, which a lock
    // file cannot actually produce, but a wrong answer is worse than a throw.
    if (!line.startsWith('    ')) break;
    final version = RegExp(r'^    version: "?([^"]+)"?$').firstMatch(line);
    if (version != null) return version.group(1)!;
  }
  fail('no version line for $package in pubspec.lock');
}
