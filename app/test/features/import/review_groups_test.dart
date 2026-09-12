/// **The review's sections** (plan 0034, fronts A and B) — the pure rules.
///
/// The payload's groups are the server's word about the page and never change.
/// These are the human's, holding flat line indexes, and the two rules that
/// matter are here: deleting a heading never loses a line, and a line minted
/// at review takes an index past the payload's last so nothing renumbers.
library;

import 'package:ansi/features/import/domain/review_groups.dart';
import 'package:flutter_test/flutter_test.dart';

import '_fixtures.dart';

/// Two named sections: two lines, then one.
final _twoGroups =
    reconPayload([reconLine('a'), reconLine('b'), reconLine('c')]).copyWith(
      groups: [
        reconPayload([
          reconLine('a'),
          reconLine('b'),
        ]).groups.single.copyWith(name: 'For the pasta'),
        reconPayload([
          reconLine('c'),
        ]).groups.single.copyWith(name: 'For the dressing'),
      ],
    );

void main() {
  test(
    'the starting sections mirror the payload, flat index for flat index',
    () {
      final groups = initialGroups(_twoGroups);
      expect(groups.map((g) => g.id), ['g0', 'g1']);
      expect(groups.map((g) => g.name), ['For the pasta', 'For the dressing']);
      expect(groups.map((g) => g.lines), [
        [0, 1],
        [2],
      ]);
    },
  );

  test('a payload with no groups still has somewhere to put a line', () {
    final groups = initialGroups(reconPayload(const []).copyWith(groups: []));
    expect(groups, hasLength(1));
    expect(groups.single.lines, isEmpty);
  });

  test('renaming stores the trimmed name; blank clears the heading', () {
    var groups = renameGroup(
      initialGroups(_twoGroups),
      'g0',
      '  For the sauce ',
    );
    expect(groups.first.name, 'For the sauce');
    groups = renameGroup(groups, 'g0', '   ');
    expect(groups.first.name, isNull);
    expect(groups.first.lines, [0, 1], reason: 'a rename touches no line');
  });

  group('deleting a heading NEVER deletes its lines', () {
    test('they move into the section above, after the ones already there', () {
      final groups = removeGroup(initialGroups(_twoGroups), 'g1');
      expect(groups, hasLength(1));
      expect(groups.single.name, 'For the pasta');
      expect(groups.single.lines, [0, 1, 2]);
    });

    test('deleting the FIRST sends them down, keeping them above', () {
      final groups = removeGroup(initialGroups(_twoGroups), 'g0');
      expect(groups, hasLength(1));
      expect(groups.single.name, 'For the dressing');
      expect(groups.single.lines, [0, 1, 2]);
    });

    test('the last section standing loses its heading instead — its lines '
        'would have nowhere to go', () {
      final one = initialGroups(reconPayload([reconLine('a')]));
      final groups = removeGroup(renameGroup(one, 'g0', 'Everything'), 'g0');
      expect(groups, hasLength(1));
      expect(groups.single.name, isNull);
      expect(groups.single.lines, [0]);
    });

    test('no index is lost across a delete, whichever one goes', () {
      final start = initialGroups(_twoGroups);
      for (final id in ['g0', 'g1']) {
        final after = removeGroup(start, id);
        expect([for (final g in after) ...g.lines]..sort(), [
          0,
          1,
          2,
        ], reason: 'deleting $id kept every line');
      }
    });
  });

  test('a section can be added, and it starts empty', () {
    final groups = addGroup(initialGroups(_twoGroups), id: 'g-new-0');
    expect(groups, hasLength(3));
    expect(groups.last.lines, isEmpty);
    expect(groups.last.name, isNull);
  });

  group('a minted line takes an index past the payload’s last', () {
    test('the first one is the payload’s line count', () {
      final groups = initialGroups(_twoGroups);
      expect(nextLineIndex(_twoGroups, groups), 3);
    });

    test('and each one after it is one higher — nothing is reused', () {
      var groups = initialGroups(_twoGroups);
      final minted = <int>[];
      for (var i = 0; i < 3; i++) {
        final index = nextLineIndex(_twoGroups, groups);
        minted.add(index);
        groups = addLineToGroup(groups, 'g1', index);
      }
      expect(minted, [3, 4, 5]);
      expect(groups.last.lines, [2, 3, 4, 5]);
    });

    test('a section deleted after a line was added to it keeps that line', () {
      var groups = initialGroups(_twoGroups);
      groups = addGroup(groups, id: 'g-new-0');
      groups = addLineToGroup(groups, 'g-new-0', 3);
      groups = removeGroup(groups, 'g-new-0');
      expect([for (final g in groups) ...g.lines], [0, 1, 2, 3]);
    });

    test('adding an index some section already holds is a no-op', () {
      final groups = initialGroups(_twoGroups);
      expect(addLineToGroup(groups, 'g1', 0), groups);
    });
  });

  group('moving a line', () {
    // Rows: 0 heading · 1 line 0 · 2 line 1 · 3 heading · 4 line 2.
    test('a line changes its POSITION and keeps its INDEX', () {
      final moved = moveReviewLine(initialGroups(_twoGroups), from: 2, to: 1);
      expect(moved.first.lines, [1, 0]);
      // The index is the line's identity — resolutions are keyed by it and
      // step chips point at it — so a reorder must leave it exactly alone.
      // Order and identity have stopped being the same number.
      expect([for (final g in moved) ...g.lines]..sort(), [0, 1, 2]);
    });

    test('a line dragged under another heading is filed there, index '
        'intact', () {
      final moved = moveReviewLine(initialGroups(_twoGroups), from: 1, to: 4);
      expect(moved.first.lines, [1]);
      expect(moved.last.lines, [2, 0]);
      expect(moved.first.name, 'For the pasta');
      expect(moved.last.name, 'For the dressing');
    });

    test('a section emptied by the move is kept', () {
      final moved = moveReviewLine(initialGroups(_twoGroups), from: 4, to: 1);
      expect(moved, hasLength(2));
      expect(moved.last.lines, isEmpty);
      expect(moved.last.name, 'For the dressing');
    });

    test('a minted line moves like any other, off the end of the payload', () {
      var groups = initialGroups(_twoGroups);
      groups = addLineToGroup(groups, 'g1', 3);
      // Rows now: 0 h · 1 line 0 · 2 line 1 · 3 h · 4 line 2 · 5 line 3.
      final moved = moveReviewLine(groups, from: 5, to: 1);
      expect(moved.first.lines, [3, 0, 1]);
      expect(moved.last.lines, [2]);
    });

    test('a heading is never what moves', () {
      final groups = initialGroups(_twoGroups);
      expect(moveReviewLine(groups, from: 3, to: 1), groups);
    });
  });
}
