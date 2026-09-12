/// One note grammar: a line's note is printed by `noteSpans` and by nothing
/// else.
///
/// The rule is `Garlic · peeled and crushed` — the name, a middle dot in the
/// hairline, the note in muted italic — and the three surfaces that print a
/// line (the recipe page, the recipe editor's row, the import review's row)
/// had drifted into two of them: the page dropped the dot, the other two kept
/// it, and the same line read two ways on two screens. This scan is why they
/// cannot drift again: the separator exists as a literal in exactly one
/// function, so a fourth surface has to call that function to print a note at
/// all.
///
/// It is deliberately narrow — the two-space middle dot, not every `·` in
/// `lib` — because the dot is a perfectly good word separator elsewhere
/// ("measure pending sync", "optional · tap to include") and a guard that
/// flagged those would be turned off rather than obeyed.
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../helpers/source_scan.dart';

/// The one file allowed to spell the separator: `noteSpans` lives here.
const _home = 'lib/features/recipes/presentation/ingredient_line.dart';

/// The separator itself, as it is written in Dart source.
const _separator = "'  ·  '";

void main() {
  test('the note separator is written in exactly one place', () {
    final files = dartFiles(Directory('lib'));
    expect(files, isNotEmpty);

    final elsewhere = <String>[];
    var atHome = 0;
    for (final file in files) {
      // Comments blanked, string literals kept: the rule is about what the
      // code prints, and prose about the dot must not trip it.
      final source = blankComments(file.readAsStringSync());
      for (final match in _separator.allMatches(source)) {
        if (file.path == _home) {
          atHome++;
        } else {
          elsewhere.add('${file.path}:${lineOf(source, match.start)}');
        }
      }
    }

    expect(
      atHome,
      1,
      reason: 'the separator belongs to noteSpans in $_home, once',
    );
    expect(
      elsewhere,
      isEmpty,
      reason:
          'print a note through noteSpans (from $_home) rather than spelling '
          'the separator again',
    );
  });
}
