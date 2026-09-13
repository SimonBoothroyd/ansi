// Structural: exactly one file under lib/ reads the viewport.
//
// `shared/ansi_layout.dart` asks how wide the window is, names the answer
// (compact · medium · expanded) and applies it structurally with `AnsiMeasure`.
// Nothing else may ask. A screen that measures itself becomes a second source
// of truth for "what is a phone": the breakpoints then live in two places, the
// caps drift apart (600 here, 700 there), and a wide-screen change has to be
// re-verified screen by screen instead of once.
//
// The three reads below are the ones that give a widget the window's size —
// `MediaQuery.sizeOf`, the older `MediaQuery.of(context).size`, and
// `LayoutBuilder`, which is the same question asked through constraints. Reads
// of the *insets* (`viewInsetsOf`, `paddingOf` — the keyboard and the home
// indicator) are not viewport reads and are deliberately not listed: they are
// about what is covering the screen, not how wide it is.
//
// There is no allow-list beyond the layout file itself, on purpose. If a screen
// genuinely needs the width, the fix is to give it a band from `AnsiLayout` —
// or to widen that file's vocabulary — not to add a row here.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// The one file allowed to ask, relative to `app/`.
const _theReader = 'lib/shared/ansi_layout.dart';

const _viewportReads = [
  'MediaQuery.sizeOf',
  'MediaQuery.of(context).size',
  'LayoutBuilder',
];

void main() {
  test('structural: only shared/ansi_layout.dart reads the viewport', () {
    expect(
      File(_theReader).existsSync(),
      isTrue,
      reason: "$_theReader is the app's one viewport reader and is missing",
    );

    final offenders = <String>[];
    for (final entity in Directory('lib').listSync(recursive: true)) {
      if (entity is! File || !entity.path.endsWith('.dart')) continue;
      if (entity.path == _theReader) continue;
      final lines = entity.readAsLinesSync();
      for (final (index, line) in lines.indexed) {
        for (final read in _viewportReads) {
          if (line.contains(read)) {
            offenders.add('${entity.path}:${index + 1}: ${line.trim()}');
          }
        }
      }
    }

    expect(
      offenders,
      isEmpty,
      reason:
          'the viewport is read outside $_theReader. Ask '
          'AnsiLayout.of(context) for a band, or sit the widget in an '
          'AnsiMeasure, instead of measuring here:\n${offenders.join('\n')}',
    );
  });
}
