/// The invariant behind every comment in `lib/`: **a comment says what the
/// code is, not how it got here.**
///
/// The prose in this app carries real weight — it explains rulings, invariants
/// and the reasons a shape is the shape it is, and that is worth keeping. What
/// rots is the *transcript* around it: the plan number a decision was made
/// under, the letter it was filed as, the date it was ruled on, the board
/// version it amended, the memory note an agent read it from, and the sentence
/// describing what the code used to do before someone fixed it.
///
/// All of that is true on the day it is written and misleading a month later,
/// because none of it is reachable from the file. A reader cannot open `plan
/// 0025 D3`; git and `docs/exec-plans/` can. So the history goes there, and the
/// comment keeps the rule the history was arguing for. `app/AGENTS.md`
/// § Code style states it in one sentence; this test is why the sentence holds.
///
/// **`lib/` only.** `integration_test/` is exempt for now: a smoke file's
/// `expect(reason:)` legitimately names the decision a failing leg belongs to,
/// and separating those from its ordinary comments is a second pass. `test/`
/// is Lane D's and is not scanned here either.
///
/// **What it can be defeated by**, stated plainly because a regex over source
/// text should be honest about its reach:
///
/// - **Trailing comments are not scanned.** Only lines whose first non-space
///   characters are `//` are read, so `foo(); // plan 0025 D3` passes. That is
///   deliberate: a URL or a string holding `//` would otherwise be read as a
///   comment, and false failures teach people to add allow-list entries.
/// - **`/* … */` blocks are not scanned.** The codebase does not use them.
/// - **Only the named patterns.** Decision letters (`D4b`, `U-D1`, `E7`) are
///   NOT matched: `D3`, `E5` and `G1` also occur as ordinary text and as real
///   identifiers, and a check that cries wolf is worse than no check. They are
///   removed by hand and kept out by review.
/// - **Paraphrase passes.** "It once did X" reads as history and is not in the
///   list. The list holds the phrasings that actually accumulated.
///
/// Generated sources (`*.g.dart`, `*.freezed.dart`) are skipped: their comments
/// are the generator's, not ours.
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// One banned shape: what it matches, and what to write instead.
typedef _Rule = ({String name, RegExp pattern, String instead});

const _instead = (
  backlink:
      'state the fact itself. A `[[mise-…]]` note is readable by one agent '
      'on one machine; the sentence it holds is readable by everyone.',
  date:
      'a comment is not a changelog. If the date matters, it is in git blame '
      'and in the plan; if it does not, it is noise that ages.',
  plan:
      'name the rule, not the ruling. The plan is in docs/exec-plans/ and '
      'nothing in lib/ can link to it.',
  review:
      'say what is true of the code. Who agreed to it, and where, is history.',
  history:
      'describe the code as it is. What it used to do belongs in the commit '
      'that changed it — where a reader can also see the diff.',
  board:
      'a board version numbers a design pass, not the app. Say what the '
      'surface does now.',
  code:
      'delete it. Commented-out code is a claim that something might come '
      'back, which git already answers better.',
);

/// Tier 1 — hard fail. Each pattern matched a real, repeated habit before it
/// was swept; none of them has a legitimate use in `lib/`.
final _rules = <_Rule>[
  (
    name: 'a memory backlink',
    pattern: RegExp(r'\[\[[a-z0-9-]+\]\]'),
    instead: _instead.backlink,
  ),
  (
    name: 'a date',
    pattern: RegExp(r'\b20\d\d-\d\d-\d\d\b'),
    instead: _instead.date,
  ),
  (
    name: 'a plan number',
    pattern: RegExp(r'\bplan[ -]\d{4}\b', caseSensitive: false),
    instead: _instead.plan,
  ),
  (
    name: 'review-speak',
    pattern: RegExp(
      'owner report|signed off|per review|post-review',
      caseSensitive: false,
    ),
    instead: _instead.review,
  ),
  (
    name: 'a history phrase',
    pattern: RegExp(
      r'\b(used to|previously|was broken|changed from|Retired here)\b',
    ),
    instead: _instead.history,
  ),
  (
    name: 'a board version',
    pattern: RegExp(
      r'\b(Library|Navigation|Week|Import|Editor) v[23]\b',
      caseSensitive: false,
    ),
    instead: _instead.board,
  ),
  (
    name: 'commented-out code',
    pattern: RegExp(r'^\s*//\s*(final|const|return|if\s*\(|await )\b'),
    instead: _instead.code,
  ),
];

/// Every hand-written Dart file under `lib/`.
List<File> _sources() =>
    Directory('lib')
        .listSync(recursive: true)
        .whereType<File>()
        .where(
          (f) =>
              f.path.endsWith('.dart') &&
              !f.path.endsWith('.g.dart') &&
              !f.path.endsWith('.freezed.dart'),
        )
        .toList()
      ..sort((a, b) => a.path.compareTo(b.path));

/// `(1-based line number, text)` for every whole-line comment in [source].
///
/// A line qualifies when its first non-space characters are `//`, which covers
/// `//`, `///` and `////` alike. See the blind spots above for what this misses
/// on purpose.
Iterable<(int, String)> _commentLines(String source) sync* {
  final lines = source.split('\n');
  for (var i = 0; i < lines.length; i++) {
    if (lines[i].trimLeft().startsWith('//')) yield (i + 1, lines[i]);
  }
}

void main() {
  late final List<File> sources;
  late final int commentLineCount;

  setUpAll(() {
    sources = _sources();
    commentLineCount = sources.fold(
      0,
      (n, f) => n + _commentLines(f.readAsStringSync()).length,
    );
  });

  test('the scan actually reaches lib/', () {
    // Without this, a broken glob or a renamed directory turns the guard below
    // into a test that passes by scanning nothing.
    expect(
      sources.length,
      greaterThan(100),
      reason: 'only ${sources.length} sources found under lib/ — broken glob?',
    );
    expect(
      commentLineCount,
      greaterThan(1000),
      reason:
          'only $commentLineCount comment lines found — the comment detector '
          'stopped seeing comments',
    );
  });

  test('the patterns match what they claim to', () {
    // The rules are only worth their runtime if they still fire. Each is
    // proven against a line that should trip it, so a botched escape or a
    // dropped alternation fails here rather than passing silently over lib/.
    const samples = <String>[
      '/// see [[mise-forui-icons-not-unicode-glyphs]] for the rule',
      '/// Owner ruling, 2026-09-02 (was 5).',
      '/// The vocabulary manager (step 8.5, plan 0020 D8).',
      '/// Riverpod 3 throws on this (owner report 2026-09-03 #1).',
      '/// The names used to be joined into ONE chip label.',
      '/// Library v2 D1 deferred this route.',
      '  // final id = _uuid.v4();',
    ];
    expect(samples, hasLength(_rules.length));
    for (var i = 0; i < _rules.length; i++) {
      expect(
        _rules[i].pattern.hasMatch(samples[i]),
        isTrue,
        reason: '${_rules[i].name} no longer matches its own sample',
      );
    }
  });

  for (final rule in _rules) {
    test('no comment in lib/ carries ${rule.name}', () {
      final hits = <String>[];
      for (final file in sources) {
        for (final (line, text) in _commentLines(file.readAsStringSync())) {
          if (rule.pattern.hasMatch(text)) {
            hits.add('${file.path}:$line: ${text.trim()}');
          }
        }
      }
      expect(
        hits,
        isEmpty,
        reason:
            'A comment in lib/ carries ${rule.name}. A comment says what the '
            'code IS — see `app/AGENTS.md` § Code style.\n'
            'Instead: ${rule.instead}\n'
            'Do not add an allow-list here; rewrite the comment.\n\n'
            '${hits.join('\n')}',
      );
    });
  }
}
