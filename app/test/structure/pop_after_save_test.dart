/// Structural test: a sheet that awaits a write before it closes pops through
/// `popIfCurrent` (`lib/shared/ansi_modals.dart`), never a bare
/// `Navigator.pop`.
///
/// A save awaits its write and then pops. Two taps in one frame both reach the
/// pop, and the second takes the page under the sheet with it: go_router
/// asserts on popping its last page and the app goes black (the confirm
/// sheet's double-tapped Add did exactly that, and inserted the meal twice).
/// `popIfCurrent` pops only a route still mounted and on top.
///
/// How it reads the source: each `async` body is scanned on its own, with
/// comments and string literals blanked ([blankNonCode]). A
/// `Navigator.of(...).pop(`, `Navigator.pop(` or `context.pop(` after the
/// statement holding the body's first `await` is a violation. A pop inside
/// the awaited expression itself (a dialog's own buttons) is not after it.
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../helpers/source_scan.dart';

final _asyncBody = RegExp(r'\basync\s*\{');
final _bareAwaitedPop = RegExp(
  r'Navigator\s*\.\s*of\s*\([^)]*\)\s*\.\s*pop\s*[<(]|'
  r'Navigator\s*\.\s*pop\s*[<(]|'
  r'\bcontext\s*\.\s*pop\s*[<(]',
);

/// The offset of the `;` that ends the statement running through [from].
int _statementEnd(String source, int from) {
  var depth = 0;
  for (var i = from; i < source.length; i++) {
    final c = source[i];
    if (c == '(' || c == '[' || c == '{') depth++;
    if (c == ')' || c == ']' || c == '}') depth--;
    if (c == ';' && depth <= 0) return i;
  }
  return source.length;
}

/// The end of the block whose `{` is at [open], exclusive.
int _blockEnd(String source, int open) {
  var depth = 0;
  for (var i = open; i < source.length; i++) {
    if (source[i] == '{') depth++;
    if (source[i] == '}') {
      depth--;
      if (depth == 0) return i;
    }
  }
  return source.length;
}

void main() {
  test('no save pops a sheet past popIfCurrent after its await', () {
    final hits = <String>[];
    for (final file in dartFiles(Directory('lib'))) {
      final raw = file.readAsStringSync();
      final code = blankNonCode(raw);
      for (final body in _asyncBody.allMatches(code)) {
        final open = code.indexOf('{', body.start);
        final end = _blockEnd(code, open);
        final text = code.substring(open, end);
        final firstAwait = RegExp(r'\bawait\b').firstMatch(text);
        if (firstAwait == null) continue;
        final after = _statementEnd(text, firstAwait.start);
        for (final pop in _bareAwaitedPop.allMatches(text)) {
          if (pop.start < after) continue;
          final at = open + pop.start;
          hits.add('${file.path}:${lineOf(raw, at)}');
        }
      }
    }
    expect(
      hits.toSet().toList(),
      isEmpty,
      reason:
          'a pop after an awaited write must go through popIfCurrent, so a '
          'second tap cannot pop the page under the sheet',
    );
  });
}
