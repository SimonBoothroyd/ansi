/// Structural test: the words the app prints follow the copy rules.
///
/// The rules are short and easy to break one string at a time: a fragment,
/// not a sentence; no em dash and no semicolon, because each one joins two
/// thoughts that should be one, or two strings; no tap hint, because a control
/// that needs its gesture spelled out wants redesigning, not a caption; and no
/// "nothing is saved until …", because reassurance about a Save button is a
/// sentence nobody needed. `docs/exec-plans/active/0057-copy-pass.md` holds the
/// whole list and the table that applied it. This test is why the four rules a
/// scan can see keep holding after the pass.
///
/// **What it reads.** Every string literal in the files that build what a
/// person sees: each feature's widget directories (`presentation/`, and
/// `ingredients/barcode/` beside it), `shared/`, and every `domain/` folder,
/// because a domain file builds refusals, attention labels and notes too. A
/// Semantics label is a string like any other, so a screen reader's tap hint
/// fails here as a visible one does.
///
/// **What it skips**, each because no person reads it:
///
/// - `features/ask/domain/`: tool results read by the model, whose wording is
///   tuned for it.
/// - `features/share/page/`: the public page's HTML and CSS scaffolding.
/// - Developer text: an `assert`, anything thrown, a `StateError` or
///   `ArgumentError` built to be thrown later, `debugPrint` and log lines, and
///   a `toString` override.
/// - Comments, doc comments and generated sources.
///
/// **What it can be defeated by**, stated plainly: a dash or semicolon built
/// at runtime (`String.fromCharCode`), and a tap hint phrased another way
/// ("press to …"). It holds the four rules as written, not their spirit.
///
/// **The allowlist** is for a string that is right as it stands, each entry
/// naming its file, its text and why. Prefer rewriting the string by the rules
/// to adding a row.
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../helpers/source_scan.dart';

/// One banned shape in the printed text, and what to write instead.
///
/// The dash and the semicolon match only with text beside them: a mark on its
/// own is a placeholder (the `—` an empty amount prints) or a separator in a
/// key, and joins nothing.
typedef _Rule = ({String name, RegExp pattern, String instead});

final _rules = <_Rule>[
  (
    name: 'an em dash',
    pattern: RegExp(r'\S.*\u2014|\u2014.*\S', dotAll: true),
    instead:
        'split it into two short strings, or drop the half that explains. '
        'A dash joins two thoughts the screen should say one at a time.',
  ),
  (
    name: 'a semicolon',
    pattern: RegExp(r'\S.*;|;.*\S', dotAll: true),
    instead: 'one thought per string. A second one is a second short sentence.',
  ),
  (
    name: 'a tap hint',
    pattern: RegExp(r'\btap (to|for)\b', caseSensitive: false),
    instead:
        'drop it. A control that needs its gesture spelled out wants a '
        'redesign, and a screen reader already says what a button does.',
  ),
  (
    name: 'save reassurance',
    pattern: RegExp(
      r'nothing(’s|\x27s| is| gets) saved until',
      caseSensitive: false,
    ),
    instead: 'drop it. The Save button already says when something is saved.',
  ),
];

/// A string that is right as it stands. Its `text` is the literal as the scan
/// sees it, with each interpolation printed as `{}`.
typedef _Allowed = ({String file, String text, String why});

const _allowlist = <_Allowed>[
  (
    file: 'lib/shared/ansi_error_state.dart',
    text: 'Couldn’t load {} — {}',
    why:
        'the one-line form of the two-line error state: the dash stands for '
        'the line break between what failed and the mapped reason',
  ),
];

/// The directories whose strings a person reads, relative to `app/`.
List<Directory> _scannedDirs() => [
  ...widgetDirs().where((d) => !d.path.endsWith('share/page')),
  Directory('lib/shared'),
  ...Directory('lib/features')
      .listSync()
      .whereType<Directory>()
      .map((feature) => Directory('${feature.path}/domain'))
      .where((d) => d.existsSync() && !d.path.endsWith('ask/domain')),
];

/// One string literal: where it starts, the offset whose code decides whether
/// a person reads it (the outermost literal's start, for a string nested in
/// another's interpolation), and its text with each interpolation as `{}`.
typedef Literal = ({int start, int context, String text});

/// Every string literal in [source], and the source with comments and string
/// literals blanked to spaces (offsets kept).
///
/// A single left-to-right pass, like [blankNonCode], but one that also walks
/// into `${…}`: a string nested in an interpolation is a literal of its own,
/// and the braces and quotes inside one must not end the outer string early.
({List<Literal> literals, String code}) readLiterals(String source) {
  final literals = <Literal>[];
  final code = StringBuffer();
  var i = 0;

  // Skips a comment at [at], if one starts there, returning its end.
  int? comment(int at) {
    if (source.startsWith('//', at)) {
      final nl = source.indexOf('\n', at);
      return nl < 0 ? source.length : nl;
    }
    if (source.startsWith('/*', at)) {
      final close = source.indexOf('*/', at + 2);
      return close < 0 ? source.length : close + 2;
    }
    return null;
  }

  // The opener of a literal at [at] as (raw, quote run length), or null.
  (bool, String)? opener(int at) {
    var j = at;
    var raw = false;
    if ((source[j] == 'r' || source[j] == 'R') &&
        j + 1 < source.length &&
        (source[j + 1] == "'" || source[j + 1] == '"')) {
      // An identifier ending in r (`bar'`) is not a raw prefix.
      final before = at > 0 ? source[at - 1] : ' ';
      if (RegExp(r'[A-Za-z0-9_$]').hasMatch(before)) return null;
      raw = true;
      j++;
    }
    if (j >= source.length || (source[j] != "'" && source[j] != '"')) {
      return null;
    }
    final quote = source[j];
    final closer = source.startsWith(quote * 3, j) ? quote * 3 : quote;
    return (raw, closer);
  }

  // Reads the literal at [at] (its opener already known), recording it and
  // any literal nested in its interpolations. Returns the offset past it.
  late int Function(int at, int context) literal;

  // Reads interpolated code from [at] up to its matching `}`, returning the
  // offset past the brace.
  int interpolation(int at, int context) {
    var depth = 1;
    var k = at;
    while (k < source.length) {
      final end = comment(k);
      if (end != null) {
        k = end;
        continue;
      }
      if (opener(k) != null) {
        k = literal(k, context);
        continue;
      }
      if (source[k] == '{') depth++;
      if (source[k] == '}' && --depth == 0) return k + 1;
      k++;
    }
    return k;
  }

  literal = (at, context) {
    final (raw, closer) = opener(at)!;
    final text = StringBuffer();
    var k = at + (raw ? 1 : 0) + closer.length;
    while (k < source.length) {
      if (source.startsWith(closer, k)) {
        k += closer.length;
        break;
      }
      if (closer.length == 1 && source[k] == '\n') break; // unterminated
      final c = source[k];
      if (!raw && c == r'\' && k + 1 < source.length) {
        final next = source[k + 1];
        final unicode = RegExp(
          r'u\{([0-9a-fA-F]+)\}|u([0-9a-fA-F]{4})',
        ).matchAsPrefix(source, k + 1);
        if (next == 'u' && unicode != null) {
          final hex = unicode.group(1) ?? unicode.group(2)!;
          text.writeCharCode(int.parse(hex, radix: 16));
          k = unicode.end;
        } else {
          text.write(next == 'n' ? '\n' : next);
          k += 2;
        }
        continue;
      }
      if (!raw && c == r'$') {
        if (source.startsWith(r'${', k)) {
          k = interpolation(k + 2, context);
        } else {
          final name = RegExp(
            '[A-Za-z_][A-Za-z0-9_]*',
          ).matchAsPrefix(source, k + 1);
          k = name?.end ?? k + 1;
        }
        text.write('{}');
        continue;
      }
      text.write(c);
      k++;
    }
    literals.add((start: at, context: context, text: text.toString()));
    return k;
  };

  while (i < source.length) {
    final end = comment(i);
    if (end != null) {
      code.write(' ' * (end - i));
      i = end;
      continue;
    }
    if (opener(i) != null) {
      final end = literal(i, i);
      code.write(' ' * (end - i));
      i = end;
      continue;
    }
    code.write(source[i]);
    i++;
  }
  return (literals: literals, code: code.toString());
}

/// The calls whose string argument no person reads: developer text (an
/// assert, an error, a log line) and text for a machine (a pattern, the JSON
/// Ask's model reads).
final _notCopyCall = RegExp(
  r'(\bassert|\bdebugPrint|\bprint|\blog|\.log|\b[A-Z]\w*(Error|Exception)'
  r'|\bRegExp|\bjsonEncode)\s*$',
);

/// Whether the literal whose code context starts at [at] is text no person
/// reads: an argument to one of [_notCopyCall], a thrown value, or the body of
/// a `toString` override. [code] has comments and literals blanked.
bool isNotCopy(String code, int at) {
  // The open brackets around [at], innermost last, with the code before each.
  final open = <(String, int)>[];
  for (var k = 0; k < at; k++) {
    final c = code[k];
    if (c == '(' || c == '[' || c == '{') open.add((c, k));
    if ((c == ')' || c == ']' || c == '}') && open.isNotEmpty) {
      open.removeLast();
    }
  }
  for (final (bracket, k) in open) {
    final before = code.substring(k < 200 ? 0 : k - 200, k);
    if (bracket == '(' && _notCopyCall.hasMatch(before)) return true;
    if (bracket == '{' && RegExp(r'toString\(\)\s*$').hasMatch(before)) {
      return true;
    }
  }
  // The statement the literal sits in, back to the last `;`, `{` or `}`.
  final stop = code.substring(0, at).lastIndexOf(RegExp('[;{}]'));
  final statement = code.substring(stop + 1, at);
  return RegExp(r'\bthrow\b|toString\(\)\s*=>').hasMatch(statement);
}

/// `file:line: rule: text` for every literal in [files] that breaks a rule.
List<String> violationsIn(Iterable<File> files) {
  final hits = <String>[];
  for (final file in files) {
    final source = file.readAsStringSync();
    final (:literals, :code) = readLiterals(source);
    for (final lit in literals) {
      final allowed = _allowlist.any(
        (a) => a.file == file.path && a.text == lit.text,
      );
      if (allowed) continue;
      for (final rule in _rules) {
        if (!rule.pattern.hasMatch(lit.text)) continue;
        if (isNotCopy(code, lit.context)) continue;
        hits.add(
          '${file.path}:${lineOf(source, lit.start)}: ${rule.name}: '
          '${lit.text}',
        );
      }
    }
  }
  return hits;
}

void main() {
  late final List<File> files;
  setUpAll(() {
    files = {
      for (final dir in _scannedDirs())
        for (final f in dartFiles(dir)) f.path: f,
    }.values.toList()..sort((a, b) => a.path.compareTo(b.path));
  });

  test('the scan reaches the screens', () {
    expect(
      files.length,
      greaterThan(200),
      reason: 'only ${files.length} files scanned — broken glob?',
    );
    expect(
      files.any((f) => f.path.contains('ask/domain')),
      isFalse,
      reason: "Ask's tool results are model-facing and out of scope",
    );
    expect(
      files.any((f) => f.path.contains('share/page')),
      isFalse,
      reason: "the share page's scaffolding is not copy",
    );
  });

  test('the reader finds what a person reads, and skips what they do not', () {
    const source = r'''
/// A doc comment — with a dash; it is not copy.
Widget build() => Column(children: [
  Text('Saved — tap to undo'),
  Text("${count} left; ${names.map((n) => 'a $n — b').join(', ')}"),
  Semantics(label: 'optional · Tap for details'),
  Text('Nothing is saved until you tap Save'),
  Text('plain words'),
  Text(amount.isEmpty ? '—' : amount),
]);
void check() {
  assert(x > 0, 'x must be positive — always; check it');
  if (bad) throw StateError('bad — state');
  final e = ArgumentError('also — fine');
  debugPrint('dev; text');
  log('dev — text');
  final words = RegExp('[-–—;]');
  final json = jsonEncode({'note': 'for the model; not printed'});
}
@override
String toString() => 'Thing(a; b)';
String describe() {
  return 'thing; with — dash';
}
''';
    final (:literals, :code) = readLiterals(source);
    final printed = [
      for (final lit in literals)
        if (!isNotCopy(code, lit.context)) lit.text,
    ];
    expect(printed, [
      'Saved — tap to undo',
      'a {} — b',
      ', ',
      '{} left; {}',
      'optional · Tap for details',
      'Nothing is saved until you tap Save',
      'plain words',
      '—',
      'thing; with — dash',
    ]);

    String? broken(String text) => [
      for (final rule in _rules)
        if (rule.pattern.hasMatch(text)) rule.name,
    ].firstOrNull;
    expect(broken('Saved — tap to undo'), 'an em dash');
    expect(broken('{} left; {}'), 'a semicolon');
    expect(broken('optional · Tap for details'), 'a tap hint');
    expect(broken('Nothing is saved until you tap Save'), 'save reassurance');
    expect(broken('plain words'), isNull);
    expect(broken('—'), isNull, reason: 'a lone dash is a placeholder');
    expect(broken(';'), isNull, reason: 'a lone semicolon is a separator');
    expect(broken(' — {}'), 'an em dash', reason: 'it joins a value on');
    expect(broken('Sun – Sat'), isNull, reason: 'an en dash is a range');
  });

  test('every allowlisted string is still there', () {
    for (final entry in _allowlist) {
      final file = File(entry.file);
      expect(file.existsSync(), isTrue, reason: '${entry.file} has moved');
      final texts = readLiterals(
        file.readAsStringSync(),
      ).literals.map((l) => l.text);
      expect(
        texts,
        contains(entry.text),
        reason:
            '${entry.file} no longer prints "${entry.text}". Remove its '
            'allowlist row.',
      );
    }
  });

  test('no printed string breaks the copy rules', () {
    final hits = violationsIn(files);
    expect(
      hits,
      isEmpty,
      reason:
          'A string a person reads breaks the copy rules '
          '(docs/exec-plans/active/0057-copy-pass.md). Rewrite it:\n'
          '${[for (final r in _rules) '- ${r.name}: ${r.instead}'].join('\n')}'
          '\n\n${hits.join('\n')}',
    );
  });
}
