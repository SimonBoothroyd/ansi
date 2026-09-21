/// Structural: a test never sleeps to wait for something. A fixed delay races
/// the thing it waits on; await the event itself (`twoEmissions`, a Completer).
/// `Duration.zero` only yields to the event loop and is allowed.
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../helpers/source_scan.dart';

/// Files whose delay IS the subject: a clock tick between two stamps, a stall
/// the client must time out on, a live query given time to close.
const _allowed = {
  'test/features/import/edge_import_failures_test.dart',
  'test/features/receipts/receipt_repository_test.dart',
  'test/features/recipes/coined_word_real_db_test.dart',
};

final _sleep = RegExp(r'Future(<\w+>)?\.delayed\((?!\s*Duration\.zero)');

void main() {
  test('structural: no test waits on a fixed delay', () {
    final offenders = <String>[];
    for (final file in dartFiles(Directory('test'))) {
      if (_allowed.contains(file.path)) continue;
      final source = blankNonCode(file.readAsStringSync());
      for (final match in _sleep.allMatches(source)) {
        offenders.add('${file.path}:${lineOf(source, match.start)}');
      }
    }
    expect(
      offenders,
      isEmpty,
      reason:
          'wait on the event, not the clock — see `twoEmissions` in '
          'test/helpers/test_db.dart:\n${offenders.join('\n')}',
    );
  });
}
