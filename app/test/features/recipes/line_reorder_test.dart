/// The one rule both ingredient lists drag by: a flat list of heading rows and
/// line rows, where filing a line under another heading and reordering it
/// inside its own are the same move.
library;

import 'package:ansi/features/recipes/domain/line_reorder.dart';
import 'package:flutter_test/flutter_test.dart';

/// Two groups: `a b` under the first heading, `c` under the second.
///
/// The flat rows are then: 0 heading · 1 a · 2 b · 3 heading · 4 c.
List<List<String>> get _groups => [
  ['a', 'b'],
  ['c'],
];

void main() {
  test('the row arithmetic names every heading and every line', () {
    final groups = _groups;
    expect(headingRowOf(groups, 0), 0);
    expect(lineRowOf(groups, 0, 0), 1);
    expect(lineRowOf(groups, 0, 1), 2);
    expect(headingRowOf(groups, 1), 3);
    expect(lineRowOf(groups, 1, 0), 4);
    expect(lineRowCount(groups), 5);
  });

  test('a line moves inside its own group', () {
    // `b` (row 2) to the top of its group: with itself taken out, row 1.
    expect(moveLineRow(_groups, from: 2, to: 1), [
      ['b', 'a'],
      ['c'],
    ]);
  });

  test('a line dropped under another heading is filed under it', () {
    // `a` (row 1) past the second heading, which sits at row 2 once `a` is
    // out: the drop lands it as that section's first line.
    expect(moveLineRow(_groups, from: 1, to: 3), [
      ['b'],
      ['a', 'c'],
    ]);
    // …and one row further down is that section's second line.
    expect(moveLineRow(_groups, from: 1, to: 4), [
      ['b'],
      ['c', 'a'],
    ]);
  });

  test('a line moves back up, into the group above', () {
    expect(moveLineRow(_groups, from: 4, to: 1), [
      ['c', 'a', 'b'],
      <String>[],
    ]);
  });

  test('a group emptied by the move is KEPT, not swept', () {
    final after = moveLineRow(_groups, from: 4, to: 2);
    expect(after, hasLength(2), reason: 'the heading is the human’s');
    expect(after[1], isEmpty);
  });

  test('the value that comes out is the value that went in', () {
    // Identity, not equality: a move must never rebuild a line, because the
    // line’s id is what every method chip points at.
    final line = ['x'];
    final after = moveLineRow([
      [line],
      <List<String>>[],
    ], from: 1, to: 2);
    expect(identical(after[1].single, line), isTrue);
  });

  test('a heading is never the thing that moves', () {
    // Row 3 is the second heading. Nothing offers a handle on it, and the
    // rule refuses rather than trusting that.
    expect(moveLineRow(_groups, from: 3, to: 1), _groups);
    expect(moveLineRow(_groups, from: 0, to: 4), _groups);
    expect(moveLineRow(_groups, from: 99, to: 1), _groups);
  });

  test('a line dropped above the first heading lands at the top of the first '
      'group — there is nowhere else for it to be', () {
    expect(moveLineRow(_groups, from: 4, to: 0), [
      ['c', 'a', 'b'],
      <String>[],
    ]);
  });

  test('a move to where it already is changes nothing', () {
    expect(moveLineRow(_groups, from: 1, to: 1), _groups);
    expect(moveLineRow(_groups, from: 2, to: 2), _groups);
  });
}
