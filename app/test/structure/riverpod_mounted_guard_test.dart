/// Structural test: an autoDispose `@riverpod` notifier must not write `state`
/// after an `await` without an intervening `ref.mounted` check.
///
/// In Riverpod 3 a disposed notifier THROWS on `state =` — in release builds
/// too, not just debug. Every screen that can be backed out of mid-request has
/// this shape (`/import` most sharply: the extraction is a slow LLM call, and
/// leaving the screen disposes the controller while it is in flight), so the
/// bug is invisible until a user does the ordinary thing.
///
/// The right home for this rule is a custom_lint plugin, and the repo already
/// runs `custom_lint` — but only with `riverpod_lint`; there is no local lint
/// package to add a rule to, and standing one up drags a second analyzer
/// dependency into a pinned custom_lint/riverpod_lint pair. So this is the
/// structural approximation, in the same deliberately simple string-level style
/// as `core/sync/watch_coverage_test.dart`: it runs in CI on every change, and
/// it fails loudly on the shape it is looking for.
///
/// How it reads the source (and what it cannot see):
/// - `@riverpod class X extends _$X` is an AUTO-DISPOSE notifier;
///   `@Riverpod(keepAlive: true)` is not and is skipped — a kept-alive notifier
///   cannot be disposed under its own await.
/// - Each member body is scanned on its own. For every `state =` assignment, if
///   an `await` appears in the same body before it AND no `ref.mounted` appears
///   between that await and the assignment, it is a violation.
/// - Comments and string literals are blanked out first (see [blankNonCode]),
///   so prose about `await` or `ref.mounted` can neither trip nor silence it.
/// - It cannot follow a `state =` hidden behind a helper (`_set(...)`) called
///   after an await, and it takes `ref.mounted` anywhere after the await as a
///   guard rather than proving it guards THIS statement. Both are deliberate:
///   the check stays readable, and the shape it does catch is the one that has
///   actually shipped broken.
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../helpers/source_scan.dart';

/// An `@riverpod class Foo extends _$Foo` header. The lowercase annotation is
/// the auto-dispose one; `@Riverpod(keepAlive: true)` doesn't match.
final _autoDisposeNotifier = RegExp(
  r'@riverpod\s+class\s+(\w+)\s+extends\s+_\$\1\b',
);

/// The body of the block that starts at the first `{` at or after [from].
/// Returns (start, end) exclusive of the braces, or null at EOF.
({int start, int end})? _blockAfter(String source, int from) {
  final open = source.indexOf('{', from);
  if (open < 0) return null;
  var depth = 0;
  for (var i = open; i < source.length; i++) {
    if (source[i] == '{') depth++;
    if (source[i] == '}') {
      depth--;
      if (depth == 0) return (start: open + 1, end: i);
    }
  }
  return null;
}

/// The member bodies inside a class body — every brace-balanced block at the
/// class's own nesting level. Each is scanned independently, so an await in one
/// method can't be blamed on an assignment in another.
List<({int offset, String text})> _memberBodies(String classBody, int base) {
  final bodies = <({int offset, String text})>[];
  var i = 0;
  while (i < classBody.length) {
    final block = _blockAfter(classBody, i);
    if (block == null) break;
    bodies.add((
      offset: base + block.start,
      text: classBody.substring(block.start, block.end),
    ));
    i = block.end + 1;
  }
  return bodies;
}

final _stateWrite = RegExp(r'\bstate\s*=(?!=)');
final _await = RegExp(r'\bawait\b');
final _mounted = RegExp(r'\bref\.mounted\b');

void main() {
  test('no `state =` after an await without a ref.mounted guard', () {
    final files = dartFiles(Directory('lib'));
    expect(files, isNotEmpty, reason: 'no lib sources found — broken glob?');

    final violations = <String>[];
    var notifiersChecked = 0;

    for (final file in files) {
      final raw = file.readAsStringSync();
      final source = blankNonCode(raw);
      for (final m in _autoDisposeNotifier.allMatches(source)) {
        final body = _blockAfter(source, m.end);
        if (body == null) continue;
        notifiersChecked++;
        final classBody = source.substring(body.start, body.end);
        for (final member in _memberBodies(classBody, body.start)) {
          for (final write in _stateWrite.allMatches(member.text)) {
            final before = member.text.substring(0, write.start);
            final lastAwait = _await.allMatches(before).lastOrNull?.start ?? -1;
            if (lastAwait < 0) continue;
            final lastGuard =
                _mounted.allMatches(before).lastOrNull?.start ?? -1;
            if (lastGuard > lastAwait) continue;
            violations.add(
              '${file.path}:'
              '${lineOf(source, member.offset + write.start)} '
              'in ${m.group(1)} — `state =` after an await with no '
              '`ref.mounted` guard between them',
            );
          }
        }
      }
    }

    expect(
      notifiersChecked,
      greaterThan(0),
      reason: 'found no @riverpod notifiers — the pattern has drifted',
    );
    expect(
      violations,
      isEmpty,
      reason:
          'an autoDispose notifier writes state after an await; in Riverpod 3 '
          'that THROWS once the user leaves the screen mid-request. Guard it '
          'with `if (!ref.mounted) return;`:\n${violations.join('\n')}',
    );
  });
}
