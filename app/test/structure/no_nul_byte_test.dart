/// No `.dart` file under `lib/` contains a literal NUL byte.
///
/// A NUL anywhere in a file makes BSD grep — macOS, so every local `make` gate
/// and every agent's search — call the whole file binary and report nothing,
/// silently. Two sort sentinels written as raw `\x00` once hid the app's
/// largest view and 798 lines of `shopping/domain/` from every `grep -r`,
/// including the domain-purity check that greps for `package:flutter` in
/// `domain/`: an illegal import there would have passed unseen. The sentinel
/// value is fine; writing it as the escape `\u0000` keeps the source ASCII and
/// the file greppable.
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('no .dart file under lib/ contains a NUL byte', () {
    final offenders = <String>[];
    var scanned = 0;

    for (final file in Directory('lib').listSync(recursive: true)) {
      if (file is! File || !file.path.endsWith('.dart')) continue;
      scanned++;
      final bytes = file.readAsBytesSync();
      final at = bytes.indexOf(0);
      if (at < 0) continue;
      final line = bytes.take(at).where((b) => b == 0x0a).length + 1;
      offenders.add('${file.path}:$line');
    }

    expect(scanned, greaterThan(0), reason: 'nothing scanned — broken glob?');
    expect(
      offenders,
      isEmpty,
      reason:
          'a NUL byte in source turns the file binary for grep, which hides it '
          'from the CI purity check and from every search. Write the escape '
          r"'\u0000' instead of the raw byte:"
          '\n${offenders.join('\n')}',
    );
  });
}
