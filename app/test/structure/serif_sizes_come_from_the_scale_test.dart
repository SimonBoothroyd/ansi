// Structural: a serif size is a role from the scale, never a number.
//
// `ansiSerif` takes a `size`, and for a long time every call site chose its
// own. One recipe name was therefore set at 14 in a book's index, 15 in the
// Library ledger, 16 in the planner's picker, 17 on the phone, 19 on a cook
// card and 24 in the wide Week — nobody decided that, it accumulated one
// literal at a time, and the owner read it as the app losing its voice. A
// number at a call site cannot be reviewed: it says how big this title is, not
// what kind of title it is, so the next screen to show the same thing has
// nothing to copy but a pixel.
//
// `AnsiType` (`lib/core/theme/ansi_theme.dart`) names the five roles instead —
// display, title, heading, row, small — each documented with the places it is
// used. This test holds the one rule that keeps them meaningful: outside the
// theme, the argument to a serif size is an `AnsiType`. There is no
// allow-list. A size that no role fits is a role the scale is missing, and the
// fix is a sixth constant with its sites written down, not a literal here.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// The one file allowed to write the numbers, relative to `app/`.
const _theScale = 'lib/core/theme/ansi_theme.dart';

/// `ansiSerif(size: 17`, `ansiSerifDelta(\n  size: 15.5` — the call and its
/// size argument, across whatever whitespace the formatter put between them.
final _literalSize = RegExp(r'ansiSerif(?:Delta)?\(\s*size:\s*[0-9]');

void main() {
  test('structural: serif sizes come from AnsiType, not from literals', () {
    expect(
      File(_theScale).existsSync(),
      isTrue,
      reason: '$_theScale holds the serif scale and is missing',
    );

    final offenders = <String>[];
    for (final entity in Directory('lib').listSync(recursive: true)) {
      if (entity is! File || !entity.path.endsWith('.dart')) continue;
      if (entity.path == _theScale) continue;
      final source = entity.readAsStringSync();
      for (final match in _literalSize.allMatches(source)) {
        final line = '\n'.allMatches(source.substring(0, match.start)).length;
        offenders.add(
          '${entity.path}:${line + 1}: '
          '${match.group(0)!.replaceAll(RegExp(r'\s+'), ' ')}…',
        );
      }
    }

    expect(
      offenders,
      isEmpty,
      reason:
          'a serif size is written as a number instead of a role. Pass '
          'AnsiType.display / .title / .heading / .row / .small — the role '
          'says what the title IS, and two screens showing the same thing '
          'then cannot drift apart:\n${offenders.join('\n')}',
    );
  });
}
