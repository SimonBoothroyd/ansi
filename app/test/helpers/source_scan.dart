/// The reading half every structural guard under `test/structure/` shares:
/// which files to open, how to blank out everything that isn't code, and how
/// to name the line a match landed on.
///
/// The guards themselves are string-level by design — they run in CI on every
/// change and fail loudly on one shape each — but they were four separate
/// re-implementations of this reading at three fidelity levels, and the
/// weakest of them truncated a line at a `//` that lived inside a string
/// literal. One implementation, at the strongest fidelity, is what makes each
/// guard's own rule the only thing left to read in it.
library;

import 'dart:io';

/// Blanks comments and string literals to spaces in one left-to-right pass,
/// keeping every offset stable so reported positions still line up with the
/// file.
///
/// A single pass (rather than two regex sweeps, or a line-level `indexOf`) is
/// what makes it safe both ways round: a `//` inside a string literal is not a
/// comment, and an apostrophe inside a comment does not open a string. Prose
/// about the very shape a guard hunts for can therefore neither trip it nor
/// silence it.
String blankNonCode(String source) => _blank(source, literals: true);

/// Blanks comments only, leaving every string literal intact — for the one
/// guard that reads what the strings SAY (the SQL a repository builds) and so
/// cannot have them blanked out from under it.
///
/// Same single pass, so a `//` inside SQL is still not a comment.
String blankComments(String source) => _blank(source, literals: false);

String _blank(String source, {required bool literals}) {
  final out = StringBuffer();
  var i = 0;
  while (i < source.length) {
    // Comments.
    if (source.startsWith('//', i)) {
      final nl = source.indexOf('\n', i);
      final end = nl < 0 ? source.length : nl;
      out.write(' ' * (end - i));
      i = end;
      continue;
    }
    if (source.startsWith('/*', i)) {
      final close = source.indexOf('*/', i + 2);
      final end = close < 0 ? source.length : close + 2;
      out.write(' ' * (end - i));
      i = end;
      continue;
    }
    // String literals, longest opener first. A leading r/R makes it raw (no
    // escapes); the opening quote run is 3 or 1 characters. Either way the
    // literal is walked to its close — blanked when asked for, copied through
    // otherwise — because that walk is what keeps a `//` inside it from
    // reading as a comment.
    var j = i;
    var raw = false;
    if (source[j] == 'r' || source[j] == 'R') {
      if (j + 1 < source.length &&
          (source[j + 1] == "'" || source[j + 1] == '"')) {
        raw = true;
        j++;
      }
    }
    if (j < source.length && (source[j] == "'" || source[j] == '"')) {
      final quote = source[j];
      final triple = source.startsWith(quote * 3, j);
      final closer = triple ? quote * 3 : quote;
      var k = j + closer.length;
      while (k < source.length) {
        if (!raw && source[k] == r'\') {
          k += 2;
          continue;
        }
        if (!triple && source[k] == '\n') break; // unterminated; bail safely
        if (source.startsWith(closer, k)) {
          k += closer.length;
          break;
        }
        k++;
      }
      final end = k > source.length ? source.length : k;
      out.write(literals ? ' ' * (end - i) : source.substring(i, end));
      i = end;
      continue;
    }
    out.write(source[i]);
    i++;
  }
  return out.toString();
}

/// Every `.dart` file under [dir], deepest first order aside, sorted by path
/// so a failure names files in a stable order.
///
/// Generated output is excluded unless [includeGenerated]: a guard is a rule
/// about what people write, and `build_runner` output would drown every one of
/// them. The exception is a guard about the bytes on disk rather than the
/// code, which has to see the whole tree.
List<File> dartFiles(Directory dir, {bool includeGenerated = false}) =>
    dir
        .listSync(recursive: true)
        .whereType<File>()
        .where(
          (f) =>
              f.path.endsWith('.dart') &&
              (includeGenerated ||
                  (!f.path.endsWith('.g.dart') &&
                      !f.path.endsWith('.freezed.dart'))),
        )
        .toList()
      ..sort((a, b) => a.path.compareTo(b.path));

/// Every directory under `lib/features/` that can hold a widget: a feature's
/// subdirectories except `domain/` and `data/`, which are pure Dart and SQL.
///
/// Derived from the tree rather than listed, so a new feature — or a second
/// widget directory beside `presentation/`, the way `ingredients/barcode/` is
/// — is scanned the day it appears rather than the day someone remembers.
List<Directory> widgetDirs() =>
    Directory('lib/features')
        .listSync()
        .whereType<Directory>()
        .expand((feature) => feature.listSync().whereType<Directory>())
        .where(
          (d) => !const {'domain', 'data'}.contains(d.path.split('/').last),
        )
        .toList()
      ..sort((a, b) => a.path.compareTo(b.path));

/// The 1-based line number [offset] falls on in [source].
int lineOf(String source, int offset) =>
    '\n'.allMatches(source.substring(0, offset)).length + 1;
