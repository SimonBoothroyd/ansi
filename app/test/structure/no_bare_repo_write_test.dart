/// The invariant behind `lib/shared/write.dart`: **every repository write
/// reached from a widget goes through `ref.write(context, what, action)`.**
///
/// The rule is mechanical rather than stylistic because the stylistic version
/// already lost — the audit that opened this front found 37 of 38 UI→repository
/// writes with no failure surface at all. A paragraph in `AGENTS.md` does not
/// catch the 39th; this does, in `make test`.
///
/// **The write set is derived, not listed.** It is every `Future`-returning
/// method declared on a `domain/*_repository.dart` interface minus the named
/// read verbs below — so a repository method added tomorrow is covered the day
/// it is *declared*, which is the whole point.
///
/// **What it can be defeated by**, stated plainly because a regex over source
/// text should be honest about its reach: an aliased receiver whose call is
/// nested inside something other than the guard, a stored function reference
/// (`final f = repo.deleteSection; f(id);`), and anything inside a string
/// literal containing parentheses. It exists to stop the *ordinary* omission —
/// the one that happened 37 times — not a determined author.
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Directories under `lib/features/` whose `presentation/` the check scans.
///
/// It grows one feature per sweep commit, so the invariant is enforced from the
/// first sweep and no commit ever ships a red build or a temporary skip.
const _scannedFeatures = {'books'};

/// Interface methods that *read*. Everything else a repository declares is a
/// write and must go through the guard.
const _readVerbs = {
  'countBooks',
  'countRecipesIn',
  'search',
  'recentlyUsed',
  'byId',
  'byIds',
  'members',
  'aliases',
  'measuresByIngredients',
  'usedIn',
  'recipeReferences',
  'mostRecentWeekBefore',
  'componentLinkWouldCycle',
};

/// Deliberate exceptions, keyed `<path>:<method>`, each with its reason.
///
/// Keyed by method rather than by line so an edit above it does not silently
/// move the exemption onto a different call.
const _allowed = <String, String>{};

/// Declarations on a repository interface: two-space indent, a `Future<…>`
/// return type, a name, an open paren.
final _declaration = RegExp(r'^  Future<.*>\s+(\w+)\s*\(', multiLine: true);

/// Line comments blanked so prose naming a write method cannot trip the check.
String _stripComments(String source) => source
    .split('\n')
    .map((line) {
      final i = line.indexOf('//');
      return i < 0 ? line : line.substring(0, i);
    })
    .join('\n');

List<File> _dartFiles(Directory dir) =>
    dir
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

/// Whether the invocation starting at [index] is lexically an argument of a
/// `ref.write(` / `guardedWrite(` call.
///
/// Walks outward through the enclosing unclosed parentheses and asks what each
/// one belongs to, so a write nested a level deeper inside the guard's closure
/// still counts as guarded.
bool _insideGuard(String source, int index) {
  final head = RegExp(r'(?:\bguardedWrite|\.write)\s*(?:<[^<>()]*>)?\s*$');
  var depth = 0;
  for (var i = index - 1; i >= 0; i--) {
    final c = source[i];
    if (c == ')') {
      depth++;
    } else if (c == '(') {
      if (depth > 0) {
        depth--;
        continue;
      }
      if (head.hasMatch(source.substring(0, i))) return true;
    }
  }
  return false;
}

void main() {
  late final Set<String> writeMethods;

  setUpAll(() {
    final interfaces = Directory('lib/features')
        .listSync()
        .whereType<Directory>()
        .map((f) => Directory('${f.path}/domain'))
        .where((d) => d.existsSync())
        .expand(_dartFiles)
        .where((f) => f.path.endsWith('_repository.dart'));

    writeMethods = {
      for (final file in interfaces)
        for (final m in _declaration.allMatches(
          _stripComments(file.readAsStringSync()),
        ))
          m.group(1)!,
    }..removeAll(_readVerbs);
  });

  test('the write set is derived from the repository interfaces', () {
    // A sanity check on the derivation: if the regex or the interface layout
    // drifts, this fails loudly instead of passing over an empty set.
    expect(
      writeMethods,
      containsAll(<String>{
        'createBook',
        'deleteSection',
        'saveRecipe',
        'addEntry',
        'setEntryChecked',
        'createStub',
      }),
      reason: 'the derivation stopped seeing known write methods',
    );
    expect(
      writeMethods.intersection(_readVerbs),
      isEmpty,
      reason: 'a read verb leaked into the write set',
    );
  });

  test('every repository write in a view goes through ref.write', () {
    final violations = <String>[];
    var guarded = 0;
    var scanned = 0;

    for (final feature in _scannedFeatures) {
      final dir = Directory('lib/features/$feature/presentation');
      expect(
        dir.existsSync(),
        isTrue,
        reason: '$feature has no presentation/ — was it renamed?',
      );
      for (final file in _dartFiles(dir)) {
        scanned++;
        final source = _stripComments(file.readAsStringSync());
        final path = file.path;
        for (final m in RegExp(r'\.(\w+)\s*\(').allMatches(source)) {
          final name = m.group(1)!;
          if (!writeMethods.contains(name)) continue;
          if (_allowed.containsKey('$path:$name')) continue;
          if (_insideGuard(source, m.start)) {
            guarded++;
            continue;
          }
          final line = '\n'.allMatches(source.substring(0, m.start)).length + 1;
          violations.add('$path:$line — .$name(');
        }
      }
    }

    expect(scanned, greaterThan(0), reason: 'nothing scanned — broken glob?');
    expect(
      guarded,
      greaterThan(0),
      reason:
          'no guarded writes found in the scanned features — either the sweep '
          'was reverted or `ref.write` was renamed',
    );
    expect(
      violations,
      isEmpty,
      reason:
          'a repository write is called straight from a view. A throw there '
          'is invisible: the spinner stops and the user is told nothing. '
          'Wrap it:\n'
          "    ref.write(context, 'delete that section', "
          '() => repo.deleteSection(id))\n'
          'or add a `<path>:<method>` entry to _allowed with the reason.\n'
          '${violations.join('\n')}',
    );
  });

  test('allow-list entries still point at something', () {
    for (final key in _allowed.keys) {
      final path = key.substring(0, key.lastIndexOf(':'));
      final method = key.substring(key.lastIndexOf(':') + 1);
      expect(File(path).existsSync(), isTrue, reason: '$key: no such file');
      expect(
        File(path).readAsStringSync().contains('.$method('),
        isTrue,
        reason: '$key: the exempted call is gone — drop the entry',
      );
    }
  });
}
