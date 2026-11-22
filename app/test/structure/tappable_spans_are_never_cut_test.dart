/// A tappable span never sits in text that can be cut: past the ellipsis it is
/// neither drawn nor tappable, and nothing says it was there. The Shop's
/// optional names were doors nobody on a phone could see.
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../helpers/source_scan.dart';

/// The `Text.rich(…)` and `RichText(…)` calls in [code], each to its matching
/// bracket.
Iterable<(int, String)> _richTexts(String code) sync* {
  for (final call in RegExp(r'\b(Text\.rich|RichText)\(').allMatches(code)) {
    var depth = 1;
    var at = call.end;
    while (at < code.length && depth > 0) {
      if (code[at] == '(') depth++;
      if (code[at] == ')') depth--;
      at++;
    }
    yield (call.start, code.substring(call.start, at));
  }
}

void main() {
  test('text with a tappable span wraps', () {
    final offenders = <String>[];
    final dirs = [...widgetDirs(), Directory('lib/shared')];
    for (final file in dirs.expand(dartFiles)) {
      final code = blankNonCode(file.readAsStringSync());
      for (final (at, call) in _richTexts(code)) {
        if (!call.contains('recognizer:')) continue;
        if (call.contains('TextOverflow.') || call.contains('maxLines:')) {
          offenders.add('${file.path}:${lineOf(code, at)}');
        }
      }
    }
    expect(
      offenders,
      isEmpty,
      reason: 'let the text wrap, or move the door out of the sentence',
    );
  });
}
