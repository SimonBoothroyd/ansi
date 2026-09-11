/// Structural test: an amount is printed by `core/units/number_format.dart`,
/// never by a `toStringAsFixed` somewhere else.
///
/// A cook says `2/3 cup`, not `0.67 cup`, and the rule that turns one into
/// the other is `formatAmount` — with `formatNumber` under it for the figures
/// no kitchen says in halves. Both live in one file, under the units, because
/// the surfaces that print a number run across every feature: a recipe line,
/// a method chip, a measure label, a batch multiplier, a portion count. The
/// moment a second file rounds its own number, half the app says `0.67` and
/// half says `2/3`, and the difference reads as two different values.
///
/// **What it checks.** Every `.dart` file under `lib/` (generated sources
/// aside), with comments and string literals blanked first ([blankNonCode]),
/// so prose about the trap can neither trip it nor silence it. A
/// `toStringAsFixed` anywhere outside the two files that ARE a printing rule
/// fails the test, naming `file:line`.
///
/// **The two exceptions, and why each is one.** `number_format.dart` holds
/// the amount rule itself. `macros_format.dart` holds the *other* rounding
/// rule this app has — energy whole, grams to one decimal — which is not an
/// amount rule and must not become one: `0.5 g` of protein is a reading off a
/// pack, and `1/2 g` would be a sentence nobody writes. Anything else that
/// wants to round has to say which of those two rules it is, in that rule's
/// own file.
///
/// **What it can be defeated by**, stated plainly because a scan over source
/// text should be honest about its reach: `toStringAsPrecision`, a manual
/// `(v * 100).round() / 100`, or an interpolation of a raw double. It stops
/// the ordinary omission — someone reaching for the obvious method — not a
/// determined author.
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../helpers/source_scan.dart';

/// The files allowed to round a number, and the rule each of them holds.
const _ruleHolders = <String, String>{
  'lib/core/units/number_format.dart': 'the amount rule itself',
  'lib/features/ingredients/presentation/macros_format.dart':
      'the macro rounding rule — energy whole, grams to one decimal',
};

/// The offsets in [text] where `toStringAsFixed` is called.
List<int> roundingCallsIn(String text) => [
  for (final m in RegExp(r'\.toStringAsFixed\s*\(').allMatches(text)) m.start,
];

void main() {
  test('the scan catches the shape it exists for, and accepts the fix', () {
    const bad = '''
String label(double amount) {
  final text = amount.toStringAsFixed(2);
  return text;
}
''';
    expect(roundingCallsIn(blankNonCode(bad)), hasLength(1));

    const fixed = '''
String label(double amount) {
  final text = formatAmount(amount);
  return text;
}
''';
    expect(roundingCallsIn(blankNonCode(fixed)), isEmpty);

    // Prose about the trap neither trips it nor silences it.
    const prose = '''
/// Never amount.toStringAsFixed(2) — see number_format.dart.
const hint = 'toStringAsFixed(2)';
''';
    expect(roundingCallsIn(blankNonCode(prose)), isEmpty);
  });

  test('the rule holders exist, so the allow-list cannot rot silently', () {
    for (final path in _ruleHolders.keys) {
      expect(File(path).existsSync(), isTrue, reason: '$path has moved');
    }
  });

  test('no file in lib/ rounds an amount for itself', () {
    final files = dartFiles(Directory('lib'));
    expect(files, isNotEmpty, reason: 'no lib sources found — broken glob?');

    final violations = <String>[];
    for (final file in files) {
      if (_ruleHolders.containsKey(file.path)) continue;
      final text = blankNonCode(file.readAsStringSync());
      for (final at in roundingCallsIn(text)) {
        violations.add('${file.path}:${lineOf(text, at)}');
      }
    }

    expect(
      violations,
      isEmpty,
      reason:
          'an amount rounded outside `core/units/number_format.dart`. Print '
          'it with formatAmount (or formatQuantity, for one that may be '
          'absent) so a third of a cup reads 1/3 here as it does everywhere '
          'else:\n${violations.join('\n')}',
    );
  });
}
