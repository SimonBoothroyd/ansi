// Structural: only `core/sync/auth_events.dart` reads Supabase's auth stream.
//
// gotrue puts a refresh that could not reach the server on
// `onAuthStateChange` as an ERROR, and replays it to late listeners. A raw
// `.listen` on it without `onError` hands that error to the zone, and the zone
// shows the crash toast for nothing worse than being offline; a raw `.map`
// under a StreamProvider turns it into an AsyncError that blanks what the
// provider knew. `authEvents` notes the offline case, reports the rest and
// passes events through, so every listener goes through it.
//
// `onAuthStateChangeSync` is banned too: one door for the auth stream,
// whichever copy of it is read. Comments and strings are blanked first, so
// prose about the stream neither trips the guard nor silences it.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../helpers/source_scan.dart';

/// The one file allowed to read it, relative to `app/`.
const _theReader = 'lib/core/sync/auth_events.dart';

final _rawRead = RegExp(r'\.onAuthStateChange');

void main() {
  test('structural: only core/sync/auth_events.dart reads the auth stream', () {
    expect(
      File(_theReader).existsSync(),
      isTrue,
      reason: "$_theReader is the app's one auth-stream reader and is missing",
    );

    final offenders = <String>[];
    for (final file in dartFiles(Directory('lib'))) {
      if (file.path == _theReader) continue;
      final source = file.readAsStringSync();
      for (final m in _rawRead.allMatches(blankNonCode(source))) {
        offenders.add('${file.path}:${lineOf(source, m.start)}');
      }
    }

    expect(
      offenders,
      isEmpty,
      reason:
          'the auth stream is read outside $_theReader, where an offline '
          'refresh error reaches the crash toast. Listen to '
          'authEvents(auth, crashSink) instead:\n${offenders.join('\n')}',
    );
  });
}
