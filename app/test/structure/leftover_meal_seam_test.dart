/// A meal eaten from a leftover names it one of two ways: a cooked batch
/// (`plan_entry.leftover_of`) or a fridge or freezer row
/// (`plan_entry.from_leftover`). Either way it is never cooked, bought or
/// costed again, and every derivation that passes over one must pass over the
/// other.
///
/// The bug this holds is the second column forgotten: a meal from the freezer
/// that the shop buys for again, on the one derivation nobody re-read. So:
///
///  1. **in SQL**, every clause that says `leftover_of IS NULL` sits beside a
///     `from_leftover IS NULL`, as many times in the same file; and
///  2. **in Dart**, nothing under `lib/` asks `leftoverOf` for null except
///     `PlanEntry.isFromLeftover` itself. A reader that means "was this meal
///     cooked here?" asks the getter.
///
/// **What it can be defeated by**: SQL built by interpolation, and a test of
/// the column through a local variable. It stops the ordinary omission.
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../helpers/source_scan.dart';

/// Where `PlanEntry.isFromLeftover` is defined: the one place allowed to ask.
const _getterIn = 'lib/features/planning/domain/planning.dart';

final _batchNull = RegExp(r'leftover_of\s+IS\s+NULL', caseSensitive: false);
final _rowNull = RegExp(r'from_leftover\s+IS\s+NULL', caseSensitive: false);
final _columnTest = RegExp(r'\.leftoverOf\s*[!=]=\s*null');

void main() {
  final files = dartFiles(Directory('lib'));

  test('every SQL pass over a batch leftover passes over a stored one', () {
    final offenders = <String>[];
    var clauses = 0;
    for (final f in files) {
      final source = blankComments(f.readAsStringSync());
      final batch = _batchNull.allMatches(source).length;
      final row = _rowNull.allMatches(source).length;
      clauses += batch;
      if (batch != row) {
        offenders.add('${f.path}: $batch × leftover_of, $row × from_leftover');
      }
    }
    // The week's read the cook plan and the shop share at least: a scan that
    // found none is broken.
    expect(clauses, greaterThanOrEqualTo(1));
    expect(offenders, isEmpty);
  });

  test('Dart asks isFromLeftover, never the leftoverOf column', () {
    final offenders = <String>[];
    for (final f in files) {
      if (f.path.endsWith(_getterIn)) continue;
      final source = blankNonCode(f.readAsStringSync());
      for (final m in _columnTest.allMatches(source)) {
        offenders.add('${f.path}:${lineOf(source, m.start)}');
      }
    }
    expect(offenders, isEmpty);
  });
}
