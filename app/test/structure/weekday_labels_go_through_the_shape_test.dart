/// Structural test: a day's NAME, and the week a date belongs to, come from
/// `WeekShape` and from nowhere else.
///
/// `plan_entry.day_of_week` is an offset from the week's own first day, and
/// that day is a household setting. So `kWeekdayShort[dayOfWeek]` is right
/// only while the household starts its week on Monday, and wrong — silently,
/// by one name per row — the moment it doesn't. It was written that way at
/// fourteen call sites, which is what makes this a bug class rather than a
/// careful edit: every future surface that prints a day would re-open it.
///
/// Three shapes are refused anywhere but `core/week_shape.dart`:
///
/// 1. indexing the weekday tables (`kWeekdayShort[…]` / `kWeekdayFull[…]`),
/// 2. `mondayOf` / `weekKeyOf` — the retired pair that hard-coded Monday,
/// 3. `weekday - 1`, which is `mondayOf`'s arithmetic written out by hand.
///
/// The fix for a hit is always the same: take the `WeekShape` the surface
/// already has (or read `weekShapeProvider`) and call `labelShort`,
/// `labelFull`, `weekStartOf`, `keyOf` or `offsetOf`.
///
/// String-level, like every guard here: comments and string literals are
/// blanked first, so prose about the rule can neither trip it nor silence it.
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../helpers/source_scan.dart';

/// The one file allowed to index the tables and to do the arithmetic.
const _shapeFile = 'lib/core/week_shape.dart';

/// What is refused, and what to do instead.
const _refused = <String, String>{
  'kWeekdayShort[': 'call shape.labelShort(offset)',
  'kWeekdayFull[': 'call shape.labelFull(offset)',
  'mondayOf(': 'call shape.weekStartOf(date) — mondayOf is retired',
  'weekKeyOf(': 'call shape.keyOf(date), or isoDateOf for a week start',
  'weekday - 1': 'call shape.offsetOf(date)',
};

void main() {
  test('weekday names and week keys go through WeekShape', () {
    final hits = <String>[];
    for (final file in dartFiles(Directory('lib'))) {
      final path = file.path;
      if (path == _shapeFile) continue;
      final source = blankNonCode(file.readAsStringSync());
      for (final entry in _refused.entries) {
        var at = source.indexOf(entry.key);
        while (at >= 0) {
          hits.add(
            '$path:${lineOf(source, at)}: '
            '${entry.key.trim()} — ${entry.value}',
          );
          at = source.indexOf(entry.key, at + 1);
        }
      }
    }
    expect(
      hits,
      isEmpty,
      reason:
          "A day is named, and a week is keyed, by the household's WeekShape "
          '($_shapeFile). These read a Monday-first table with an offset that '
          'need not count from Monday:\n${hits.join('\n')}',
    );
  });

  test('the weekday tables are still ISO-ordered, seven long', () {
    // The shape maps an offset onto these by rotating the index, so the
    // ordering is load-bearing: a reordered table would move every label by
    // the same amount and stay quietly plausible.
    final words = File('lib/core/words.dart').readAsStringSync();
    expect(
      words,
      contains(
        "const kWeekdayShort = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', "
        "'Sat', 'Sun'];",
      ),
    );
    expect(words.contains("'Monday',\n  'Tuesday',"), isTrue);
    expect(words.contains("'Saturday',\n  'Sunday',\n];"), isTrue);
  });
}
