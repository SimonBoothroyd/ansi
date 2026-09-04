/// The invariant behind `hostContextOf` / `container.write` in
/// `lib/shared/write.dart`: **after a view awaits a sheet, dialog or prompt,
/// nothing goes through the widget's `ref`.**
///
/// Why it is mechanical: every list here is a viewport, a sheet's keyboard
/// shrinks it on a phone, and the row that opened the sheet can be unmounted
/// by the time the user confirms. Riverpod 3 throws on a `WidgetRef` used
/// after that (owner report 2026-09-03 #1 — a review pick silently lost), and
/// the `context.mounted` bail that avoids the throw drops the write instead.
/// The fix is one shape — capture `ProviderScope.containerOf(context)` and
/// `hostContextOf(context)` BEFORE the await, go through them after — and a
/// shape is exactly what a paragraph fails to hold and a scan holds.
///
/// **What it checks.** In every `.dart` under a feature's widget-bearing
/// directories (everything but `domain/` and `data/`) and under
/// `lib/shared`, for each `await show…(` / `await promptForText(` /
/// `await _refuse(` / `await _confirm…(` (an awaited modal), any `ref.read(`,
/// `ref.watch(`, `ref.write(`, `ref.writeOk(` or `ref.listen(` that follows it
/// **inside the same function body** is a violation. The fix shape —
/// `ProviderScope.containerOf(context, listen: false)` + `hostContextOf`
/// captured before the await — has no `ref` after the await at all.
///
/// **How "same function body" is decided**, honestly: by brace depth. The
/// await sits at some depth; the body it belongs to is the span from the most
/// recent brace that opened that depth to the brace that closes it. A `ref.`
/// later in that span — including inside a closure declared there, which runs
/// later still — counts. Line comments and simple string literals are blanked
/// first so prose cannot trip it.
///
/// **What it can be defeated by:** a `ref` aliased into another name, braces
/// inside a multi-line string, an awaited modal opened through a helper whose
/// name does not start with `show`/`prompt`/`_refuse`/`_confirm`. It stops the
/// ordinary omission, not a determined author — the same reach as
/// `no_bare_repo_write_test.dart`, and stated for the same reason.
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

final _awaitedModal = RegExp(
  r'\bawait\s+(?:show\w*|promptForText|_refuse|_confirm\w*)\s*(?:<[^<>()]*>)?\s*\(',
);
final _refUse = RegExp(
  r'\bref\.(?:read|watch|write|writeOk|listen)\s*(?:<[^<>()]*>)?\s*\(',
);

/// Blanks `//` comments and the contents of simple single-line string
/// literals, keeping every other character (and so every offset) in place.
String _blank(String source) {
  final out = StringBuffer();
  var i = 0;
  while (i < source.length) {
    final c = source[i];
    if (c == '/' && i + 1 < source.length && source[i + 1] == '/') {
      while (i < source.length && source[i] != '\n') {
        out.write(' ');
        i++;
      }
      continue;
    }
    if (c == "'" || c == '"') {
      final quote = c;
      out.write(quote);
      i++;
      while (i < source.length && source[i] != quote && source[i] != '\n') {
        // An escape and the character it escapes are both blanked, so an
        // escaped quote cannot end the literal early.
        final skip = source[i] == r'\' && i + 1 < source.length ? 2 : 1;
        out.write(' ' * skip);
        i += skip;
      }
      if (i < source.length) {
        out.write(source[i]);
        i++;
      }
      continue;
    }
    out.write(c);
    i++;
  }
  return out.toString();
}

/// Every directory under `lib/features/` that can hold a widget: a feature's
/// subdirectories except `domain/` and `data/`, which are pure Dart and SQL.
///
/// Derived from the tree rather than listed, so a new feature — or a second
/// widget directory beside `presentation/`, the way `ingredients/barcode/` is
/// — is scanned the day it appears rather than the day someone remembers.
List<Directory> _widgetDirs() =>
    Directory('lib/features')
        .listSync()
        .whereType<Directory>()
        .expand((feature) => feature.listSync().whereType<Directory>())
        .where(
          (d) => !const {'domain', 'data'}.contains(d.path.split('/').last),
        )
        .toList()
      ..sort((a, b) => a.path.compareTo(b.path));

/// Brace depth at every offset of [source] (depth AFTER the character).
List<int> _depths(String source) {
  final depths = List<int>.filled(source.length, 0);
  var d = 0;
  for (var i = 0; i < source.length; i++) {
    final c = source[i];
    if (c == '{') d++;
    if (c == '}') d--;
    depths[i] = d;
  }
  return depths;
}

/// The `ref.` uses that follow an awaited modal inside its function body, as
/// `line:col` strings, for one file's [source].
List<String> violationsIn(String source) {
  final text = _blank(source);
  final depths = _depths(text);
  final found = <String>[];
  for (final m in _awaitedModal.allMatches(text)) {
    final at = m.start;
    final depth = depths[at];
    // The body: back to the brace that opened this depth …
    var start = at;
    while (start > 0 && depths[start - 1] >= depth) {
      start--;
    }
    // … and forward to the brace that closes it.
    var end = at;
    while (end < text.length && depths[end] >= depth) {
      end++;
    }
    for (final r in _refUse.allMatches(text.substring(at, end))) {
      final offset = at + r.start;
      final line = '\n'.allMatches(text.substring(0, offset)).length + 1;
      final col = offset - text.lastIndexOf('\n', offset);
      found.add('$line:$col');
    }
  }
  return found;
}

void main() {
  test('the scan catches the shape it exists for, and accepts the fix', () {
    const bad = '''
Future<void> f(BuildContext context, WidgetRef ref) async {
  final ok = await showAnsiDialog<bool>(context: context, builder: b);
  if (!(ok ?? false) || !context.mounted) return;
  await ref.write(context, 'delete it', () => repo.delete());
}
''';
    expect(violationsIn(bad), ['4:9']);

    const fixed = '''
Future<void> f(BuildContext context, WidgetRef ref) async {
  final repo = ref.read(repoProvider);
  final container = ProviderScope.containerOf(context, listen: false);
  final host = hostContextOf(context);
  final ok = await showAnsiDialog<bool>(context: context, builder: b);
  if (!(ok ?? false)) return;
  await container.write(host, 'delete it', () => repo.delete());
}
''';
    expect(violationsIn(fixed), isEmpty);

    // A `ref` in a DIFFERENT function after the await's function closes is
    // not the await's.
    const neighbour = '''
Future<void> f(BuildContext context) async {
  await showAnsiSheet<void>(context: context, builder: b);
}
void g(WidgetRef ref) {
  ref.read(repoProvider); // "a comment with await showX( in it"
}
''';
    expect(violationsIn(neighbour), isEmpty);
  });

  test('no view reads through ref after an awaited modal', () {
    final files = [
      ..._widgetDirs().expand(
        (d) => d
            .listSync(recursive: true)
            .whereType<File>()
            .where(
              (f) =>
                  f.path.endsWith('.dart') &&
                  !f.path.endsWith('.g.dart') &&
                  !f.path.endsWith('.freezed.dart'),
            ),
      ),
      ...Directory(
        'lib/shared',
      ).listSync().whereType<File>().where((f) => f.path.endsWith('.dart')),
    ]..sort((a, b) => a.path.compareTo(b.path));
    expect(files, isNotEmpty);

    final violations = <String>[];
    for (final file in files) {
      for (final v in violationsIn(file.readAsStringSync())) {
        violations.add('${file.path}:$v');
      }
    }
    expect(
      violations,
      isEmpty,
      reason:
          'a `ref` used after an awaited sheet/dialog/prompt — capture '
          '`ProviderScope.containerOf(context, listen: false)` and '
          '`hostContextOf(context)` before the await and go through them '
          '(lib/shared/write.dart):\n${violations.join('\n')}',
    );
  });
}
