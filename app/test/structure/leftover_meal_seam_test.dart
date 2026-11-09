/// The last release's leftover pointers and tables are read-only for this
/// one: `plan_entry.leftover_of`, `plan_entry.from_leftover`, `leftover`
/// and `batch_leftover` were carried over to cookings (0061) and are dropped
/// a release later.
///
/// The bug this holds is a write that brings a second truth back: a meal
/// pointed at a stored row the reader no longer reads, so the shop buys it
/// again and the fridge never shows it. So:
///
///  1. **nothing under `lib/` writes them**: no INSERT, UPDATE or SET of the
///     old tables and columns; and
///  2. **one file reads them**: the carry-over (`cooking_store.dart`), which
///     the release after this drops with the tables.
///
/// **What it can be defeated by**: SQL built by interpolation. It stops the
/// ordinary slip.
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../helpers/source_scan.dart';

/// The one reader allowed: the carry-over.
const _carryOver = 'lib/features/cook_plan/data/cooking_store.dart';

/// Describes the dropped write of an old queued row: names, never reads.
const _describer = 'lib/shared/dropped_write_subject.dart';

final _write = RegExp(
  r'(INSERT\s+INTO|UPDATE)\s+(leftover|batch_leftover)\b'
  r'|SET\s+[^;]*\b(leftover_of|from_leftover)\s*=',
  caseSensitive: false,
);

final _read = RegExp(
  r'\b(FROM|JOIN)\s+(leftover|batch_leftover)\b'
  r'|\bpe\.(leftover_of|from_leftover)\b',
  caseSensitive: false,
);

void main() {
  final files = dartFiles(Directory('lib'));

  test('nothing writes the old leftover tables or pointers', () {
    final offenders = <String>[];
    for (final f in files) {
      final source = blankComments(f.readAsStringSync());
      for (final m in _write.allMatches(source)) {
        offenders.add('${f.path}:${lineOf(source, m.start)}');
      }
    }
    expect(offenders, isEmpty);
  });

  test('only the carry-over reads them', () {
    final readers = <String>{};
    for (final f in files) {
      if (f.path.endsWith(_describer)) continue;
      final source = blankComments(f.readAsStringSync());
      if (_read.hasMatch(source)) readers.add(f.path);
    }
    expect(readers, {_carryOver});
  });
}
