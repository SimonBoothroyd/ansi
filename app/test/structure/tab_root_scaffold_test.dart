// Structural: a tab root never resizes for the keyboard on its own.
//
// The four tab screens each build an `FScaffold`, and since Navigation v2
// that scaffold sits INSIDE the shell's scaffold (`shared/ansi_tab_shell.dart`),
// which already shrinks the branch area by the keyboard inset. Forui's
// scaffold subtracts `MediaQuery.viewInsets.bottom` from its content whenever
// `resizeToAvoidBottomInset` is true (the default) — so two nested scaffolds
// subtract the same inset twice, and the inner one's list ends up a few lines
// tall. Android made it visible first (2026-09-03: the Cook tab cut off after
// the sign-in keyboard), because there the inset can outlive the keyboard.
//
// The rule: a tab root passes `resizeToAvoidBottomInset: false`; the shell owns
// the inset. Held here by reading the source, the way the modal and push rules
// are held, because nothing at compile time knows which scaffold is nested.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

const _tabRoots = [
  'lib/features/books/presentation/library_view.dart',
  'lib/features/planning/presentation/week_view.dart',
  'lib/features/cook_plan/presentation/cook_view.dart',
  'lib/features/shopping/presentation/shopping_view.dart',
];

void main() {
  test('structural: every tab root leaves the keyboard inset to the shell', () {
    final offenders = <String>[];
    for (final path in _tabRoots) {
      final source = File(path).readAsStringSync();
      // The root scaffold is the FIRST one the file builds. Three of the four
      // are wrapped rather than returned bare — the week tabs sit inside
      // `WeekInTheLocation`, which names the week on screen in the URL and
      // draws nothing of its own — so this looks for the scaffold, not for a
      // `return` in front of it.
      final first = source.indexOf('FScaffold(');
      expect(first, isNot(-1), reason: '$path should build its FScaffold');
      // The root scaffold's argument list runs to the first `child:`.
      final args = source.substring(first, source.indexOf('child:', first));
      if (!args.contains('resizeToAvoidBottomInset: false')) {
        offenders.add(path);
      }
    }
    expect(
      offenders,
      isEmpty,
      reason:
          'a tab root resizes for the keyboard on its own — the shell already '
          'does, so the inset is subtracted twice. Pass '
          'resizeToAvoidBottomInset: false on the root FScaffold of:\n'
          '${offenders.join('\n')}',
    );
  });
}
