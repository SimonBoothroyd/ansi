/// Structural: no glyph-only control is a bare tap.
///
/// A control whose whole body is one mark — a `⋯`, a `−`, a fold chevron, a
/// trash can — has nothing to say to a mouse or a keyboard except what its tap
/// wrapper says for it. A `GestureDetector` says nothing: no ground under the
/// pointer, no focus ring, and (because Forui's tappable style defaults its
/// cursor to `defer`) not even an arrow that changes shape. That is the owner's
/// report — *most burger menu buttons show no response when hovering* — and it
/// was not one broken control, it was every one of them, because they were all
/// written the same way.
///
/// So the rule is structural rather than per-widget: a bare tap around a
/// glyph-only child fails the build, and the fix is `AnsiTap`
/// (`lib/shared/ansi_tap.dart`) or a Forui component that already carries the
/// same hover, ring and cursor — `FButton`, `FHeaderAction`, `FSidebarItem`,
/// `FTappable`.
///
/// **What counts as glyph-only.** A tap whose subtree draws an icon (an
/// `Icon(`,
/// or an `FLucideIcons.` handed to something that draws one) and no text at
/// all.
/// A tap around a row of words — a recipe title, an ingredient name, a chip
/// with
/// a label — is NOT caught: those read as doors on their own, they are usually
/// the whole width of a line, and grounding every one of them would light up
/// half a list under the pointer. They are welcome to use `AnsiTap` and several
/// now do; they are simply not required to.
///
/// The allow-list below is empty, and that is the state to keep it in. A glyph
/// that genuinely cannot take the shared style is a real thing — a white mark
/// on
/// a coloured band, say, where a herb-soft ground would swallow it — but it
/// needs a line here saying which one and why, not a quiet exception.
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../helpers/source_scan.dart';

/// Glyph-only bare taps that may stay, as `path:reason`.
///
/// Empty on purpose. Add a row only with the reason the shared style cannot
/// apply — never to get a change through.
const _allowed = <String, String>{};

/// The tap wrappers that carry no hover, ring or cursor of their own.
const _bareTaps = ['GestureDetector(', 'InkWell('];

void main() {
  test('structural: a glyph-only control is never a bare tap', () {
    final offenders = <String>[];

    for (final file in dartFiles(Directory('lib'))) {
      final source = file.readAsStringSync();
      // Comments and string literals blanked: prose about `GestureDetector`
      // in a doc comment is not a `GestureDetector`.
      final code = blankNonCode(source);

      for (final opener in _bareTaps) {
        var from = 0;
        while (true) {
          final at = code.indexOf(opener, from);
          if (at < 0) break;
          from = at + opener.length;

          final body = _balanced(code, at + opener.length - 1);
          if (body == null) continue;

          final drawsGlyph =
              body.contains('Icon(') || body.contains('FLucideIcons.');
          final drawsWords =
              body.contains('Text(') || body.contains('Text.rich');
          if (!drawsGlyph || drawsWords) continue;

          final where = '${file.path}:${lineOf(source, at)}';
          if (_allowed.containsKey(file.path)) continue;
          offenders.add(where);
        }
      }
    }

    expect(
      offenders,
      isEmpty,
      reason:
          'a glyph-only control is wrapped in a bare tap, so it answers '
          'neither a mouse nor a keyboard. Wrap it in AnsiTap '
          '(lib/shared/ansi_tap.dart), or hang it on a Forui component that '
          'already hovers and rings — FButton, FHeaderAction, FSidebarItem, '
          'FTappable:\n${offenders.join('\n')}',
    );
  });

  test('structural: the allow-list stays honest', () {
    for (final MapEntry(key: path, value: reason) in _allowed.entries) {
      expect(
        File(path).existsSync(),
        isTrue,
        reason: '$path is allow-listed and no longer exists — drop the row',
      );
      expect(
        reason.trim(),
        isNotEmpty,
        reason: '$path is allow-listed with no reason',
      );
    }
  });
}

/// The text from [open] (an index pointing at `(`) to its matching `)`, or null
/// if the parentheses never balance.
String? _balanced(String code, int open) {
  var depth = 0;
  for (var i = open; i < code.length; i++) {
    switch (code[i]) {
      case '(':
        depth++;
      case ')':
        depth--;
        if (depth == 0) return code.substring(open, i + 1);
    }
  }
  return null;
}
